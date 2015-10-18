Devstack GlusterFS Plugin
================

# Goals

* To install Glusterfs (client and server) packages
* Configures Glusterfs as a backend for Glance, Nova, Cinder and Manila
* Creates Gluster volumes to provide them as storage to Glance, Nova, Cinder and Manila
* Also cleans up the Gluster volumes and data related to Gluster
* Uninstalls the Gluster packages when we run "unstack.sh"

# How to use (localrc configuration)

* Enable devstack-plugin-glusterfs plugin:
     [[local|localrc]]
     enable_plugin devstack-plugin-glusterfs https://github.com/stackforge/devstack-plugin-glusterfs

* To enable Gluster as a backend for Glance:
     CONFIGURE_GLUSTERFS_GLANCE=True

* To enable Gluster as a backend for Nova:
     CONFIGURE_GLUSTERFS_NOVA=True

* To enable Gluster as a backend for Cinder:
     CONFIGURE_GLUSTERFS_CINDER=True
  Also we can enable/disable glusterfs as a backend for Cinder Backup (c-bak) driver:
     enable_service c-bak
     CONFIGURE_GLUSTERFS_CINDER_BACKEND=[True OR False] # By default set to True when CONFIGURE_GLUSTERFS_CINDER=True

* To enable Gluster as a backend for Manila:
     CONFIGURE_GLUSTERFS_MANILA=True
  Also select specific gluster backend type for manila, default is "glusterfs":
     GLUSTERFS_MANILA_DRIVER_TYPE=[glusterfs OR glusterfs-native]

* Then run "stack.sh"
