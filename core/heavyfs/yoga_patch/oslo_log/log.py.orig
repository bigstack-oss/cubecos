# Copyright 2011 OpenStack Foundation.
# Copyright 2010 United States Government as represented by the
# Administrator of the National Aeronautics and Space Administration.
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

"""OpenStack logging handler.

This module adds to logging functionality by adding the option to specify
a context object when calling the various log methods.  If the context object
is not specified, default formatting is used. Additionally, an instance uuid
may be passed as part of the log message, which is intended to make it easier
for admins to find messages related to a specific instance.

It also allows setting of formatting information through conf.

"""

import configparser
import logging
import logging.config
import logging.handlers
import os
import platform
import sys
try:
    import syslog
except ImportError:
    syslog = None

from oslo_config import cfg
from oslo_utils import importutils
from oslo_utils import units

from oslo_log._i18n import _
from oslo_log import _options
from oslo_log import formatters
from oslo_log import handlers

CRITICAL = logging.CRITICAL
FATAL = logging.FATAL
ERROR = logging.ERROR
WARNING = logging.WARNING
WARN = logging.WARNING
INFO = logging.INFO
DEBUG = logging.DEBUG
NOTSET = logging.NOTSET
TRACE = handlers._TRACE

logging.addLevelName(TRACE, 'TRACE')

LOG_ROTATE_INTERVAL_MAPPING = {
    'seconds': 's',
    'minutes': 'm',
    'hours': 'h',
    'days': 'd',
    'weekday': 'w',
    'midnight': 'midnight'
}


def _get_log_file_path(conf, binary=None):
    logfile = conf.log_file
    logdir = conf.log_dir

    if logfile and not logdir:
        return logfile

    if logfile and logdir:
        return os.path.join(logdir, logfile)

    if logdir:
        binary = binary or handlers._get_binary_name()
        return '%s.log' % (os.path.join(logdir, binary),)

    return None


def _iter_loggers():
    """Iterate on existing loggers."""

    # Sadly, Logger.manager and Manager.loggerDict are not documented,
    # but there is no logging public function to iterate on all loggers.

    # The root logger is not part of loggerDict.
    yield logging.getLogger()

    manager = logging.Logger.manager
    for logger in manager.loggerDict.values():
        if isinstance(logger, logging.PlaceHolder):
            continue
        yield logger


class BaseLoggerAdapter(logging.LoggerAdapter):

    warn = logging.LoggerAdapter.warning

    @property
    def handlers(self):
        return self.logger.handlers

    def trace(self, msg, *args, **kwargs):
        self.log(TRACE, msg, *args, **kwargs)


class KeywordArgumentAdapter(BaseLoggerAdapter):
    """Logger adapter to add keyword arguments to log record's extra data

    Keywords passed to the log call are added to the "extra"
    dictionary passed to the underlying logger so they are emitted
    with the log message and available to the format string.

    Special keywords:

    extra
      An existing dictionary of extra values to be passed to the
      logger. If present, the dictionary is copied and extended.
    resource
      A dictionary-like object containing a ``name`` key or ``type``
       and ``id`` keys.

    """

    def process(self, msg, kwargs):
        # Make a new extra dictionary combining the values we were
        # given when we were constructed and anything from kwargs.
        extra = {}
        extra.update(self.extra)
        if 'extra' in kwargs:
            extra.update(kwargs.pop('extra'))
        # Move any unknown keyword arguments into the extra
        # dictionary.
        for name in list(kwargs.keys()):
            if name == 'exc_info':
                continue
            extra[name] = kwargs.pop(name)
        # NOTE(dhellmann): The gap between when the adapter is called
        # and when the formatter needs to know what the extra values
        # are is large enough that we can't get back to the original
        # extra dictionary easily. We leave a hint to ourselves here
        # in the form of a list of keys, which will eventually be
        # attributes of the LogRecord processed by the formatter. That
        # allows the formatter to know which values were original and
        # which were extra, so it can treat them differently (see
        # JSONFormatter for an example of this). We sort the keys so
        # it is possible to write sane unit tests.
        extra['extra_keys'] = list(sorted(extra.keys()))
        # Place the updated extra values back into the keyword
        # arguments.
        kwargs['extra'] = extra

        # NOTE(jdg): We would like an easy way to add resource info
        # to logging, for example a header like 'volume-<uuid>'
        # Turns out Nova implemented this but it's Nova specific with
        # instance.  Also there's resource_uuid that's been added to
        # context, but again that only works for Instances, and it
        # only works for contexts that have the resource id set.
        resource = kwargs['extra'].get('resource', None)
        if resource:

            # Many OpenStack resources have a name entry in their db ref
            # of the form <resource_type>-<uuid>, let's just use that if
            # it's passed in
            if not resource.get('name', None):

                # For resources that don't have the name of the format we wish
                # to use (or places where the LOG call may not have the full
                # object ref, allow them to pass in a dict:
                # resource={'type': volume, 'id': uuid}

                resource_type = resource.get('type', None)
                resource_id = resource.get('id', None)

                if resource_type and resource_id:
                    kwargs['extra']['resource'] = ('[' + resource_type +
                                                   '-' + resource_id + '] ')
            else:
                # FIXME(jdg): Since the name format can be specified via conf
                # entry, we may want to consider allowing this to be configured
                # here as well
                kwargs['extra']['resource'] = ('[' + resource.get('name', '')
                                               + '] ')

        return msg, kwargs


