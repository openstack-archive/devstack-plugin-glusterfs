#!/bin/bash

# devstack/gluster-functions.sh
# Functions to control the installation and configuration of the **GlusterFS** storage

# Installs 3.x version of glusterfs
# Triggered from devstack/plugin.sh as part of devstack "pre-install"
function install_glusterfs {
    if [[ ${DISTRO} =~ rhel7 ]] && [[ ! -f /etc/yum.repos.d/glusterfs-epel.repo ]]; then
        sudo wget $GLUSTERFS_CENTOS_REPO -O /etc/yum.repos.d/glusterfs-epel.repo
    elif is_ubuntu; then
        sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 3FE869A9
        if [ "$1" == "3.6" ]; then
            echo "deb http://ppa.launchpad.net/gluster/glusterfs-3.6/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/glusterfs-3_6.list
            echo "deb-src http://ppa.launchpad.net/gluster/glusterfs-3.6/ubuntu $(lsb_release -sc) main" | sudo tee --append /etc/apt/sources.list.d/glusterfs-3_6.list
        elif [ "$1" == "3.7" ]; then
            echo "deb http://ppa.launchpad.net/gluster/glusterfs-3.7/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/glusterfs-3_7.list
            echo "deb-src http://ppa.launchpad.net/gluster/glusterfs-3.7/ubuntu $(lsb_release -sc) main" | sudo tee --append /etc/apt/sources.list.d/glusterfs-3_7.list
        fi
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

    local vol_name
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

    # Cleaning up Cinder Backup GlusterFS shares
    if [ "$CONFIGURE_GLUSTERFS_CINDER_BACKUP" = "True" ]; then
        _delete_gluster_shares $CINDER_GLUSTERFS_BACKUP_SHARE
    fi
    # Cleaning up Glance GlusterFS share
    if [ "$CONFIGURE_GLUSTERFS_GLANCE" = "True" ]; then
        _delete_gluster_shares $GLANCE_GLUSTERFS_SHARE
    fi

    # Cleaning up Nova GlusterFS share
    if [ "$CONFIGURE_GLUSTERFS_NOVA" = "True" ]; then
        _delete_gluster_shares $NOVA_GLUSTERFS_SHARE
    fi

    # Clean up Manila GlusterFS
    if [ "$CONFIGURE_GLUSTERFS_MANILA" = "True" ]; then
        vols=$(sudo ls $MANILA_STATE_PATH/export)
        for vol_name in $vols; do
	    # Use '|| true' to continue if any of these commands fail.
            sudo gluster --mode=script vol stop $vol_name || true
            sudo gluster --mode=script vol delete $vol_name || true
            sudo rm -rf  $MANILA_STATE_PATH/export/$vol_name/brick || true
            sudo umount $MANILA_STATE_PATH/export/$vol_name || true
            sudo rmdir $MANILA_STATE_PATH/export/$vol_name || true
        done
        sudo lvremove -f $GLUSTERFS_VG_NAME || true
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
    iniset $CINDER_CONF $be_name nas_volume_prov_type $GLUSTERFS_VOLUME_PROV_TYPE

    if [[ -n "$CINDER_GLUSTERFS_SHARES" ]]; then
        CINDER_GLUSTERFS_SHARES=$(echo $CINDER_GLUSTERFS_SHARES | tr ";" "\n")
        echo "$CINDER_GLUSTERFS_SHARES" | tee "$CINDER_CONF_DIR/glusterfs-shares-$be_name.conf"
    fi
}


# Configure GlusterFS as Cinder backup target
# Triggered from plugin.sh
function configure_cinder_backup_backend_glusterfs {
    _create_gluster_volumes $CINDER_GLUSTERFS_BACKUP_SHARE

    iniset $CINDER_CONF DEFAULT backup_driver "cinder.backup.drivers.glusterfs"
    iniset $CINDER_CONF DEFAULT glusterfs_backup_share "$CINDER_GLUSTERFS_BACKUP_SHARE"
}

# Mount gluster volume
function _mount_gluster_volume {
    local mount_dir=$1
    local gluster_share=$2

    # Delete existing files in directory
    rm -rf $mount_dir
    mkdir -p $mount_dir

    sudo mount -t glusterfs $gluster_share $mount_dir
    sudo chown -R $STACK_USER:$STACK_USER $DATA_DIR
}

# Configure GlusterFS as a backend for Glance
function configure_glance_backend_glusterfs {
    _create_gluster_volumes $GLANCE_GLUSTERFS_SHARE

    _mount_gluster_volume $GLANCE_IMAGE_DIR $GLANCE_GLUSTERFS_SHARE
}

