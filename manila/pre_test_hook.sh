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

# This script is executed inside pre_test_hook function in devstack gate.

localrc_path=$BASE/new/devstack/localrc
echo "DEVSTACK_GATE_TEMPEST_ALLOW_TENANT_ISOLATION=1" >> $localrc_path
echo "API_RATE_LIMIT=False" >> $localrc_path
echo "TEMPEST_SERVICES+=,manila" >> $localrc_path

echo "MANILA_USE_DOWNGRADE_MIGRATIONS=True" >> $localrc_path
echo "MANILA_MULTI_BACKEND=False" >> $localrc_path

# Import env vars defined in CI job.
for env_var in ${DEVSTACK_LOCAL_CONFIG// / }; do
    export $env_var;
done

# If the job tests glusterfs (NFS) driver, then create default share_type with
# extra_spec snapshot_support as False. Becasuse the job that tests the
# glusterfs (NFS) driver tests the directory based layout that doesn't support
# snapshots. The job that tests glusterfs (NFS) driver has a name that
# ends with "glusterfs".
if [[ "$GLUSTERFS_MANILA_DRIVER_TYPE" == "glusterfs" ]]; then
    echo "MANILA_DEFAULT_SHARE_TYPE_EXTRA_SPECS='snapshot_support=False'" >> $localrc_path
fi

# Enabling isolated metadata in Neutron is required because
# Tempest creates isolated networks and created vm's in scenario tests don't
# have access to Nova Metadata service. This leads to unavailability of
# created vm's in scenario tests.
echo 'ENABLE_ISOLATED_METADATA=True' >> $localrc_path

# Go to Tempest dir and checkout stable commit to avoid possible
# incompatibilities for plugin stored in Manila repo.
cd $BASE/new/tempest
source $BASE/new/manila/contrib/ci/common.sh
# In lack of $MANILA_TEMPEST_COMMIT fall back to the old hardcoded
# Tempest commit.
git checkout ${MANILA_TEMPEST_COMMIT:-3b1bb9be3265f}

# Print current Tempest status
git status
