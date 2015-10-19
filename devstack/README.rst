==============================
Enabling glusterfs in Devstack
==============================

1. Download DevStack::

    git clone https://git.openstack.org/openstack-dev/devstack
    cd devstack

2. Add this repo as an external repository in ``local.conf`` file::

    [[local|localrc]]
    enable_plugin glusterfs https://git.openstack.org/openstack/devstack-plugin-glusterfs

3. Run ``stack.sh``.
