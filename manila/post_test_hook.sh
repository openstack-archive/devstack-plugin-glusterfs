#!/bin/bash -xe
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# This script is executed inside post_test_hook function in devstack gate.

TEMPEST_CONFIG=$BASE/new/tempest/etc/tempest.conf

sudo chown -R jenkins:stack $BASE/new/tempest
sudo chown -R jenkins:stack $BASE/data/tempest
sudo chmod -R o+rx $BASE/new/devstack/files

# Import devstack functions 'iniset'
source $BASE/new/devstack/functions

# Import env vars defined in CI job.
for env_var in ${DEVSTACK_LOCAL_CONFIG// / }; do
    export $env_var;
done

if [[ "${GLUSTERFS_MANILA_DRIVER_TYPE}" == "glusterfs-native" ]]; then
    local BACKEND_NAME="GLUSTERNATIVE"
    iniset $TEMPEST_CONFIG share enable_protocols glusterfs
    iniset $TEMPEST_CONFIG share storage_protocol glusterfs
    # Disable tempest config option that enables creation of 'ip' type access
    # rules by default during tempest test runs.
    iniset $TEMPEST_CONFIG share enable_ip_rules_for_protocols
    iniset $TEMPEST_CONFIG share enable_cert_rules_for_protocols glusterfs
    iniset $TEMPEST_CONFIG share capability_snapshot_support True
    # ro access_level is not supported by the driver.
    iniset $TEMPEST_CONFIG share enable_ro_access_level_for_protocols
else
    case "$GLUSTERFS_MANILA_DRIVER_TYPE" in
    "glusterfs|glusterfs-nfs")
        local BACKEND_NAME="GLUSTERFS"
        ;;
    "glusterfs-heketi|glusterfs-nfs-heketi")
        local BACKEND_NAME="GLUSTERFSHEKETI"
        iniset $TEMPEST_CONFIG share capability_snapshot_support True
        ;;
    *)
        echo "no BACKEND_NAME for GLUSTERFS_MANILA_DRIVER_TYPE=${GLUSTERFS_MANILA_DRIVER_TYPE}"
        ;;
    esac
    iniset $TEMPEST_CONFIG share enable_protocols nfs
    iniset $TEMPEST_CONFIG share enable_ip_rules_for_protocols nfs
    iniset $TEMPEST_CONFIG share storage_protocol NFS
    # ro access_level is not supported by the driver.
    iniset $TEMPEST_CONFIG share enable_ro_access_level_for_protocols
fi


iniset $TEMPEST_CONFIG share backend_names $BACKEND_NAME

# Set two retries for CI jobs
iniset $TEMPEST_CONFIG share share_creation_retry_number 2

# Suppress errors in cleanup of resources
SUPPRESS_ERRORS=${SUPPRESS_ERRORS_IN_CLEANUP:-True}
iniset $TEMPEST_CONFIG share suppress_errors_in_cleanup $SUPPRESS_ERRORS


# Disable multi_backend tests
RUN_MANILA_MULTI_BACKEND_TESTS=${RUN_MANILA_MULTI_BACKEND_TESTS:-False}
iniset $TEMPEST_CONFIG share multi_backend $RUN_MANILA_MULTI_BACKEND_TESTS

# Disable manage/unmanage tests
RUN_MANILA_MANAGE_TESTS=${RUN_MANILA_MANAGE_TESTS:-False}
iniset $TEMPEST_CONFIG share run_manage_unmanage_tests $RUN_MANILA_MANAGE_TESTS

# Disable extend tests
RUN_MANILA_EXTEND_TESTS=${RUN_MANILA_EXTEND_TESTS:-False}
iniset $TEMPEST_CONFIG share run_extend_tests $RUN_MANILA_EXTEND_TESTS

# Disable shrink tests
RUN_MANILA_SHRINK_TESTS=${RUN_MANILA_SHRINK_TESTS:-False}
iniset $TEMPEST_CONFIG share run_shrink_tests $RUN_MANILA_SHRINK_TESTS

# Disable multi_tenancy tests
iniset $TEMPEST_CONFIG share multitenancy_enabled False

# Disable snapshot tests
RUN_MANILA_SNAPSHOT_TESTS=${RUN_MANILA_SNAPSHOT_TESTS:-False}
iniset $TEMPEST_CONFIG share run_snapshot_tests $RUN_MANILA_SNAPSHOT_TESTS

# Disable consistency group tests
RUN_MANILA_CG_TESTS=${RUN_MANILA_CG_TESTS:-False}
iniset $TEMPEST_CONFIG share run_consistency_group_tests $RUN_MANILA_CG_TESTS

# let us control if we die or not
set +o errexit
cd $BASE/new/tempest

export MANILA_TEMPEST_CONCURRENCY=${MANILA_TEMPEST_CONCURRENCY:-12}
export MANILA_TESTS=${MANILA_TESTS:-'manila_tempest_tests.tests.api'}

# check if tempest plugin was installed correctly
echo 'import pkg_resources; print list(pkg_resources.iter_entry_points("tempest.test_plugins"))' | python

# Workaround for Tempest architectural changes (only for Liberty and lower releases)
# See bugs:
# 1) https://bugs.launchpad.net/manila/+bug/1531049
# 2) https://bugs.launchpad.net/tempest/+bug/1524717
ADMIN_TENANT_NAME=${ADMIN_TENANT_NAME:-"admin"}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"secretadmin"}
iniset $TEMPEST_CONFIG auth admin_username ${ADMIN_USERNAME:-"admin"}
iniset $TEMPEST_CONFIG auth admin_password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG auth admin_tenant_name $ADMIN_TENANT_NAME
iniset $TEMPEST_CONFIG auth admin_domain_name ${ADMIN_DOMAIN_NAME:-"Default"}
iniset $TEMPEST_CONFIG identity username ${TEMPEST_USERNAME:-"demo"}
iniset $TEMPEST_CONFIG identity password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG identity tenant_name ${TEMPEST_TENANT_NAME:-"demo"}
iniset $TEMPEST_CONFIG identity alt_username ${ALT_USERNAME:-"alt_demo"}
iniset $TEMPEST_CONFIG identity alt_password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG identity alt_tenant_name ${ALT_TENANT_NAME:-"alt_demo"}
iniset $TEMPEST_CONFIG validation ip_version_for_ssh 4
iniset $TEMPEST_CONFIG validation ssh_timeout $BUILD_TIMEOUT
iniset $TEMPEST_CONFIG validation network_for_ssh ${PRIVATE_NETWORK_NAME:-"private"}

echo "Running tempest manila test suites"
sudo -H -u jenkins tox -eall-plugin $MANILA_TESTS -- --concurrency=$MANILA_TEMPEST_CONCURRENCY

_retval=$?

# This is a hack to work around EPERM issue upon
# uploading log files: we ensure that the logs
# shall land in a VFAT mount, whereby POSIX file
# permissions are not implemented (everything is
# world readable).
install_package dosfstools
truncate -s 3g /tmp/fat.img
mkdosfs /tmp/fat.img
sudo mkdir "$WORKSPACE/logs/glusterfs"
sudo mount /tmp/fat.img "$WORKSPACE/logs/glusterfs"

(exit $_retval)
