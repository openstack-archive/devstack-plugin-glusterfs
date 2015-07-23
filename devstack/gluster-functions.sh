#!/bin/bash

# devstack/gluster-functions.sh
# Functions to control the installation and configuration of the **GlusterFS** storage

# Installs 3.6.x version of glusterfs
# Triggered from devstack/plugin.sh as part of devstack "pre-install"
function install_glusterfs {
    if [[ ${DISTRO} =~ rhel7 ]] && [[ ! -f /etc/yum.repos.d/glusterfs-epel.repo ]]; then
        sudo wget $GLUSTERFS_CENTOS_REPO -O /etc/yum.repos.d/glusterfs-epel.repo
    elif is_ubuntu; then
        sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 3FE869A9
        echo "deb http://ppa.launchpad.net/gluster/glusterfs-3.6/ubuntu trusty main" | sudo tee /etc/apt/sources.list.d/glusterfs-3_6-trusty.list
        echo "deb-src http://ppa.launchpad.net/gluster/glusterfs-3.6/ubuntu trusty main" | sudo tee --append /etc/apt/sources.list.d/glusterfs-3_6-trusty.list
        NO_UPDATE_REPOS=False
        REPOS_UPDATED=False
    fi

    install_package glusterfs-server
    install_package xfsprogs

    if is_fedora; then
        stop_glusterfs
        _start_glusterfs
    fi

    _create_glusterfs_disk

    # Changing file permissions of glusterfs logs.
    # This avoids creation of zero sized glusterfs log files while running CI job (Bug: 1455951).
    sudo chmod 755 -R /var/log/glusterfs/
}

# Start gluster service
function _start_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server start
    else
        sudo service glusterd start
    fi
}

# Stop running gluster service
# Triggered from devstack/plugin.sh as part of devstack "unstack"
function stop_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server stop
    else
        sudo service glusterd stop
    fi
}

# Clean Shares
function _umount_shares {
    local shares=$1
    local share
    local mount_point
    for share in $(echo $shares | sed "s/;/ /");  do
        mount_point=$(grep $share /proc/mounts | awk '{print $2}')
        if [[ -n $mount_point ]]; then
            sudo umount $mount_point
        fi
    done
}

# Delete gluster volumes
function _delete_gluster_shares {
    local shares=$1
    local share
    local gluster_volumes
    _umount_shares $shares

    for share in $(echo $shares | sed "s/;/ /"); do
        gluster_volumes+=,$(echo $share | cut -d/ -f2);
    done

    for vol_name in $(echo $gluster_volumes | sed "s/,/ /g"); do
        sudo gluster --mode=script volume stop $vol_name
        sudo gluster --mode=script volume delete $vol_name
    done
}

# Cleanup GlusterFS
# Triggered from devstack/plugin.sh as part of devstack "clean"
function cleanup_glusterfs {
    local glusterfs_volumes
    local vol_name

    # Cleaning up Cinder GlusterFS shares
    if [ "$CONFIGURE_GLUSTERFS_CINDER" = "True" ]; then
        _delete_gluster_shares $CINDER_GLUSTERFS_SHARES
    fi

    if [[ -e ${GLUSTERFS_DISK_IMAGE} ]]; then
        sudo rm -f ${GLUSTERFS_DISK_IMAGE}
    fi

    if [[ "$OFFLINE" = "False" ]]; then
        uninstall_package glusterfs-server
    fi

    if egrep -q ${GLUSTERFS_DATA_DIR} /proc/mounts; then
        sudo umount ${GLUSTERFS_DATA_DIR}
    fi

    sudo rm -rf ${GLUSTERFS_DATA_DIR}
}

# Setting up glusterfs
function _create_glusterfs_disk {
    # create a backing file disk
    local disk_image_directory=$(dirname "${GLUSTERFS_DISK_IMAGE}")
    mkdir -p $disk_image_directory
    create_disk ${GLUSTERFS_DISK_IMAGE} ${GLUSTERFS_DATA_DIR} ${GLUSTERFS_LOOPBACK_DISK_SIZE}
}

function _create_gluster_volume {
    local glusterfs_volume=$1

    sudo mkdir -p ${GLUSTERFS_DATA_DIR}/$glusterfs_volume
    sudo gluster --mode=script volume \
            create $glusterfs_volume $(hostname):${GLUSTERFS_DATA_DIR}/$glusterfs_volume
    sudo gluster --mode=script volume start $glusterfs_volume
    sudo gluster --mode=script volume set $glusterfs_volume server.allow-insecure on
}

function _create_gluster_volumes {
    local gluster_shares=$1
    local share
    local glusterfs_volumes
    for share in $(echo $gluster_shares | sed "s/;/ /"); do
        glusterfs_volumes+=,$(echo $share | cut -d/ -f2);
    done

    local vol_name

    for vol_name in $(echo $glusterfs_volumes | sed "s/,/ /g"); do
        _create_gluster_volume $vol_name
    done
}

# Configure GlusterFS as a backend for Cinder
# Triggered from stack.sh
function configure_cinder_backend_glusterfs {
    _create_gluster_volumes $CINDER_GLUSTERFS_SHARES

    local be_name=$1
    iniset $CINDER_CONF $be_name volume_backend_name $be_name
    iniset $CINDER_CONF $be_name volume_driver "cinder.volume.drivers.glusterfs.GlusterfsDriver"
    iniset $CINDER_CONF $be_name glusterfs_shares_config "$CINDER_CONF_DIR/glusterfs-shares-$be_name.conf"

    if [[ -n "$CINDER_GLUSTERFS_SHARES" ]]; then
        CINDER_GLUSTERFS_SHARES=$(echo $CINDER_GLUSTERFS_SHARES | tr ";" "\n")
        echo "$CINDER_GLUSTERFS_SHARES" | tee "$CINDER_CONF_DIR/glusterfs-shares-$be_name.conf"
    fi
}