# Configure GlusterFS as a backend for Nova
function configure_nova_backend_glusterfs {
    _create_gluster_volumes $NOVA_GLUSTERFS_SHARE

    _mount_gluster_volume $NOVA_INSTANCES_PATH $NOVA_GLUSTERFS_SHARE
}

# Create Manila GlusterFS Volume
function _create_thin_lv_pool {
    # Create a Volume Group
    init_lvm_volume_group $GLUSTERFS_VG_NAME 20G

    # Create a thin pool
    sudo lvcreate -l 99%VG -T $GLUSTERFS_VG_NAME/$GLUSTERFS_THIN_POOL_NAME
}

# Creating Thin LV
function _create_thin_lv_gluster_vol {
    local vol_name=$1
    local vol_size=$2

    sudo lvcreate -V $vol_size -T $GLUSTERFS_VG_NAME/$GLUSTERFS_THIN_POOL_NAME -n $vol_name

    # Format the LV.
    test_with_retry "sudo mkfs.xfs -i size=512 /dev/$GLUSTERFS_VG_NAME/$vol_name" "mkfs.xfs failed"

    # Mount the filesystem
    if [ ! -d $MANILA_STATE_PATH/export/$vol_name ] ; then
	sudo mkdir -p $MANILA_STATE_PATH/export/$vol_name
    fi
    test_with_retry "sudo mount /dev/$GLUSTERFS_VG_NAME/$vol_name $MANILA_STATE_PATH/export/$vol_name" "mounting XFS from the LV failed"

    # Create a directory that would serve as a brick.
    sudo mkdir -p $MANILA_STATE_PATH/export/$vol_name/brick

    # Create a GlusterFS Volume.
    sudo gluster --mode=script vol create $vol_name $(hostname):$MANILA_STATE_PATH/export/$vol_name/brick

    # Start gluster volume
    sudo gluster --mode=script volume start $vol_name
}

# Configure manila.conf to use glusterfs.py driver
function _configure_manila_glusterfs {
    local share_driver=manila.share.drivers.glusterfs.GlusterfsShareDriver
    local group_name=$1
    local gluster_vol=$2

    iniset $MANILA_CONF $group_name share_driver $share_driver
    iniset $MANILA_CONF $group_name share_backend_name GLUSTERFS
    iniset $MANILA_CONF $group_name glusterfs_target $(hostname):/$gluster_vol
    iniset $MANILA_CONF $group_name driver_handles_share_servers False
}

# Configure glusterfs.py as backend driver for Manila
function _configure_manila_glusterfs_nfs {
    # Create Thin lvpool
    _create_thin_lv_pool

    # Create Gluster Volume
    _create_thin_lv_gluster_vol manila-glusterfs-vol 200G
    sudo chown -R $STACK_USER:$STACK_USER $MANILA_STATE_PATH/export
    sudo chmod -R 755 $MANILA_STATE_PATH/export

    # Configure manila.conf
    _configure_manila_glusterfs glusternfs1 manila-glusterfs-vol

    # Setting enabled_share_protocols to NFS
    iniset $MANILA_CONF DEFAULT enabled_share_protocols NFS

    # Overriding MANILA_ENABLED_BACKENDS to have only glusternfs1 backend
    MANILA_ENABLED_BACKENDS=glusternfs1

    # Setting enabled_share_backends
    iniset $MANILA_CONF DEFAULT enabled_share_backends $MANILA_ENABLED_BACKENDS
}


# Create necessary files required to support GlusterFS's TLS feature for the
# GlusterFS server running on the local host.
# Require a common name for the signed certificate that the function creates to
# be passed as a parameter.
function _configure_glusterfs_server_in_local_host_for_tls_support {

    local common_name=$1

    # Generate a private key.
    sudo openssl genrsa -out /etc/ssl/glusterfs.key 2048

    # Generate self-signed certicate with the common name passed to the
    # function.
    sudo openssl req -new -x509 -key /etc/ssl/glusterfs.key -subj /CN=$common_name -out /etc/ssl/glusterfs.pem

    # Create certificate authority file.
    sudo cp /etc/ssl/glusterfs.pem /etc/ssl/glusterfs.ca

}

