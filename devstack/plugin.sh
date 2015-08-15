#!/bin/bash

# devstack/plugin.sh
# Triggers glusterfs specific functions to install and configure GlusterFS

# Dependencies:
#
# - ``functions`` file
# - ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_glusterfs
# - start_glusterfs
# - configure_cinder_backend_glusterfs
# - configure_glance_backend_glusterfs
# - configure_nova_backend_glusterfs
# - configure_manila_backend_glusterfs
# - stop_glusterfs
# - cleanup_glusterfs

# Defaults
# --------

# Set CONFIGURE_GLUSTERFS_CINDER to true, to enable GlusterFS as a backend for Cinder.
CONFIGURE_GLUSTERFS_CINDER=${CONFIGURE_GLUSTERFS_CINDER:-True}

# Set CONFIGURE_GLUSTERFS_GLANCE to true, to configure GlusterFS as a backend for Glance.
CONFIGURE_GLUSTERFS_GLANCE=${CONFIGURE_GLUSTERFS_GLANCE:-False}

# Set CONFIGURE_GLUSTERFS_NOVA to true, to configure GlusterFS as a backend for Nova.
CONFIGURE_GLUSTERFS_NOVA=${CONFIGURE_GLUSTERFS_NOVA:-False}

# Set CONFIGURE_GLUSTERFS_MANILA to true, to configure GlusterFS as a backend for Manila.
CONFIGURE_GLUSTERFS_MANILA=${CONFIGURE_GLUSTERFS_MANILA:-False}

# Set GLUSTERFS_MANILA_DRIVER_TYPE to either 'glusterfs' or 'glusterfs-native'.
GLUSTERFS_MANILA_DRIVER_TYPE=${GLUSTERFS_MANILA_DRIVER_TYPE:-glusterfs}

# Set GLUSTERFS_VG_NAME to the name of volume group.
GLUSTERFS_VG_NAME=${GLUSTERFS_VG_NAME:-glusterfs-vg}

# Set GLUSTERFS_THIN_POOL_NAME to the name of thinpool.
GLUSTERFS_THIN_POOL_NAME=${GLUSTERFS_THIN_POOL_NAME:-glusterfs-thinpool}

# Error out when devstack-plugin-glusterfs is enabled, but not selected as a backend for Cinder, Glance or Nova.
if [ "$CONFIGURE_GLUSTERFS_CINDER" = "False" ] && [ "$CONFIGURE_GLUSTERFS_GLANCE" = "False" ] && [ "$CONFIGURE_GLUSTERFS_NOVA" = "False" ] && [ "$CONFIGURE_GLUSTERFS_MANILA" = "False" ];  then
    echo "GlusterFS plugin enabled but not selected as a backend for Cinder, Glance, Nova or Manila."
    echo "Please set CONFIGURE_GLUSTERFS_CINDER, CONFIGURE_GLUSTERFS_GLANCE, CONFIGURE_GLUSTERFS_NOVA and/or CONFIGURE_GLUSTERFS_MANILA to True in localrc."
    exit 1
fi

# When CONFIGURE_GLUSTERFS_CINDER is true, CINDER_ENABLED_BACKENDS should have
# at least one backend of type 'glusterfs', error out otherwise.
local is_gluster_backend_configured=False
for be in ${CINDER_ENABLED_BACKENDS//,/ }; do
    if [ "${be%%:*}" = "glusterfs" ]; then
        is_gluster_backend_configured=True
        break
    fi
done
if [ "$CONFIGURE_GLUSTERFS_CINDER" = "True" ] && [ "$is_gluster_backend_configured" = "False" ]; then
    echo "CONFIGURE_GLUSTERFS_CINDER is set to True, to configure GlusterFS as a backend for Cinder."
    echo "But, glusterfs backend type not present in CINDER_ENABLED_BACKENDS."
    echo "Please enable at least one backend of type glusterfs in CINDER_ENABLED_BACKENDS."
    exit 1
elif [ "$CONFIGURE_GLUSTERFS_CINDER" = "False" ] && [ "$is_gluster_backend_configured" = "True" ]; then
    echo "Configured Glusterfs as backend type in CINDER_ENABLED_BACKENDS. But CONFIGURE_GLUSTERFS_CINDER set to False."
    exit 1
fi

# GLUSTERFS_PLUGIN_DIR contains the path to devstack-plugin-glusterfs/devstack directory
GLUSTERFS_PLUGIN_DIR=$(readlink -f $(dirname ${BASH_SOURCE[0]}))

# Set ``GLUSTERFS_DATA_DIR`` to the location of GlusterFS drives.
# Default is /var/lib/glusterfs.
GLUSTERFS_DATA_DIR=${GLUSTERFS_DATA_DIR:-/var/lib/glusterfs}
GLUSTERFS_DISK_IMAGE=${DATA_DIR}/cinder/glusterfs.img

# DevStack will create a loop-back disk formatted as XFS to store the
# GlusterFS data. Set ``GLUSTERFS_LOOPBACK_DISK_SIZE`` to the disk size in
# GB.
# Default is 4 gigabyte. But we can configure through localrc.
GLUSTERFS_LOOPBACK_DISK_SIZE=${GLUSTERFS_LOOPBACK_DISK_SIZE:-4G}

# Devstack will create GlusterFS shares to store Cinder volumes.
# Those shares can be configured by seting CINDER_GLUSTERFS_SHARES.
# By default CINDER_GLUSTERFS_SHARES="127.0.0.1:/vol1"
CINDER_GLUSTERFS_SHARES=${CINDER_GLUSTERFS_SHARES:-"127.0.0.1:/cinder-vol"}

# Glance GlusterFS share
GLANCE_GLUSTERFS_SHARE=${GLANCE_GLUSTERFS_SHARE:-"127.0.0.1:/glance-vol"}

# Glance Nova share
NOVA_GLUSTERFS_SHARE=${NOVA_GLUSTERFS_SHARE:-"127.0.0.1:/nova-vol"}

# Adding GlusterFS repo to CentOS / RHEL 7 platform.
GLUSTERFS_CENTOS_REPO=${GLUSTERFS_CENTOS_REPO:-"http://download.gluster.org/pub/gluster/glusterfs/LATEST/CentOS/glusterfs-epel.repo"}

# Initializing gluster specific functions
source $GLUSTERFS_PLUGIN_DIR/gluster-functions.sh

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing GlusterFS"
    install_glusterfs
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if is_service_enabled glance && [[ "$CONFIGURE_GLUSTERFS_GLANCE" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Glance"
        configure_glance_backend_glusterfs
    fi
    if is_service_enabled nova && [[ "$CONFIGURE_GLUSTERFS_NOVA" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Nova"
        configure_nova_backend_glusterfs
    fi
    if is_service_enabled manila && [[ "$CONFIGURE_GLUSTERFS_MANILA" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Manila"
        configure_manila_backend_glusterfs
    fi
fi

if [[ "$1" == "unstack" ]]; then
    cleanup_glusterfs
    stop_glusterfs
fi

if [[ "$1" == "clean" ]]; then
    cleanup_glusterfs
fi

## Local variables:
## mode: shell-script
## End:
