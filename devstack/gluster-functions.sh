#!/bin/bash

# devstack/gluster-functions.sh
# Functions to control the installation and configuration of the **GlusterFS** storage

# Installs 3.6.3 version of glusterfs
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
        start_glusterfs
    fi

    create_glusterfs_disk
    sudo chmod 755 -R /var/log/glusterfs/
}

# Start gluster service
function start_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server start
    else
        sudo service glusterd start
    fi
}

# Stop running gluster service
function stop_glusterfs {
    if is_ubuntu; then
        sudo service glusterfs-server stop
    else
        sudo service glusterd stop
    fi
}

# Cleanup GlusterFS
function cleanup_glusterfs {
    local share
    local mount_point
    local glusterfs_volumes
    local vol_name

    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /");  do
        mount_point=$(grep $share /proc/mounts | awk '{print $2}')
        if [[ -n $mount_point ]]; then
            sudo umount $mount_point
        fi
    done

    for share in $(echo $GLANCE_GLUSTERFS_SHARE | sed "s/;/ /");  do
        local mount_point=$(grep $share /proc/mounts | awk '{print $2}')
        if [[ -n $mount_point ]]; then
            sudo umount $mount_point
        fi
    done

    if [[ -e ${GLUSTERFS_DISK_IMAGE} ]]; then
        sudo rm -f ${GLUSTERFS_DISK_IMAGE}
    fi

    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /"); do
        glusterfs_volumes+=,$(echo $share | cut -d/ -f2);
    done

    for share in $(echo $GLANCE_GLUSTERFS_SHARE | sed "s/;/ /"); do
        glusterfs_volumes+=,$(echo $share | cut -d/ -f2);
    done

    for vol_name in $(echo $glusterfs_volumes | sed "s/,/ /g"); do
        sudo gluster --mode=script volume stop $vol_name
        sudo gluster --mode=script volume delete $vol_name
    done

    if [[ "$OFFLINE" = "False" ]]; then
        uninstall_package glusterfs-server
    fi

    if egrep -q ${GLUSTERFS_DATA_DIR} /proc/mounts; then
        sudo umount ${GLUSTERFS_DATA_DIR}
    fi

    sudo rm -rf ${GLUSTERFS_DATA_DIR}
}

# Setting up glusterfs

function create_glusterfs_disk {
    # create a backing file disk
    create_disk ${GLUSTERFS_DISK_IMAGE} ${GLUSTERFS_DATA_DIR} ${GLUSTERFS_LOOPBACK_DISK_SIZE}
}

function create_gluster_volume {
    local glusterfs_volume=$1

    sudo mkdir -p ${GLUSTERFS_DATA_DIR}/$glusterfs_volume
    sudo gluster --mode=script volume \
            create $glusterfs_volume $(hostname):${GLUSTERFS_DATA_DIR}/$glusterfs_volume
    sudo gluster --mode=script volume start $glusterfs_volume
    sudo gluster --mode=script volume set $glusterfs_volume server.allow-insecure on
}

function create_gluster_volumes {
    local glusterfs_volumes=$1
    local vol_name

    for vol_name in $(echo $glusterfs_volumes | sed "s/,/ /g"); do
        create_gluster_volume $vol_name
    done
}

# Configure GlusterFS as a backend for Cinder
function configure_cinder_backend_glusterfs {
    local glusterfs_volumes
    local share

    for share in $(echo $CINDER_GLUSTERFS_SHARES | sed "s/;/ /"); do
        glusterfs_volumes+=,$(echo $share | cut -d/ -f2);
    done

    create_gluster_volumes $glusterfs_volumes

    # Changing file permissions of glusterfs logs.
    # This avoids creation of zero sized glusterfs log files while running CI job (Bug: 1455951).

    local be_name=$1
    iniset $CINDER_CONF $be_name volume_backend_name $be_name
    iniset $CINDER_CONF $be_name volume_driver "cinder.volume.drivers.glusterfs.GlusterfsDriver"
    iniset $CINDER_CONF $be_name glusterfs_shares_config "$CINDER_CONF_DIR/glusterfs-shares-$be_name.conf"
    #iniset $CINDER_CONF $be_name volume_prov_type $GLUSTERFS_VOLUME_PROV_TYPE

    if [[ -n "$CINDER_GLUSTERFS_SHARES" ]]; then
        CINDER_GLUSTERFS_SHARES=$(echo $CINDER_GLUSTERFS_SHARES | tr ";" "\n")
        echo "$CINDER_GLUSTERFS_SHARES" | tee "$CINDER_CONF_DIR/glusterfs-shares-$be_name.conf"
    fi
}