# Setup and configure glusterfs_native.py as the backend share driver for Manila
function _configure_manila_glusterfs_native {


    # Create necessary files to allow GlusterFS volumes to use TLS features
    local common_name='glusterfs-server'
    _configure_glusterfs_server_in_local_host_for_tls_support $common_name

    # Create GlusterFS volumes to be used as shares.
    _create_thin_lv_pool

    local i
    for i in `seq 1 20`; do
        _create_thin_lv_gluster_vol manila-glusterfs-native-vol-20G-$i 20G
        # Configure the volume to use GlusterFS's TLS support required by the
        # native driver.
        sudo gluster vol set manila-glusterfs-native-vol-20G-$i auth.ssl-allow $common_name
    done

    # Configure manila.conf.
    local share_driver=manila.share.drivers.glusterfs_native.GlusterfsNativeShareDriver
    local group_name=glusternative1
    # Set "glusterfs_volume_pattern" option to be
    # "manila-glusterfs-native-vol-#{size}G-\d+$".
    local glusterfs_volume_pattern=manila-glusterfs-native-vol-#{size}G-\\\\d+$

    iniset $MANILA_CONF $group_name share_driver $share_driver
    iniset $MANILA_CONF $group_name share_backend_name GLUSTERFSNATIVE
    iniset $MANILA_CONF $group_name glusterfs_servers $(hostname)
    iniset $MANILA_CONF $group_name driver_handles_share_servers False
    iniset $MANILA_CONF $group_name glusterfs_volume_pattern $glusterfs_volume_pattern

    # Set enabled_share_protocols to be GLUSTERFS that is used by
    # glusterfs_native driver.
    iniset $MANILA_CONF DEFAULT enabled_share_protocols GLUSTERFS


    # Override MANILA_ENABLED_BACKENDS used in manila's devstack plugin.
    # This allows glusternative1 to be recognized as the enabled backend for
    # manila in the stack.sh run.
    MANILA_ENABLED_BACKENDS=$group_name

    # Set enabled_share_backends
    iniset $MANILA_CONF DEFAULT enabled_share_backends $group_name
}

function _setup_rootssh {
    mkdir -p "$HOME"/.ssh
    chmod 700 "$HOME"/.ssh
    sudo mkdir -p /root/.ssh
    sudo chmod 700 /root/.ssh
    yes n | ssh-keygen -f  "$HOME"/.ssh/id_rsa -N ''
    sudo sh -c "cat >> /root/.ssh/authorized_keys" < "$HOME"/.ssh/id_rsa.pub
    sudo chmod 600 /root/.ssh/authorized_keys
}

function _configure_setup_heketi {
    # get Heketi and start service
    wget "$HEKETI_V1_PACKAGE"
    tar xvf "$(basename "$HEKETI_V1_PACKAGE")"
    ( ./heketi/heketi -config "$GLUSTERFS_PLUGIN_DIR"/extras/heketi.json &>/dev/null & ) &

    # basic Heketi setup
    $GLUSTERFS_PLUGIN_DIR/extras/heketisetup.py -s 1T -n 3 -v -D $(hostname)
}

function _configure_manila_glusterfs_heketi {
    _setup_rootssh
    _configure_setup_heketi

    # Manila config
    local share_driver=manila.share.drivers.glusterfs.GlusterfsShareDriver
    local group_name=glusterheketi1

    iniset $MANILA_CONF $group_name share_driver $share_driver
    iniset $MANILA_CONF $group_name share_backend_name GLUSTERFSHEKETI
    iniset $MANILA_CONF $group_name driver_handles_share_servers False
    iniset $MANILA_CONF $group_name glusterfs_share_layout layout_heketi.GlusterfsHeketiLayout
    iniset $MANILA_CONF $group_name glusterfs_heketi_url http://localhost:8080
    iniset $MANILA_CONF $group_name glusterfs_heketi_nodeadmin_username root
    iniset $MANILA_CONF $group_name glusterfs_heketi_volume_replica 1
}

# Configure GlusterFS as a backend for Manila
function configure_manila_backend_glusterfs {
    case "$GLUSTERFS_MANILA_DRIVER_TYPE" in
    glusterfs|glusterfs-nfs)
        _configure_manila_glusterfs_nfs
        ;;
    glusterfs-heketi|glusterfs-nfs-heketi)
        _configure_manila_glusterfs_heketi
        ;;
    glusterfs-native)
        _configure_manila_glusterfs_native
        ;;
    *)
        echo "no configuration hook for GLUSTERFS_MANILA_DRIVER_TYPE=${GLUSTERFS_MANILA_DRIVER_TYPE}"
        ;;
    esac
}
