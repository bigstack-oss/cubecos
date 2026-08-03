# gunicorn settings for the horizon dashboard.
#
# Horizon moved into the python 3.10 venv at /opt/openstack-antelope, and
# mod_wsgi is built against the system python 3.9, so httpd can no longer host
# the application in-process. It reverse-proxies this socket instead, the same
# arrangement keystone, barbican and monasca-api already use.

# apache is both the socket's owner and its only client, so the default umask
# is enough here -- unlike monasca and barbican, which need a group-writable
# socket because their application runs as a different user than httpd.
bind = "unix:/var/lib/openstack-dashboard/horizon.socket"
user = "apache"
group = "apache"

# httpd strips the /horizon prefix before proxying (ProxyPass maps /horizon onto
# the socket root), so gunicorn has to put it back: horizon's URLconf is rooted
# at '' and WEBROOT only prefixes LOGIN_URL, STATIC_URL and MEDIA_URL, not the
# reverse() output. WSGIScriptAlias used to supply SCRIPT_NAME for free.
# gunicorn reads it from the environment; the systemd unit exports it.

# The mod_wsgi setup this replaces ran on WSGIDaemonProcess defaults: one
# process, 15 threads. gthread with a handful of workers is the closer match to
# that -- it is what makes threads meaningful -- and it survives a worker dying
# mid-request, which the single-process layout did not.
workers = 4
threads = 8
worker_class = "gthread"

# Django renders some of the admin tables (hypervisors, instances across all
# projects) with several sequential API calls behind them, so the 30s barbican
# and monasca use is too tight here.
timeout = 60
backlog = 2048
keepalive = 2
proc_name = "horizon"

# gunicorn's own log goes to the file the unit appends to. The application logs
# separately through LOGGING in local_settings, and apache already records the
# access log.
loglevel = "info"