def _create_logging_excepthook(product_name):
    def logging_excepthook(exc_type, value, tb):
        extra = {'exc_info': (exc_type, value, tb)}
        getLogger(product_name).critical('Unhandled error', **extra)
    return logging_excepthook


class LogConfigError(Exception):

    message = _('Error loading logging config %(log_config)s: %(err_msg)s')

    def __init__(self, log_config, err_msg):
        self.log_config = log_config
        self.err_msg = err_msg

    def __str__(self):
        return self.message % dict(log_config=self.log_config,
                                   err_msg=self.err_msg)


def _load_log_config(log_config_append):
    try:
        if not hasattr(_load_log_config, "old_time"):
            _load_log_config.old_time = 0
        new_time = os.path.getmtime(log_config_append)
        if _load_log_config.old_time != new_time:
            # Reset all existing loggers before reloading config as fileConfig
            # does not reset non-child loggers.
            for logger in _iter_loggers():
                logger.setLevel(logging.NOTSET)
                logger.handlers = []
                logger.propagate = 1
            logging.config.fileConfig(log_config_append,
                                      disable_existing_loggers=False)
            _load_log_config.old_time = new_time
    except (configparser.Error, KeyError, os.error) as exc:
        raise LogConfigError(log_config_append, str(exc))


def _mutate_hook(conf, fresh):
    """Reconfigures oslo.log according to the mutated options."""

    if (None, 'debug') in fresh:
        _refresh_root_level(conf.debug)

    if (None, 'log-config-append') in fresh:
        _load_log_config.old_time = 0
    if conf.log_config_append:
        _load_log_config(conf.log_config_append)


def register_options(conf):
    """Register the command line and configuration options used by oslo.log."""

    # Sometimes logging occurs before logging is ready (e.g., oslo_config).
    # To avoid "No handlers could be found," temporarily log to sys.stderr.
    root_logger = logging.getLogger(None)
    if not root_logger.handlers:
        root_logger.addHandler(logging.StreamHandler())

    conf.register_cli_opts(_options.common_cli_opts)
    conf.register_cli_opts(_options.logging_cli_opts)
    conf.register_opts(_options.generic_log_opts)
    conf.register_opts(_options.log_opts)
    formatters._store_global_conf(conf)

    conf.register_mutate_hook(_mutate_hook)


def setup(conf, product_name, version='unknown'):
    """Setup logging for the current application."""
    if conf.log_config_append:
        _load_log_config(conf.log_config_append)
    else:
        _setup_logging_from_conf(conf, product_name, version)
    sys.excepthook = _create_logging_excepthook(product_name)


