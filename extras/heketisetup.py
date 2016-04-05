#!/usr/bin/env python

# Copyright (c) 2016 Red Hat, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

from __future__ import print_function
import datetime
import hashlib
import pipes
import re
import subprocess
import sys
import time

try:
    import jwt
except ImportError:
    print("jwt module not found, Heketi JWT auth won't work.\n"
          "You can install it with 'pip install PyJWT'.\n", file=sys.stderr)
import requests


class Objlog(object):

    def __init__(self, obj):
        self.object = obj
        self.__log__ = []

    def __getattr__(self, att):
        av = getattr(self.object, att)

        if not hasattr(av, '__call__'):
            return av

        def alog(*a, **kw):
            try:
                ret = av(*a, **kw)
            except Exception as x:
                self.__log__.append(((att, a, kw), None, x))
                raise x
            self.__log__.append(((att, a, kw), ret))
            return ret

        return alog

    def __reset__(self):
        self.__log__ = []


def objlog_get(ol):
    return ol.__log__


def reqlog(req, lower=0, upper=None):
    ol = objlog_get(req)
    if upper is None:
        upper = len(ol)
    for i in range(lower, upper):
        e = ol[i]
        print(i, e[0])
        print(e[1], e[1].headers, e[1].text)


class HeketiException(Exception):
    pass


def jwt_token(method, path, key, issuer="admin", delta={'minutes': 5}):
    method = method.upper()
    path = re.sub("\A/+", "/", "/" + path)

    claims = {}

    # Issuer
    claims['iss'] = issuer

    # Issued at time
    claims['iat'] = datetime.datetime.utcnow()

    # Expiration time
    claims['exp'] = (datetime.datetime.utcnow() +
                     datetime.timedelta(**delta))

    # URI tampering protection
    claims['qsh'] = hashlib.sha256(method + '&' + path).hexdigest()

    return jwt.encode(claims, key, algorithm='HS256')


class HeketiClient(object):
    """A client class for the Heteki GlusterFS management service."""

    def __init__(self, host, requests_like=requests, jwt_key=None):
        host_stripped = re.sub("/+\Z", "", host)
        self.__host__ = host_stripped
        self.__requests__ = requests_like
        self.__jwt_key__ = jwt_key

    def __getattr__(self, attr):
        attr_value = getattr(self.__requests__, attr)

        if not hasattr(attr_value, '__call__'):
            return attr_value

        def _attr_value_host_injected(*a, **kw):
            if len(a) == 0:
                return attr_value(*a, **kw)
            else:
                path = a[0]
                path_stripped = re.sub("\A/+", "", path)
                req_url = "/".join((self.__host__, path_stripped))
                if self.__jwt_key__:
                    token = jwt_token(attr, path, self.__jwt_key__)
                    kw['headers'] = {"Authorization": "bearer %s" % token}
                report("Heketi request %(method)s to %(url)s" % {
                    'method': attr.upper(), 'url': req_url})
                resp = attr_value(req_url, *a[1:], **kw)
                report("Heketi response: %s" % repr(resp))
                return resp

        return _attr_value_host_injected

    def asyncop(self, *a, **kw):
        method = kw.pop('method', 'post')
        retry_interval = kw.pop('retry_interval', 1)
        resp = getattr(self, method)(*a, **kw)
        if resp.status_code != 202:
            resp.raise_for_status()
            raise HeketiException((
                'Unexpected Heketi async %(method)s status %(status)d'
            ) % {'method': method.upper(), 'status': resp.status_code})
        queue = resp.headers['location']
        while True:
            resp = self.get(queue)
            if resp.status_code == 204:
                return resp
            elif resp.status_code == 303:
                return self.get(resp.headers['location'])
            elif resp.status_code == 200:
                if 'x-pending' not in resp.headers:
                    return resp
            else:
                resp.raise_for_status()
                raise HeketiException((
                   'Unexpected Heketi async queue status %d'
                ) % resp.status_code)
            time.sleep(retry_interval)


