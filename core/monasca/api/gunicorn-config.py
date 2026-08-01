# gunicorn settings for monasca-api.
#
# "gunicorn --paste" only loads the application out of api-config.ini; the
# [server:main] section of a paste ini is honoured by paster/pserve, not by
# gunicorn, so everything below has to live in a gunicorn config file of its own
# (same split barbican uses).

# The socket httpd reverse-proxies port 8070 onto. monasca-api moved into the
# python 3.10 venv and mod_wsgi is built against the system python 3.9, so httpd
# can no longer host the application in-process.
bind = "unix:/var/lib/monasca/monasca-api.socket"
user = "monasca"
group = "monasca"
# Group-writable so apache, which is a member of the monasca group, can connect.
umask = 0o002

# Straight translation of the WSGIDaemonProcess line monasca-api-wsgi.conf.in
# used to carry: processes=8 threads=4.
#
# Not eventlet, which is what upstream's [server:main] suggests: gunicorn 20.1.0
# imports eventlet.wsgi.ALREADY_HANDLED, dropped in eventlet 0.33, and the venv
# is on 0.33.1 per the antelope constraints. gunicorn 21 fixed it, but gunicorn
# is shared with keystone and barbican here. gthread is the closer match to the
# mod_wsgi setup being replaced anyway -- it is what makes threads meaningful.
workers = 8
threads = 4
worker_class = "gthread"

timeout = 30
backlog = 2048
keepalive = 2
proc_name = "monasca-api"

# gunicorn's own log goes to the file the unit appends to. The application logs
# separately through api-logging.conf, and apache already records the access log.
loglevel = "info"
