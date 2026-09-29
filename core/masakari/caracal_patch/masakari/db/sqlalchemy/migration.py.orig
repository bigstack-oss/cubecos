# Copyright 2016 NTT Data.
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

import os

from alembic import command as alembic_api
from alembic import config as alembic_config
from alembic import migration as alembic_migration
from oslo_config import cfg
from oslo_db import options
from oslo_log import log as logging
import sqlalchemy as sa

import masakari.conf
from masakari.db import api as db_api
from masakari.engine import driver
from masakari import exception
from masakari.i18n import _

options.set_defaults(cfg.CONF)

LOG = logging.getLogger(__name__)
CONF = masakari.conf.CONF


def _migrate_legacy_database(engine, connection, config):
    """Check if database is a legacy sqlalchemy-migrate-managed database.

    If it is, migrate it by "stamping" the initial alembic schema.
    """
    # If the database doesn't have the sqlalchemy-migrate legacy migration
    # table, we don't have anything to do
    if not sa.inspect(engine).has_table('migrate_version'):
        return

    # Likewise, if we've already migrated to alembic, we don't have anything to
    # do
    context = alembic_migration.MigrationContext.configure(connection)
    if context.get_current_revision():
        return

    # We have legacy migrations but no alembic migration. Stamp (dummy apply)
    # the initial alembic migration(s). There may be one or two to apply
    # depending on what's already applied.

    # Get the currently applied version of the legacy migrations using table
    # reflection to avoid a dependency on sqlalchemy-migrate
    # https://opendev.org/x/sqlalchemy-migrate/src/commit/5d1f322542cd8eb42381612765be4ed9ca8105ec/migrate/versioning/schema.py#L175-L179
    meta = sa.MetaData()
    table = sa.Table('migrate_version', meta, autoload_with=engine)
    with engine.connect() as conn:
        version = conn.execute(sa.select(table.c.version)).scalar()

    # If the user is requesting a skip-level upgrade from a very old version,
    # we can't help them since we don't have alembic-versions of those old
    # migrations :(
    if version < 7:
        reason = _(
            'Your database is at version %03d; we only support upgrading '
            'from version 007 or later. Please upgrade your database using '
            'an earlier release of Masakari and then return here.'
        )
        raise exception.InvalidInput(reason % version)
    elif version > 8:
        if os.getenv('FORCE_MASAKARI_DB_SYNC') is None:
            reason = _(
                'Your database is at version %03d; we do not recognise this '
                'version and it is likely you are carrying out-of-tree '
                'migrations. You can still upgrade but we cannot guarantee '
                'things will work as expected. '
                'If you wish to continue, set the FORCE_MASAKARI_DB_SYNC '
                'environment variable to any value and retry.'
            )
            raise exception.InvalidInput(reason % version)
        else:
            msg = _(
                'Your database is at version %03d; we do not recognise this '
                'version but the FORCE_MASAKARI_DB_SYNC environment variable '
                'is set so we are continuing. Things may break. '
                'You have been warned!',
            )
            LOG.warning(msg, version)

    if version == 7:
        alembic_init_version = '8f848eb45d03'
    else:  # 8 or greater (out-of-tree)
        alembic_init_version = '8bdf5929c5a6'

    LOG.info(
        'The database is still under sqlalchemy-migrate control; '
        'fake applying the initial alembic migration'
    )
    alembic_api.stamp(config, alembic_init_version)


def _find_alembic_conf():
    """Get the project's alembic configuration

    :returns: An instance of ``alembic.config.Config``
    """
    path = os.path.join(
        os.path.abspath(os.path.dirname(__file__)),
        'alembic.ini',
    )
    config = alembic_config.Config(os.path.abspath(path))
    # We don't want to use the logger configuration from the file, which is
    # only really intended for the CLI
    # https://stackoverflow.com/a/42691781/613428
    config.attributes['configure_logger'] = False
    return config


def _upgrade_alembic(engine, config, version):
    # re-use the connection rather than creating a new one
    with engine.begin() as connection:
        config.attributes['connection'] = connection
        _migrate_legacy_database(engine, connection, config)
        alembic_api.upgrade(config, version or 'head')


def db_sync(version=None, engine=None):
    """Migrate the database to `version` or the most recent version."""
    # If the user requested a specific version, check if it's an integer: if
    # so, we're almost certainly in sqlalchemy-migrate land and won't support
    # that
    if version is not None and version.isdigit():
        raise ValueError(
            'You requested an sqlalchemy-migrate database version; this is '
            'no longer supported'
        )

    if engine is None:
        engine = db_api.get_engine()

    config = _find_alembic_conf()

    # Discard the URL encoded in alembic.ini in favour of the URL configured
    # for the engine by the database fixtures, casting from
    # 'sqlalchemy.engine.url.URL' to str in the process. This returns a
    # RFC-1738 quoted URL, which means that a password like "foo@" will be
    # turned into "foo%40". This in turns causes a problem for
    # set_main_option() because that uses ConfigParser.set, which (by design)
    # uses *python* interpolation to write the string out ... where "%" is the
    # special python interpolation character! Avoid this mismatch by quoting
    # all %'s for the set below.
    engine_url = str(engine.url).replace('%', '%%')
    config.set_main_option('sqlalchemy.url', str(engine_url))

    # First upgrade ourselves, followed by Taskflow
    LOG.info('Applying migration(s)')
    _upgrade_alembic(engine, config, version)

    # Get the taskflow driver configured, default is 'taskflow_driver',
    # to load persistence tables to store progress details.
    taskflow_driver = driver.load_masakari_driver(CONF.notification_driver)

    if CONF.taskflow.connection:
        taskflow_driver.upgrade_backend(CONF.taskflow.connection)
    LOG.info('Migration(s) applied')


def db_version():
    """Get database version."""
    engine = db_api.get_engine()
    with engine.connect() as connection:
        m_context = alembic_migration.MigrationContext.configure(connection)
        return m_context.get_current_revision()