class ShExec(object):

    def __init__(self, host, user=None, key=None, root=False):
        self.host = host
        self.root = root
        self.args = []
        if host == "localhost":
            self.args = ["sh", "-c"]
        else:
            self.args = ["ssh", host]
            if user:
                self.args.extend(["-l", user])
            if key:
                self.args.extend(["-i", key])

    def __call__(self, cmd):
        if not self.root:
            cmd = "sudo sh -c " + pipes.quote(cmd)
        report("Running on %(host)s: %(cmd)s" % {
               'cmd': cmd, 'host': self.host})
        po = subprocess.Popen(self.args + [cmd],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = po.communicate()
        report("Command output: %s" % out, cond=out)
        if po.returncode:
            raise RuntimeError("%(cmd)s has failed with %(exit)d" % {
                'cmd': ' '.join(self.args) + ' ' + cmd,
                'exit': po.returncode})
        return out, err


def setup(clusters, args, h):
    cluster = args.cluster
    if not cluster and clusters:
        cluster = clusters[0]
    if cluster not in clusters:
        if re.match('[\da-f]{8}(-?[\da-f]{4}){3}-?[\da-f]{12}\Z',
                    cluster or '', re.I):
            raise HeketiException(
                "Cluster %s not found on Heketi server." % cluster)
        cluster = None
    if not cluster:
        cluster = h.post("clusters").json()['id']
    report("Using cluster %s" % cluster)

    hostdevices = {}
    for host in args.host:
        hostdevices[host] = []
        shx = ShExec(host, user=args.user, key=args.key, root=args.root)
        for _ in range(args.devices):
            dev, _ = shx("i=0; while [ -f /LOOP%(cluster)s-$i ]; do i=$(($i+1)); done && "
                         "truncate -s %(size)s /LOOP%(cluster)s-$i && "
                         "losetup -f --show /LOOP%(cluster)s-$i" % {'size': args.size,
                         'cluster': cluster})
            hostdevices[host].append(dev.strip())

    for host, devices in hostdevices.items():
        # add a node
        node = h.asyncop("nodes", json={
                  "zone": 1,
                  "hostnames": {"manage": [host], "storage": [host]},
                  "cluster": cluster}).json()
        for dev in devices:
            # add a device
            h.asyncop("devices", json={"node": node['id'], "name": dev})


def teardown(clusters, args, h):
    if args.cluster not in clusters:
        raise HeketiException(
            "Cluster %s not found on Heketi server." % args.cluster)

    cluster = h.get("clusters/%s" % args.cluster).json()
    for vol in cluster["volumes"]:
        h.asyncop('volumes/%s' % vol, method='delete')
    for nodeid in cluster["nodes"]:
        node = h.get("nodes/%s" % nodeid).json()
        for dev in node["devices"]:
            h.asyncop('devices/%s' % dev['id'], method='delete')
            for host in node["hostnames"]["storage"]:
                shx = ShExec(host, user=args.user, key=args.key, root=args.root)
                qname = pipes.quote(dev['name'])
                backfile, _ = shx("losetup --list -Oback-file --noheadings %s" % qname)
                shx("losetup -d %s" % qname)
                shx("rm %s" % pipes.quote(backfile.strip()))
        h.asyncop('nodes/%s' % nodeid, method='delete')
    h.delete("clusters/%s" % args.cluster)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("host", nargs='+')
    parser.add_argument("-v", "--verbose", action='store_true')
    parser.add_argument("-H", "--heketi", default="http://localhost:8080",
                        help="Heketi service URL")
    parser.add_argument("-s", "--size", help="size of devices created")
    parser.add_argument("-n", "--devices",
                        help="number of devices created per node", type=int)
    parser.add_argument("-c", "--cluster", help="Heketi cluster to use")
    parser.add_argument("-j", "--jwt", help="JWT key to use with Heketi auth")
    parser.add_argument("-u", "--user", default="heketi",
                        help="user with which nodes are managed")
    parser.add_argument("-k", "--key", help="SSH key used to log in remotely")
    parser.add_argument("--root", action='store_true',
                        help="remote user has root privileges")
    parser.add_argument("-A", "--action", choices=('setup', 'teardown'),
                        default='setup')
    parser.add_argument("-D", "--debug", action='store_true')
    args = parser.parse_args()

    if args.jwt:
        jwt
    if args.verbose:
        def report(*a, **kw):
            if not kw.pop('cond', True):
                return
            print(*a, **kw)
    else:
        report = lambda *a, **kw: None

    req = requests.session()
    if args.debug:
        req = Objlog(req)
    heketi = HeketiClient(args.heketi, requests_like=req, jwt_key=args.jwt)

    try:
        # get a cluster
        clusters = heketi.get("clusters").json()['clusters']
        getattr(sys.modules[__name__], args.action)(clusters, args, heketi)
    finally:
        if args.debug:
            reqlog(req)