def set_defaults(logging_context_format_string=None,
                 default_log_levels=None):
    """Set default values for the configuration options used by oslo.log."""
    # Just in case the caller is not setting the
    # default_log_level. This is insurance because
    # we introduced the default_log_level parameter
    # later in a backwards in-compatible change
    if default_log_levels is not None:
        cfg.set_defaults(
            _options.log_opts,
            default_log_levels=default_log_levels)
    if logging_context_format_string is not None:
        cfg.set_defaults(
            _options.log_opts,
            logging_context_format_string=logging_context_format_string)


def tempest_set_log_file(filename):
    """Provide an API for tempest to set the logging filename.

    .. warning:: Only Tempest should use this function.

    We don't want applications to set a default log file, so we don't
    want this in set_defaults(). Because tempest doesn't use a
    configuration file we don't have another convenient way to safely
    set the log file default.

    """
    cfg.set_defaults(_options.logging_cli_opts, log_file=filename)


def _find_facility(facility):
    # NOTE(jd): Check the validity of facilities at run time as they differ
    # depending on the OS and Python version being used.
    valid_facilities = [f for f in
                        ["LOG_KERN", "LOG_USER", "LOG_MAIL",
                         "LOG_DAEMON", "LOG_AUTH", "LOG_SYSLOG",
                         "LOG_LPR", "LOG_NEWS", "LOG_UUCP",
                         "LOG_CRON", "LOG_AUTHPRIV", "LOG_FTP",
                         "LOG_LOCAL0", "LOG_LOCAL1", "LOG_LOCAL2",
                         "LOG_LOCAL3", "LOG_LOCAL4", "LOG_LOCAL5",
                         "LOG_LOCAL6", "LOG_LOCAL7"]
                        if getattr(syslog, f, None)]

    facility = facility.upper()

    if not facility.startswith("LOG_"):
        facility = "LOG_" + facility

    if facility not in valid_facilities:
        raise TypeError(_('syslog facility must be one of: %s') %
                        ', '.join("'%s'" % fac
                                  for fac in valid_facilities))

    return getattr(syslog, facility)


def _refresh_root_level(debug):
    """Set the level of the root logger.

    :param debug: If 'debug' is True, the level will be DEBUG.
     Otherwise the level will be INFO.
    """
    log_root = getLogger(None).logger
    if debug:
        log_root.setLevel(logging.DEBUG)
    else:
        log_root.setLevel(logging.INFO)


