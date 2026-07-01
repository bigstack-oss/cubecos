#!/opt/openstack-antelope/bin/python3.10
import os

bind = "unix:/var/lib/keystone/keystone.socket"
workers = 5
threads = 1
user = "keystone"
group = "keystone"
umask = 0o002

# Logging configuration
accesslog = "/var/log/keystone/keystone_access.log"
errorlog = "/var/log/keystone/keystone_error.log"

# Clean sys.argv before loading the application so oslo.config doesn't crash
import sys
sys.argv = [sys.argv[0]]
