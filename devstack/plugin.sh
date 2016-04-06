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
# - configure_cinder_backup_backend_glusterfs
# - configure_glance_backend_glusterfs
# - configure_nova_backend_glusterfs
# - configure_manila_backend_glusterfs
# - stop_glusterfs
# - cleanup_glusterfs

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "Installing GlusterFS 3.7"
    install_glusterfs 3.7
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if is_service_enabled c-bak && [[ "$CONFIGURE_GLUSTERFS_CINDER_BACKUP" == "True" ]]; then
        echo_summary "Configuring GlusterFS as a backend for Cinder backup driver"
        configure_cinder_backup_backend_glusterfs
    fi
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
elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
    # Changing file permissions of glusterfs logs.
    # This avoids creation of zero sized glusterfs log files while running CI job (Bug: 1455951).
    for  p in "" logs logs/glusterfs logs/glusterfs/quota-mount-manila-glusterfs-vol.log; do
        for t in "" /; do
            echo "Running: ls -ld $WORKSPACE/$p$t"
            ls -ld "$WORKSPACE/$p$t"
        done
    done
    sudo chmod 755 -R /var/log/glusterfs/
    sudo find "$WORKSPACE" -type d -exec chmod 755 {} \;
    sudo find "$WORKSPACE" -name '*.log' -type f -exec chmod 644 {} \;
    for  p in "" logs logs/glusterfs logs/glusterfs/quota-mount-manila-glusterfs-vol.log; do
        for t in "" /; do
            echo "Running again: ls -ld $WORKSPACE/$p$t"
            ls -ld "$WORKSPACE/$p$t"
        done
    done

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