def _setup_logging_from_conf(conf, project, version):
    log_root = getLogger(None).logger

    # Remove all handlers
    for handler in list(log_root.handlers):
        log_root.removeHandler(handler)

    logpath = _get_log_file_path(conf)
    if logpath:
        # On Windows, in-use files cannot be moved or deleted.
        if conf.watch_log_file and platform.system() == 'Linux':
            from oslo_log import watchers
            file_handler = watchers.FastWatchedFileHandler
            filelog = file_handler(logpath)
        elif conf.log_rotation_type.lower() == "interval":
            file_handler = logging.handlers.TimedRotatingFileHandler
            when = conf.log_rotate_interval_type.lower()
            interval_type = LOG_ROTATE_INTERVAL_MAPPING[when]
            # When weekday is configured, "when" has to be a value between
            # 'w0'-'w6' (w0 for Monday, w1 for Tuesday, and so on)'
            if interval_type == 'w':
                interval_type = interval_type + str(conf.log_rotate_interval)
            filelog = file_handler(logpath,
                                   when=interval_type,
                                   interval=conf.log_rotate_interval,
                                   backupCount=conf.max_logfile_count)
        elif conf.log_rotation_type.lower() == "size":
            file_handler = logging.handlers.RotatingFileHandler
            maxBytes = conf.max_logfile_size_mb * units.Mi
            filelog = file_handler(logpath,
                                   maxBytes=maxBytes,
                                   backupCount=conf.max_logfile_count)
        else:
            file_handler = logging.handlers.WatchedFileHandler
            filelog = file_handler(logpath)

        log_root.addHandler(filelog)

    if conf.use_stderr:
        streamlog = handlers.ColorHandler()
        log_root.addHandler(streamlog)

    if conf.use_journal:
        if syslog is None:
            raise RuntimeError("syslog is not available on this platform")
        facility = _find_facility(conf.syslog_log_facility)
        journal = handlers.OSJournalHandler(facility=facility)
        log_root.addHandler(journal)

    if conf.use_eventlog:
        if platform.system() == 'Windows':
            eventlog = logging.handlers.NTEventLogHandler(project)
            log_root.addHandler(eventlog)
        else:
            raise RuntimeError(_("Windows Event Log is not available on this "
                                 "platform."))

    # if None of the above are True, then fall back to standard out
    if not logpath and not conf.use_stderr and not conf.use_journal:
        # pass sys.stdout as a positional argument
        # python2.6 calls the argument strm, in 2.7 it's stream
        streamlog = handlers.ColorHandler(sys.stdout)
        log_root.addHandler(streamlog)

    if conf.publish_errors:
        handler = importutils.import_object(
            "oslo_messaging.notify.log_handler.PublishErrorsHandler",
            logging.ERROR)
        log_root.addHandler(handler)

    if conf.use_syslog:
        if syslog is None:
            raise RuntimeError("syslog is not available on this platform")
        facility = _find_facility(conf.syslog_log_facility)
        syslog_handler = handlers.OSSysLogHandler(facility=facility)
        log_root.addHandler(syslog_handler)

    datefmt = conf.log_date_format
    if not conf.use_json:
        for handler in log_root.handlers:
            handler.setFormatter(formatters.ContextFormatter(project=project,
                                                             version=version,
                                                             datefmt=datefmt,
                                                             config=conf))
    else:
        for handler in log_root.handlers:
            handler.setFormatter(formatters.JSONFormatter(datefmt=datefmt))
    _refresh_root_level(conf.debug)

    for pair in conf.default_log_levels:
        mod, _sep, level_name = pair.partition('=')
        logger = logging.getLogger(mod)
        numeric_level = None
        try:
            # NOTE(harlowja): integer's are valid level names, and for some
            # libraries they have a lower level than DEBUG that is typically
            # defined at level 5, so to make that accessible, try to convert
            # this to a integer, and if not keep the original...
            numeric_level = int(level_name)
        except ValueError:  # nosec
            pass
        if numeric_level is not None:
            logger.setLevel(numeric_level)
        else:
            logger.setLevel(level_name)

    if conf.rate_limit_burst >= 1 and conf.rate_limit_interval >= 1:
        from oslo_log import rate_limit
        rate_limit.install_filter(conf.rate_limit_burst,
                                  conf.rate_limit_interval,
                                  conf.rate_limit_except)


_loggers = {}


def get_loggers():
    """Return a copy of the oslo loggers dictionary."""
    return _loggers.copy()


def getLogger(name=None, project='unknown', version='unknown'):
    """Build a logger with the given name.

    :param name: The name for the logger. This is usually the module
                 name, ``__name__``.
    :type name: string
    :param project: The name of the project, to be injected into log
                    messages. For example, ``'nova'``.
    :type project: string
    :param version: The version of the project, to be injected into log
                    messages. For example, ``'2014.2'``.
    :type version: string
    """
    # NOTE(dhellmann): To maintain backwards compatibility with the
    # old oslo namespace package logger configurations, and to make it
    # possible to control all oslo logging with one logger node, we
    # replace "oslo_" with "oslo." so that modules under the new
    # non-namespaced packages get loggers as though they are.
    if name and name.startswith('oslo_'):
        name = 'oslo.' + name[5:]
    if name not in _loggers:
        _loggers[name] = KeywordArgumentAdapter(logging.getLogger(name),
                                                {'project': project,
                                                 'version': version})
    return _loggers[name]


def get_default_log_levels():
    """Return the Oslo Logging default log levels.

    Returns a copy of the list so an application can change the value
    and not affect the default value used in the log_opts configuration
    setup.
    """
    return list(_options.DEFAULT_LOG_LEVELS)


def is_debug_enabled(conf):
    """Determine if debug logging mode is enabled."""
    return conf.debug
