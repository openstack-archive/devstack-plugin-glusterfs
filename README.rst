=========================
Devstack GlusterFS Plugin
=========================

Goals
-----

* To install GlusterFS (client and server) packages
* Creates GlusterFS volumes to provide them as shares to Cinder
* Configures Cinder with GlusterFS backend
* Also cleans up the GlusterFS volumes and data related to GlusterFS
* Uninstalls the Gluster packages when we run "unstack.sh"

Integrating GlusterFS plugin with DevStack
------------------------------------------

* For integrating devstack-glusterfs-plugin with DevStack see::

    ``./devstack/README.rst``

Useful links
------------

* Launchpad: https://launchpad.net/devstack-plugin-glusterfs
* Bugs filing: https://bugs.launchpad.net/devstack-plugin-glusterfs
* Blueprints filing: https://blueprints.launchpad.net/devstack-plugin-glusterfs
* Source code: https://git.openstack.org/cgit/openstack/devstack-plugin-glusterfs
* Source code mirror link: https://github.com/openstack/devstack-plugin-glusterfs
* For cloning: https://git.openstack.org/openstack/devstack-plugin-glusterfs
* Code review: https://review.openstack.org/#/q/status:open+project:openstack/devstack-plugin-glusterfs,n,z 
