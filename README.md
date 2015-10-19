Devstack GlusterFS Plugin
=========================

# Goals

* To install GlusterFS (client and server) packages
* Creates GlusterFS volumes to provide them as shares to Cinder
* Configures Cinder with GlusterFS backend
* Also cleans up the GlusterFS volumes and data related to GlusterFS
* Uninstalls the Gluster packages when we run "unstack.sh"

# How to use

* Add "enable_plugin glusterfs https://git.openstack.org/openstack/devstack-plugin-glusterfs" to localrc file inside devstack.
* Then run "stack.sh"
