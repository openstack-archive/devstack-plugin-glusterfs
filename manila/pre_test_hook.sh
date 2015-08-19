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

# JOB_NAME is defined in openstack-infra/config project
# used by CI/CD, where this script is intended to be used.
if [[ "$JOB_NAME" =~ "multibackend" ]]; then
    echo "MANILA_MULTI_BACKEND=True" >> $localrc_path
else
    echo "MANILA_MULTI_BACKEND=False" >> $localrc_path
fi

# Enabling isolated metadata in Neutron is required because
# Tempest creates isolated networks and created vm's in scenario tests don't
# have access to Nova Metadata service. This leads to unavailability of
# created vm's in scenario tests.
echo 'ENABLE_ISOLATED_METADATA=True' >> $localrc_path

# Go to Tempest dir and checkout stable commit to avoid possible
# incompatibilities for plugin stored in Manila repo.
TEMPEST_COMMIT="489f5e62"  # 15 June, 2015
cd $BASE/new/tempest
git checkout $TEMPEST_COMMIT

# Print current Tempest status
git status

# Install Manila Tempest integration
cp -r $BASE/new/manila/contrib/tempest/tempest/* $BASE/new/tempest/tempest
