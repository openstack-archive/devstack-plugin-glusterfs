#!/bin/bash

# devstack/plugin.sh
# Triggers glusterfs specific functions to install and configure GlusterFS

# Dependencies:
#
# - ``functions`` file
# - ``GLUSTERFS_DATA_DIR`` or ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_glusterfs
# - configure_glusterfs_cinder & configure_privileged_user
# - start_glusterfs
# - stop_glusterfs
# - cleanup_glusterfs

# Defaults
# --------

# GLUSTERFS_PLUGIN_DIR contains the path to devstack-plugin-glusterfs/devstack directory
GLUSTERFS_PLUGIN_DIR=$(readlink -f $(dirname ${BASH_SOURCE[0]}))

# Set ``GLUSTERFS_DATA_DIR`` to the location of GlusterFS drives.
# Default is the common DevStack data directory.
GLUSTERFS_DATA_DIR=${GLUSTERFS_DATA_DIR:-/var/lib/glusterfs}
GLUSTERFS_DISK_IMAGE=${DATA_DIR}/cinder/glusterfs.img

# DevStack will create a loop-back disk formatted as XFS to store the
# GlusterFS data. Set ``GLUSTERFS_LOOPBACK_DISK_SIZE`` to the disk size in
# kilobytes.
# Default is 4 gigabyte. But we can configure through localrc.
GLUSTERFS_LOOPBACK_DISK_SIZE=${GLUSTERFS_LOOPBACK_DISK_SIZE:-4G}

# Devstack will create GlusterFS shares to store Cinder volumes.
# Those shares can be configured by seting CINDER_GLUSTERFS_SHARES.
# By default CINDER_GLUSTERFS_SHARES="127.0.0.1:/vol1"
CINDER_GLUSTERFS_SHARES=${CINDER_GLUSTERFS_SHARES:-"127.0.0.1:/vol1"}

# Glusterfs volume provisioned type, allowed values are 'thin' or 'thick'.
# Since we only support raw volumes for backup, using 'thick' as default value.
GLUSTERFS_VOLUME_PROV_TYPE=${GLUSTERFS_VOLUME_PROV_TYPE:-"thick"}

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
