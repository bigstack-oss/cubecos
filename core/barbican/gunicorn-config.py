import multiprocessing

bind = "unix:/var/lib/barbican/barbican.socket"
# workers = 2
# threads = 8
user = "barbican"
group = "barbican"
umask = 0o002

timeout = 30
backlog = 2048
keepalive = 2

workers = multiprocessing.cpu_count() * 2

# Logging configuration
loglevel = 'info'
# errorlog = '-'
# accesslog = '-'
accesslog = "/var/log/barbican/barbican_access.log"
errorlog = "/var/log/barbican/barbican_error.log"
