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
# - stop_glusterfs
# - cleanup_glusterfs

# Defaults
# --------

# Set CONFIGURE_GLUSTERFS_CINDER to true, to enable GlusterFS as a backend for Cinder.
CONFIGURE_GLUSTERFS_CINDER=${CONFIGURE_GLUSTERFS_CINDER:-True}

# Error out when devstack-plugin-glusterfs is enabled, but not selected as a backend for cinder.
if [ "$CONFIGURE_GLUSTERFS_CINDER" = "False" ]; then
    echo "GlusterFS plugin enabled but not selected as a backend for Cinder."
    echo "Please set CONFIGURE_GLUSTERFS_CINDER to True in localrc."
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

# Adding GlusterFS repo to CentOS / RHEL 7 platform.
GLUSTERFS_CENTOS_REPO=${GLUSTERFS_CENTOS_REPO:-"http://download.gluster.org/pub/gluster/glusterfs/LATEST/CentOS/glusterfs-epel.repo"}

# Initializing gluster specific functions
source $GLUSTERFS_PLUGIN_DIR/gluster-functions.sh

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing GlusterFS"
    install_glusterfs
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
