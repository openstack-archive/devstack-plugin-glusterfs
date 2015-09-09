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

sudo chown -R jenkins:stack $BASE/new/tempest
sudo chown -R jenkins:stack $BASE/data/tempest
sudo chmod -R o+rx $BASE/new/devstack/files

# Import devstack functions 'iniset'
source $BASE/new/devstack/functions



if [[ "$JOB_NAME" =~ "glusterfs-native" ]]; then
    local BACKEND_NAME="GLUSTERNATIVE"
    iniset $BASE/new/tempest/etc/tempest.conf share enable_protocols glusterfs
    iniset $BASE/new/tempest/etc/tempest.conf share storage_protocol GLUSTERFS
    iniset $BASE/new/tempest/etc/tempest.conf share enable_cert_rules_for_protocols glusterfs
else
    local BACKEND_NAME="GLUSTERFS"
    iniset $BASE/new/tempest/etc/tempest.conf share enable_protocols nfs
    iniset $BASE/new/tempest/etc/tempest.conf share enable_ip_rules_for_protocols nfs
    iniset $BASE/new/tempest/etc/tempest.conf share storage_protocol NFS
fi


iniset $BASE/new/tempest/etc/tempest.conf share backend_names $BACKEND_NAME

# Set two retries for CI jobs
iniset $BASE/new/tempest/etc/tempest.conf share share_creation_retry_number 2

# Suppress errors in cleanup of resources
SUPPRESS_ERRORS=${SUPPRESS_ERRORS_IN_CLEANUP:-True}
iniset $BASE/new/tempest/etc/tempest.conf share suppress_errors_in_cleanup $SUPPRESS_ERRORS


# Disable multi_backend tests
RUN_MANILA_MULTI_BACKEND_TESTS=${RUN_MANILA_MULTI_BACKEND_TESTS:-False}
iniset $BASE/new/tempest/etc/tempest.conf share multi_backend $RUN_MANILA_MULTI_BACKEND_TESTS

# Disable manage/unmanage tests
RUN_MANILA_MANAGE_TESTS=${RUN_MANILA_MANAGE_TESTS:-False}
iniset $BASE/new/tempest/etc/tempest.conf share run_manage_unmanage_tests $RUN_MANILA_MANAGE_TESTS

# Disable extend tests
RUN_MANILA_EXTEND_TESTS=${RUN_MANILA_EXTEND_TESTS:-False}
iniset $BASE/new/tempest/etc/tempest.conf share run_extend_tests $RUN_MANILA_EXTEND_TESTS

# Disable shrink tests
RUN_MANILA_SHRINK_TESTS=${RUN_MANILA_SHRINK_TESTS:-False}
iniset $BASE/new/tempest/etc/tempest.conf share run_shrink_tests $RUN_MANILA_SHRINK_TESTS

# Disable multi_tenancy tests
iniset $BASE/new/tempest/etc/tempest.conf share multitenancy_enabled False

# Disable snapshot tests
RUN_MANILA_SNAPSHOT_TESTS=${RUN_MANILA_SNAPSHOT_TESTS:-False}
iniset $BASE/new/tempest/etc/tempest.conf share run_snapshot_tests $RUN_MANILA_SNAPSHOT_TESTS

# let us control if we die or not
set +o errexit
cd $BASE/new/tempest

export MANILA_TEMPEST_CONCURRENCY=${MANILA_TEMPEST_CONCURRENCY:-12}
export MANILA_TESTS=${MANILA_TESTS:-'manila_tempest_tests.tests.api'}

if [[ "$JOB_NAME" =~ "scenario" ]]; then
    echo "Set test set to scenario only"
    MANILA_TESTS='manila_tempest_tests.tests.scenario'
fi

# check if tempest plugin was installed correctly
echo 'import pkg_resources; print list(pkg_resources.iter_entry_points("tempest.test_plugins"))' | python

echo "Running tempest manila test suites"
sudo -H -u jenkins tox -eall-plugin $MANILA_TESTS -- --concurrency=$MANILA_TEMPEST_CONCURRENCY
