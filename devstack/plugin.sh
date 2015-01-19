# 60-glusterfs.sh - DevStack extras script to install GlusterFS
# Functions to control the configuration and operation of the **GlusterFS** storage service

# Dependencies:
#
# - ``functions`` file
# - ``GLUSTERFS_DATA_DIR`` or ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_glusterfs
# - configure_glusterfs_cinder
# - start_glusterfs
# - stop_glusterfs
# - cleanup_glusterfs

# Defaults
# --------

# Set ``GLUSTERFS_DATA_DIR`` to the location of GlusterFS drives.
# Default is the common DevStack data directory.
GLUSTERFS_DATA_DIR=${GLUSTERFS_DATA_DIR:-/var/lib/glusterfs}
GLUSTERFS_DISK_IMAGE=${DATA_DIR}/cinder/glusterfs.img

# DevStack will create a loop-back disk formatted as XFS to store the
# GlusterFS data. Set ``GLUSTERFS_LOOPBACK_DISK_SIZE`` to the disk size in
# kilobytes.
# Default is 4 gigabyte.
GLUSTERFS_LOOPBACK_DISK_SIZE=${GLUSTERFS_LOOPBACK_DISK_SIZE:-4G}

# Devstack will create GlusterFS shares to store Cinder volumes.
# Those shares can be configured by seting CINDER_GLUSTERFS_SHARES.
# By default CINDER_GLUSTERFS_SHARES="127.0.0.1:/vol1;127.0.0.1:/vol2"

CINDER_GLUSTERFS_SHARES=${CINDER_GLUSTERFS_SHARES:-"127.0.0.1:/vol1;127.0.0.1:/vol2"}

# Adding GlusterFS repo to CentOS / RHEL 7 platform.

GLUSTERFS_CENTOS_REPO=${GLUSTERFS_CENTOS_REPO:-"http://download.gluster.org/pub/gluster/glusterfs/LATEST/CentOS/glusterfs-epel.repo"}

# Functions
# ------------

# cleanup_glusterfs() - Remove residual data files, anything left over from previous
# runs that a clean run would need to clean up
function cleanup_glusterfs {
    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /");  do
        local mount_point=$(grep $share /proc/mounts | awk '{print $2}')
        if [[ -n $mount_point ]]; then
            sudo umount $mount_point
        fi
    done

    if [[ -e ${GLUSTERFS_DISK_IMAGE} ]]; then
        sudo rm -f ${GLUSTERFS_DISK_IMAGE}
    fi

    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /"); do
        GLUSTERFS_VOLUMES+=,$(echo $share | cut -d/ -f2);
    done

    for vol_name in $(echo $GLUSTERFS_VOLUMES | sed "s/,/ /g"); do
        sudo gluster --mode=script volume stop $vol_name
        sudo gluster --mode=script volume delete $vol_name
    done

    uninstall_package glusterfs-server
    if egrep -q ${GLUSTERFS_DATA_DIR} /proc/mounts; then
        sudo umount ${GLUSTERFS_DATA_DIR}
    fi
    sudo rm -rf ${GLUSTERFS_DATA_DIR}
}

# configure_glusterfs_cinder() - Create GlusterFS volumes
function configure_glusterfs_cinder {
    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /"); do
        GLUSTERFS_VOLUMES+=,$(echo $share | cut -d/ -f2);
    done

    if is_fedora; then
        stop_glusterfs
        start_glusterfs
    fi
    # create a backing file disk
    create_disk ${GLUSTERFS_DISK_IMAGE} ${GLUSTERFS_DATA_DIR} ${GLUSTERFS_LOOPBACK_DISK_SIZE}

    for vol_name in $(echo $GLUSTERFS_VOLUMES | sed "s/,/ /g"); do
        sudo mkdir -p ${GLUSTERFS_DATA_DIR}/$vol_name
        sudo gluster --mode=script volume \
            create $vol_name $(hostname):${GLUSTERFS_DATA_DIR}/$vol_name
        sudo gluster --mode=script volume start $vol_name
        sudo gluster --mode=script volume set $vol_name server.allow-insecure on
    done
}

# install_glusterfs() - Collect source and prepare
function install_glusterfs {
    if [[ ${DISTRO} =~ rhel7 ]] && [[ ! -f /etc/yum.repos.d/glusterfs-epel.repo ]]; then
        sudo  wget $GLUSTERFS_CENTOS_REPO -O /etc/yum.repos.d/glusterfs-epel.repo
    fi
    install_package glusterfs-server
    install_package xfsprogs
}

# start_glusterfs() - Start running processes
function start_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server start
    else
        sudo service glusterd start
    fi
}

# stop_glusterfs() - Stop running processes
function stop_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server stop
    else
        sudo service glusterd stop
    fi
}

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing GlusterFS"
    install_glusterfs
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if is_service_enabled cinder; then
        echo_summary "Configuring Cinder for GlusterFS"
        configure_glusterfs_cinder
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
