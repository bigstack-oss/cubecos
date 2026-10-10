# -*- encoding: utf-8 -*-
#
# Copyright 2013 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

"""SQLAlchemy storage backend."""

import collections
import datetime
import operator
import threading

from oslo_config import cfg
from oslo_db import api as oslo_db_api
from oslo_db import exception as db_exc
from oslo_db.sqlalchemy import enginefacade
from oslo_db.sqlalchemy import utils as db_utils
from oslo_utils import timeutils
from sqlalchemy.inspection import inspect
from sqlalchemy.orm import exc
from sqlalchemy.orm import joinedload

from watcher._i18n import _
from watcher.common import exception
from watcher.common import utils
from watcher.db import api
from watcher.db.sqlalchemy import models
from watcher import objects

CONF = cfg.CONF

_CONTEXT = threading.local()


def get_backend():
    """The backend is this module itself."""
    return Connection()


def _session_for_read():
    return enginefacade.reader.using(_CONTEXT)


# NOTE(tylerchristie) Please add @oslo_db_api.retry_on_deadlock decorator to
# any new methods using _session_for_write (as deadlocks happen on write), so
# that oslo_db is able to retry in case of deadlocks.
def _session_for_write():
    return enginefacade.writer.using(_CONTEXT)


def add_identity_filter(query, value):
    """Adds an identity filter to a query.

    Filters results by ID, if supplied value is a valid integer.
    Otherwise attempts to filter results by UUID.

    :param query: Initial query to add filter to.
    :param value: Value for filtering results by.
    :return: Modified query.
    """
    if utils.is_int_like(value):
        return query.filter_by(id=value)
    elif utils.is_uuid_like(value):
        return query.filter_by(uuid=value)
    else:
        raise exception.InvalidIdentity(identity=value)


def _paginate_query(model, limit=None, marker=None, sort_key=None,
                    sort_dir=None, query=None):
    sort_keys = ['id']
    if sort_key and sort_key not in sort_keys:
        sort_keys.insert(0, sort_key)
    query = db_utils.paginate_query(query, model, limit, sort_keys,
                                    marker=marker, sort_dir=sort_dir)
    return query.all()


class JoinMap(utils.Struct):
    """Mapping for the Join-based queries"""


NaturalJoinFilter = collections.namedtuple(
    'NaturalJoinFilter', ['join_fieldname', 'join_model'])


class Connection(api.BaseConnection):
    """SqlAlchemy connection."""

    valid_operators = {
        "": operator.eq,
        "eq": operator.eq,
        "neq": operator.ne,
        "gt": operator.gt,
        "gte": operator.ge,
        "lt": operator.lt,
        "lte": operator.le,
        "in": lambda field, choices: field.in_(choices),
        "notin": lambda field, choices: field.notin_(choices),
    }

    def __init__(self):
        super(Connection, self).__init__()

    def __add_simple_filter(self, query, model, fieldname, value, operator_):
        field = getattr(model, fieldname)

        if (fieldname != 'deleted' and value and
                field.type.python_type is datetime.datetime):
            if not isinstance(value, datetime.datetime):
                value = timeutils.parse_isotime(value)

        return query.filter(self.valid_operators[operator_](field, value))

    def __add_join_filter(self, query, model, fieldname, value, operator_):
        query = query.join(model)
        return self.__add_simple_filter(query, model, fieldname,
                                        value, operator_)

    def __decompose_filter(self, raw_fieldname):
        """Decompose a filter name into its 2 subparts

        A filter can take 2 forms:

        - "<FIELDNAME>" which is a syntactic sugar for "<FIELDNAME>__eq"
        - "<FIELDNAME>__<OPERATOR>" where <OPERATOR> is the comparison operator
          to be used.

        Available operators are:

        - eq
        - neq
        - gt
        - gte
        - lt
        - lte
        - in
        - notin
        """
        separator = '__'
        fieldname, separator, operator_ = raw_fieldname.partition(separator)

        if operator_ and operator_ not in self.valid_operators:
            raise exception.InvalidOperator(
                operator=operator_, valid_operators=self.valid_operators)

        return fieldname, operator_

    def _add_filters(self, query, model, filters=None,
                     plain_fields=None, join_fieldmap=None):
        """Generic way to add filters to a Watcher model

        Each filter key provided by the `filters` parameter will be decomposed
        into 2 pieces: the field name and the comparison operator

        - "": By default, the "eq" is applied if no operator is provided
        - "eq", which stands for "equal" : e.g. {"state__eq": "PENDING"}
          will result in the "WHERE state = 'PENDING'" clause.
        - "neq", which stands for "not equal" : e.g. {"state__neq": "PENDING"}
          will result in the "WHERE state != 'PENDING'" clause.
        - "gt", which stands for "greater than" : e.g.
          {"created_at__gt": "2016-06-06T10:33:22.063176"} will result in the
          "WHERE created_at > '2016-06-06T10:33:22.063176'" clause.
        - "gte", which stands for "greater than or equal to" : e.g.
          {"created_at__gte": "2016-06-06T10:33:22.063176"} will result in the
          "WHERE created_at >= '2016-06-06T10:33:22.063176'" clause.
        - "lt", which stands for "less than" : e.g.
          {"created_at__lt": "2016-06-06T10:33:22.063176"} will result in the
          "WHERE created_at < '2016-06-06T10:33:22.063176'" clause.
        - "lte", which stands for "less than or equal to" : e.g.
          {"created_at__lte": "2016-06-06T10:33:22.063176"} will result in the
          "WHERE created_at <= '2016-06-06T10:33:22.063176'" clause.
        - "in": e.g. {"state__in": ('SUCCEEDED', 'FAILED')} will result in the
          "WHERE state IN ('SUCCEEDED', 'FAILED')" clause.

        :param query: a :py:class:`sqlalchemy.orm.query.Query` instance
        :param model: the model class the filters should relate to
        :param filters: dict with the following structure {"fieldname": value}
        :param plain_fields: a :py:class:`sqlalchemy.orm.query.Query` instance
        :param join_fieldmap: a :py:class:`sqlalchemy.orm.query.Query` instance
        """
        soft_delete_mixin_fields = ['deleted', 'deleted_at']
        timestamp_mixin_fields = ['created_at', 'updated_at']
        filters = filters or {}

        # Special case for 'deleted' because it is a non-boolean flag
        if 'deleted' in filters:
            deleted_filter = filters.pop('deleted')
            op = 'eq' if not bool(deleted_filter) else 'neq'
            filters['deleted__%s' % op] = 0

        plain_fields = tuple(
            (list(plain_fields) or []) +
            soft_delete_mixin_fields +
            timestamp_mixin_fields)
        join_fieldmap = join_fieldmap or {}

        for raw_fieldname, value in filters.items():
            fieldname, operator_ = self.__decompose_filter(raw_fieldname)
            if fieldname in plain_fields:
                query = self.__add_simple_filter(
                    query, model, fieldname, value, operator_)
            elif fieldname in join_fieldmap:
                join_field, join_model = join_fieldmap[fieldname]
                query = self.__add_join_filter(
                    query, join_model, join_field, value, operator_)

        return query

    @staticmethod
    def _get_relationships(model):
        return inspect(model).relationships

    @staticmethod
    def _set_eager_options(model, query):
        relationships = inspect(model).relationships
        for relationship in relationships:
            if not relationship.uselist:
                # We have a One-to-X relationship
                query = query.options(joinedload(
                    getattr(model, relationship.key)))
        return query

    @oslo_db_api.retry_on_deadlock
    def _create(self, model, values):
        with _session_for_write() as session:
            obj = model()
            cleaned_values = {k: v for k, v in values.items()
                              if k not in self._get_relationships(model)}
            obj.update(cleaned_values)
            session.add(obj)
            session.flush()
            return obj

    def _get(self, context, model, fieldname, value, eager):
        with _session_for_read() as session:
            query = session.query(model)
            if eager:
                query = self._set_eager_options(model, query)

            query = query.filter(getattr(model, fieldname) == value)
            if not context.show_deleted:
                query = query.filter(model.deleted_at.is_(None))

            try:
                obj = query.one()
            except exc.NoResultFound:
                raise exception.ResourceNotFound(name=model.__name__, id=value)

            return obj

    @staticmethod
    @oslo_db_api.retry_on_deadlock
    def _update(model, id_, values):
        with _session_for_write() as session:
            query = session.query(model)
            query = add_identity_filter(query, id_)
            try:
                ref = query.with_for_update().one()
            except exc.NoResultFound:
                raise exception.ResourceNotFound(name=model.__name__, id=id_)

            ref.update(values)

            return ref

    @staticmethod
    @oslo_db_api.retry_on_deadlock
    def _soft_delete(model, id_):
        with _session_for_write() as session:
            query = session.query(model)
            query = add_identity_filter(query, id_)
            try:
                row = query.one()
            except exc.NoResultFound:
                raise exception.ResourceNotFound(name=model.__name__, id=id_)

            row.soft_delete(session)

            return row

    @staticmethod
    @oslo_db_api.retry_on_deadlock
    def _destroy(model, id_):
        with _session_for_write() as session:
            query = session.query(model)
            query = add_identity_filter(query, id_)

            try:
                query.one()
            except exc.NoResultFound:
                raise exception.ResourceNotFound(name=model.__name__, id=id_)

            query.delete()

    def _get_model_list(self, model, add_filters_func, context, filters=None,
                        limit=None, marker=None, sort_key=None, sort_dir=None,
                        eager=False):
        with _session_for_read() as session:
            query = session.query(model)
            if eager:
                query = self._set_eager_options(model, query)
            query = add_filters_func(query, filters)
            if not context.show_deleted:
                query = query.filter(model.deleted_at.is_(None))
            return _paginate_query(model, limit, marker,
                                   sort_key, sort_dir, query)

    # NOTE(erakli): _add_..._filters methods should be refactored to have same
    # content. join_fieldmap should be filled with JoinMap instead of dict

    def _add_goals_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'name', 'display_name']

        return self._add_filters(
            query=query, model=models.Goal, filters=filters,
            plain_fields=plain_fields)

    def _add_strategies_filters(self, query, filters):
        plain_fields = ['uuid', 'name', 'display_name', 'goal_id']
        join_fieldmap = JoinMap(
            goal_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.Goal),
            goal_name=NaturalJoinFilter(
                join_fieldname="name", join_model=models.Goal))
        return self._add_filters(
            query=query, model=models.Strategy, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

    def _add_audit_templates_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'name', 'goal_id', 'strategy_id']
        join_fieldmap = JoinMap(
            goal_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.Goal),
            goal_name=NaturalJoinFilter(
                join_fieldname="name", join_model=models.Goal),
            strategy_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.Strategy),
            strategy_name=NaturalJoinFilter(
                join_fieldname="name", join_model=models.Strategy),
        )

        return self._add_filters(
            query=query, model=models.AuditTemplate, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

    def _add_audits_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'audit_type', 'state', 'goal_id',
                        'strategy_id', 'hostname']
        join_fieldmap = {
            'goal_uuid': ("uuid", models.Goal),
            'goal_name': ("name", models.Goal),
            'strategy_uuid': ("uuid", models.Strategy),
            'strategy_name': ("name", models.Strategy),
        }

        return self._add_filters(
            query=query, model=models.Audit, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

    def _add_action_plans_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'state', 'audit_id', 'strategy_id']
        join_fieldmap = JoinMap(
            audit_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.Audit),
            strategy_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.Strategy),
            strategy_name=NaturalJoinFilter(
                join_fieldname="name", join_model=models.Strategy),
        )

        return self._add_filters(
            query=query, model=models.ActionPlan, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

    def _add_actions_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'state', 'action_plan_id']
        join_fieldmap = {
            'action_plan_uuid': ("uuid", models.ActionPlan),
        }

        query = self._add_filters(
            query=query, model=models.Action, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

        if 'audit_uuid' in filters:
            with _session_for_read() as session:
                stmt = session.query(models.ActionPlan).join(
                    models.Audit,
                    models.Audit.id == models.ActionPlan.audit_id)\
                    .filter_by(uuid=filters['audit_uuid']).subquery()
                query = query.filter_by(action_plan_id=stmt.c.id)

        return query

    def _add_efficacy_indicators_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['uuid', 'name', 'unit', 'schema', 'action_plan_id']
        join_fieldmap = JoinMap(
            action_plan_uuid=NaturalJoinFilter(
                join_fieldname="uuid", join_model=models.ActionPlan),
        )

        return self._add_filters(
            query=query, model=models.EfficacyIndicator, filters=filters,
            plain_fields=plain_fields, join_fieldmap=join_fieldmap)

    def _add_scoring_engine_filters(self, query, filters):
        if filters is None:
            filters = {}

        plain_fields = ['id', 'description']

        return self._add_filters(
            query=query, model=models.ScoringEngine, filters=filters,
            plain_fields=plain_fields)

    def _add_action_descriptions_filters(self, query, filters):
        if not filters:
            filters = {}

        plain_fields = ['id', 'action_type']

        return self._add_filters(
            query=query, model=models.ActionDescription, filters=filters,
            plain_fields=plain_fields)

    def _add_services_filters(self, query, filters):
        if not filters:
            filters = {}

        plain_fields = ['id', 'name', 'host']

        return self._add_filters(
            query=query, model=models.Service, filters=filters,
            plain_fields=plain_fields)

    # ### GOALS ### #

    def get_goal_list(self, *args, **kwargs):
        return self._get_model_list(models.Goal,
                                    self._add_goals_filters,
                                    *args, **kwargs)

    def create_goal(self, values):
        # ensure defaults are present for new goals
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        try:
            goal = self._create(models.Goal, values)
        except db_exc.DBDuplicateEntry:
            raise exception.GoalAlreadyExists(uuid=values['uuid'])
        return goal

    def _get_goal(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.Goal,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.GoalNotFound(goal=value)

    def get_goal_by_id(self, context, goal_id, eager=False):
        return self._get_goal(
            context, fieldname="id", value=goal_id, eager=eager)

    def get_goal_by_uuid(self, context, goal_uuid, eager=False):
        return self._get_goal(
            context, fieldname="uuid", value=goal_uuid, eager=eager)

    def get_goal_by_name(self, context, goal_name, eager=False):
        return self._get_goal(
            context, fieldname="name", value=goal_name, eager=eager)

    def destroy_goal(self, goal_id):
        try:
            return self._destroy(models.Goal, goal_id)
        except exception.ResourceNotFound:
            raise exception.GoalNotFound(goal=goal_id)

    def update_goal(self, goal_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing Goal."))

        try:
            return self._update(models.Goal, goal_id, values)
        except exception.ResourceNotFound:
            raise exception.GoalNotFound(goal=goal_id)

    def soft_delete_goal(self, goal_id):
        try:
            return self._soft_delete(models.Goal, goal_id)
        except exception.ResourceNotFound:
            raise exception.GoalNotFound(goal=goal_id)

    # ### STRATEGIES ### #

    def get_strategy_list(self, *args, **kwargs):
        return self._get_model_list(models.Strategy,
                                    self._add_strategies_filters,
                                    *args, **kwargs)

    def create_strategy(self, values):
        # ensure defaults are present for new strategies
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        try:
            strategy = self._create(models.Strategy, values)
        except db_exc.DBDuplicateEntry:
            raise exception.StrategyAlreadyExists(uuid=values['uuid'])
        return strategy

    def _get_strategy(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.Strategy,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.StrategyNotFound(strategy=value)

    def get_strategy_by_id(self, context, strategy_id, eager=False):
        return self._get_strategy(
            context, fieldname="id", value=strategy_id, eager=eager)

    def get_strategy_by_uuid(self, context, strategy_uuid, eager=False):
        return self._get_strategy(
            context, fieldname="uuid", value=strategy_uuid, eager=eager)

    def get_strategy_by_name(self, context, strategy_name, eager=False):
        return self._get_strategy(
            context, fieldname="name", value=strategy_name, eager=eager)

    def destroy_strategy(self, strategy_id):
        try:
            return self._destroy(models.Strategy, strategy_id)
        except exception.ResourceNotFound:
            raise exception.StrategyNotFound(strategy=strategy_id)

    def update_strategy(self, strategy_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing Strategy."))

        try:
            return self._update(models.Strategy, strategy_id, values)
        except exception.ResourceNotFound:
            raise exception.StrategyNotFound(strategy=strategy_id)

    def soft_delete_strategy(self, strategy_id):
        try:
            return self._soft_delete(models.Strategy, strategy_id)
        except exception.ResourceNotFound:
            raise exception.StrategyNotFound(strategy=strategy_id)

    # ### AUDIT TEMPLATES ### #

    def get_audit_template_list(self, *args, **kwargs):
        return self._get_model_list(models.AuditTemplate,
                                    self._add_audit_templates_filters,
                                    *args, **kwargs)

    def create_audit_template(self, values):
        # ensure defaults are present for new audit_templates
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        with _session_for_write() as session:
            query = session.query(models.AuditTemplate)
            query = query.filter_by(name=values.get('name'),
                                    deleted_at=None)

            if len(query.all()) > 0:
                raise exception.AuditTemplateAlreadyExists(
                    audit_template=values['name'])

            try:
                audit_template = self._create(models.AuditTemplate, values)
            except db_exc.DBDuplicateEntry:
                raise exception.AuditTemplateAlreadyExists(
                    audit_template=values['name'])
            return audit_template

    def _get_audit_template(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.AuditTemplate,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.AuditTemplateNotFound(audit_template=value)

    def get_audit_template_by_id(self, context, audit_template_id,
                                 eager=False):
        return self._get_audit_template(
            context, fieldname="id", value=audit_template_id, eager=eager)

    def get_audit_template_by_uuid(self, context, audit_template_uuid,
                                   eager=False):
        return self._get_audit_template(
            context, fieldname="uuid", value=audit_template_uuid, eager=eager)

    def get_audit_template_by_name(self, context, audit_template_name,
                                   eager=False):
        return self._get_audit_template(
            context, fieldname="name", value=audit_template_name, eager=eager)

    def destroy_audit_template(self, audit_template_id):
        try:
            return self._destroy(models.AuditTemplate, audit_template_id)
        except exception.ResourceNotFound:
            raise exception.AuditTemplateNotFound(
                audit_template=audit_template_id)

    def update_audit_template(self, audit_template_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing "
                          "Audit Template."))
        try:
            return self._update(
                models.AuditTemplate, audit_template_id, values)
        except exception.ResourceNotFound:
            raise exception.AuditTemplateNotFound(
                audit_template=audit_template_id)

    def soft_delete_audit_template(self, audit_template_id):
        try:
            return self._soft_delete(models.AuditTemplate, audit_template_id)
        except exception.ResourceNotFound:
            raise exception.AuditTemplateNotFound(
                audit_template=audit_template_id)

    # ### AUDITS ### #

    def get_audit_list(self, *args, **kwargs):
        return self._get_model_list(models.Audit,
                                    self._add_audits_filters,
                                    *args, **kwargs)

    def create_audit(self, values):
        # ensure defaults are present for new audits
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        with _session_for_write() as session:
            query = session.query(models.Audit)
            query = query.filter_by(name=values.get('name'),
                                    deleted_at=None)

            if len(query.all()) > 0:
                raise exception.AuditAlreadyExists(
                    audit=values['name'])

            if values.get('state') is None:
                values['state'] = objects.audit.State.PENDING

            if not values.get('auto_trigger'):
                values['auto_trigger'] = False

            try:
                audit = self._create(models.Audit, values)
            except db_exc.DBDuplicateEntry:
                raise exception.AuditAlreadyExists(audit=values['uuid'])
            return audit

    def _get_audit(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.Audit,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.AuditNotFound(audit=value)

    def get_audit_by_id(self, context, audit_id, eager=False):
        return self._get_audit(
            context, fieldname="id", value=audit_id, eager=eager)

    def get_audit_by_uuid(self, context, audit_uuid, eager=False):
        return self._get_audit(
            context, fieldname="uuid", value=audit_uuid, eager=eager)

    def get_audit_by_name(self, context, audit_name, eager=False):
        return self._get_audit(
            context, fieldname="name", value=audit_name, eager=eager)

    def destroy_audit(self, audit_id):
        def is_audit_referenced(session, audit_id):
            """Checks whether the audit is referenced by action_plan(s)."""
            query = session.query(models.ActionPlan)
            query = self._add_action_plans_filters(
                query, {'audit_id': audit_id})
            return query.count() != 0

        with _session_for_write() as session:
            query = session.query(models.Audit)
            query = add_identity_filter(query, audit_id)

            try:
                audit_ref = query.one()
            except exc.NoResultFound:
                raise exception.AuditNotFound(audit=audit_id)

            if is_audit_referenced(session, audit_ref['id']):
                raise exception.AuditReferenced(audit=audit_id)

            query.delete()

    def update_audit(self, audit_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing "
                          "Audit."))

        try:
            return self._update(models.Audit, audit_id, values)
        except exception.ResourceNotFound:
            raise exception.AuditNotFound(audit=audit_id)

    def soft_delete_audit(self, audit_id):
        try:
            return self._soft_delete(models.Audit, audit_id)
        except exception.ResourceNotFound:
            raise exception.AuditNotFound(audit=audit_id)

    # ### ACTIONS ### #

    def get_action_list(self, *args, **kwargs):
        return self._get_model_list(models.Action,
                                    self._add_actions_filters,
                                    *args, **kwargs)

    def create_action(self, values):
        # ensure defaults are present for new actions
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        if values.get('state') is None:
            values['state'] = objects.action.State.PENDING

        try:
            action = self._create(models.Action, values)
        except db_exc.DBDuplicateEntry:
            raise exception.ActionAlreadyExists(uuid=values['uuid'])
        return action

    def _get_action(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.Action,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.ActionNotFound(action=value)

    def get_action_by_id(self, context, action_id, eager=False):
        return self._get_action(
            context, fieldname="id", value=action_id, eager=eager)

    def get_action_by_uuid(self, context, action_uuid, eager=False):
        return self._get_action(
            context, fieldname="uuid", value=action_uuid, eager=eager)

    def destroy_action(self, action_id):
        with _session_for_write() as session:
            query = session.query(models.Action)
            query = add_identity_filter(query, action_id)
            count = query.delete()
            if count != 1:
                raise exception.ActionNotFound(action_id)

    def update_action(self, action_id, values):
        # NOTE(dtantsur): this can lead to very strange errors
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing Action."))

        return self._do_update_action(action_id, values)

    @staticmethod
    def _do_update_action(action_id, values):
        with _session_for_write() as session:
            query = session.query(models.Action)
            query = add_identity_filter(query, action_id)
            try:
                ref = query.with_for_update().one()
            except exc.NoResultFound:
                raise exception.ActionNotFound(action=action_id)

            ref.update(values)
            return ref

    def soft_delete_action(self, action_id):
        try:
            return self._soft_delete(models.Action, action_id)
        except exception.ResourceNotFound:
            raise exception.ActionNotFound(action=action_id)

    # ### ACTION PLANS ### #

    def get_action_plan_list(self, *args, **kwargs):
        return self._get_model_list(models.ActionPlan,
                                    self._add_action_plans_filters,
                                    *args, **kwargs)

    def create_action_plan(self, values):
        # ensure defaults are present for new audits
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        try:
            action_plan = self._create(models.ActionPlan, values)
        except db_exc.DBDuplicateEntry:
            raise exception.ActionPlanAlreadyExists(uuid=values['uuid'])
        return action_plan

    def _get_action_plan(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.ActionPlan,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.ActionPlanNotFound(action_plan=value)

    def get_action_plan_by_id(self, context, action_plan_id, eager=False):
        return self._get_action_plan(
            context, fieldname="id", value=action_plan_id, eager=eager)

    def get_action_plan_by_uuid(self, context, action_plan_uuid, eager=False):
        return self._get_action_plan(
            context, fieldname="uuid", value=action_plan_uuid, eager=eager)

    def destroy_action_plan(self, action_plan_id):
        def is_action_plan_referenced(session, action_plan_id):
            """Checks whether the action_plan is referenced by action(s)."""
            query = session.query(models.Action)
            query = self._add_actions_filters(
                query, {'action_plan_id': action_plan_id})
            return query.count() != 0

        with _session_for_write() as session:
            query = session.query(models.ActionPlan)
            query = add_identity_filter(query, action_plan_id)

            try:
                action_plan_ref = query.one()
            except exc.NoResultFound:
                raise exception.ActionPlanNotFound(action_plan=action_plan_id)

            if is_action_plan_referenced(session, action_plan_ref['id']):
                raise exception.ActionPlanReferenced(
                    action_plan=action_plan_id)

            query.delete()

    def update_action_plan(self, action_plan_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing "
                          "Action Plan."))

        return self._do_update_action_plan(action_plan_id, values)

    @staticmethod
    def _do_update_action_plan(action_plan_id, values):
        with _session_for_write() as session:
            query = session.query(models.ActionPlan)
            query = add_identity_filter(query, action_plan_id)
            try:
                ref = query.with_for_update().one()
            except exc.NoResultFound:
                raise exception.ActionPlanNotFound(action_plan=action_plan_id)

            ref.update(values)
            return ref

    def soft_delete_action_plan(self, action_plan_id):
        try:
            return self._soft_delete(models.ActionPlan, action_plan_id)
        except exception.ResourceNotFound:
            raise exception.ActionPlanNotFound(action_plan=action_plan_id)

    # ### EFFICACY INDICATORS ### #

    def get_efficacy_indicator_list(self, *args, **kwargs):
        return self._get_model_list(models.EfficacyIndicator,
                                    self._add_efficacy_indicators_filters,
                                    *args, **kwargs)

    def create_efficacy_indicator(self, values):
        # ensure defaults are present for new efficacy indicators
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        try:
            efficacy_indicator = self._create(models.EfficacyIndicator, values)
        except db_exc.DBDuplicateEntry:
            raise exception.EfficacyIndicatorAlreadyExists(uuid=values['uuid'])
        return efficacy_indicator

    def _get_efficacy_indicator(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.EfficacyIndicator,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.EfficacyIndicatorNotFound(efficacy_indicator=value)

    def get_efficacy_indicator_by_id(self, context, efficacy_indicator_id,
                                     eager=False):
        return self._get_efficacy_indicator(
            context, fieldname="id",
            value=efficacy_indicator_id, eager=eager)

    def get_efficacy_indicator_by_uuid(self, context, efficacy_indicator_uuid,
                                       eager=False):
        return self._get_efficacy_indicator(
            context, fieldname="uuid",
            value=efficacy_indicator_uuid, eager=eager)

    def get_efficacy_indicator_by_name(self, context, efficacy_indicator_name,
                                       eager=False):
        return self._get_efficacy_indicator(
            context, fieldname="name",
            value=efficacy_indicator_name, eager=eager)

    def update_efficacy_indicator(self, efficacy_indicator_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing "
                          "efficacy indicator."))

        try:
            return self._update(
                models.EfficacyIndicator, efficacy_indicator_id, values)
        except exception.ResourceNotFound:
            raise exception.EfficacyIndicatorNotFound(
                efficacy_indicator=efficacy_indicator_id)

    def soft_delete_efficacy_indicator(self, efficacy_indicator_id):
        try:
            return self._soft_delete(
                models.EfficacyIndicator, efficacy_indicator_id)
        except exception.ResourceNotFound:
            raise exception.EfficacyIndicatorNotFound(
                efficacy_indicator=efficacy_indicator_id)

    def destroy_efficacy_indicator(self, efficacy_indicator_id):
        try:
            return self._destroy(
                models.EfficacyIndicator, efficacy_indicator_id)
        except exception.ResourceNotFound:
            raise exception.EfficacyIndicatorNotFound(
                efficacy_indicator=efficacy_indicator_id)

    # ### SCORING ENGINES ### #

    def get_scoring_engine_list(self, *args, **kwargs):
        return self._get_model_list(models.ScoringEngine,
                                    self._add_scoring_engine_filters,
                                    *args, **kwargs)

    def create_scoring_engine(self, values):
        # ensure defaults are present for new scoring engines
        if not values.get('uuid'):
            values['uuid'] = utils.generate_uuid()

        try:
            scoring_engine = self._create(models.ScoringEngine, values)
        except db_exc.DBDuplicateEntry:
            raise exception.ScoringEngineAlreadyExists(uuid=values['uuid'])
        return scoring_engine

    def _get_scoring_engine(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.ScoringEngine,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.ScoringEngineNotFound(scoring_engine=value)

    def get_scoring_engine_by_id(self, context, scoring_engine_id,
                                 eager=False):
        return self._get_scoring_engine(
            context, fieldname="id", value=scoring_engine_id, eager=eager)

    def get_scoring_engine_by_uuid(self, context, scoring_engine_uuid,
                                   eager=False):
        return self._get_scoring_engine(
            context, fieldname="uuid", value=scoring_engine_uuid, eager=eager)

    def get_scoring_engine_by_name(self, context, scoring_engine_name,
                                   eager=False):
        return self._get_scoring_engine(
            context, fieldname="name", value=scoring_engine_name, eager=eager)

    def destroy_scoring_engine(self, scoring_engine_id):
        try:
            return self._destroy(models.ScoringEngine, scoring_engine_id)
        except exception.ResourceNotFound:
            raise exception.ScoringEngineNotFound(
                scoring_engine=scoring_engine_id)

    def update_scoring_engine(self, scoring_engine_id, values):
        if 'uuid' in values:
            raise exception.Invalid(
                message=_("Cannot overwrite UUID for an existing "
                          "Scoring Engine."))

        try:
            return self._update(
                models.ScoringEngine, scoring_engine_id, values)
        except exception.ResourceNotFound:
            raise exception.ScoringEngineNotFound(
                scoring_engine=scoring_engine_id)

    def soft_delete_scoring_engine(self, scoring_engine_id):
        try:
            return self._soft_delete(
                models.ScoringEngine, scoring_engine_id)
        except exception.ResourceNotFound:
            raise exception.ScoringEngineNotFound(
                scoring_engine=scoring_engine_id)

    # ### SERVICES ### #

    def get_service_list(self, *args, **kwargs):
        return self._get_model_list(models.Service,
                                    self._add_services_filters,
                                    *args, **kwargs)

    def create_service(self, values):
        try:
            service = self._create(models.Service, values)
        except db_exc.DBDuplicateEntry:
            raise exception.ServiceAlreadyExists(name=values['name'],
                                                 host=values['host'])
        return service

    def _get_service(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.Service,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.ServiceNotFound(service=value)

    def get_service_by_id(self, context, service_id, eager=False):
        return self._get_service(
            context, fieldname="id", value=service_id, eager=eager)

    def get_service_by_name(self, context, service_name, eager=False):
        return self._get_service(
            context, fieldname="name", value=service_name, eager=eager)

    def destroy_service(self, service_id):
        try:
            return self._destroy(models.Service, service_id)
        except exception.ResourceNotFound:
            raise exception.ServiceNotFound(service=service_id)

    def update_service(self, service_id, values):
        try:
            return self._update(models.Service, service_id, values)
        except exception.ResourceNotFound:
            raise exception.ServiceNotFound(service=service_id)

    def soft_delete_service(self, service_id):
        try:
            return self._soft_delete(models.Service, service_id)
        except exception.ResourceNotFound:
            raise exception.ServiceNotFound(service=service_id)

    # ### ACTION_DESCRIPTIONS ### #

    def get_action_description_list(self, *args, **kwargs):
        return self._get_model_list(models.ActionDescription,
                                    self._add_action_descriptions_filters,
                                    *args, **kwargs)

    def create_action_description(self, values):
        try:
            action_description = self._create(models.ActionDescription, values)
        except db_exc.DBDuplicateEntry:
            raise exception.ActionDescriptionAlreadyExists(
                action_type=values['action_type'])
        return action_description

    def _get_action_description(self, context, fieldname, value, eager):
        try:
            return self._get(context, model=models.ActionDescription,
                             fieldname=fieldname, value=value, eager=eager)
        except exception.ResourceNotFound:
            raise exception.ActionDescriptionNotFound(action_id=value)

    def get_action_description_by_id(self, context,
                                     action_id, eager=False):
        return self._get_action_description(
            context, fieldname="id", value=action_id, eager=eager)

    def get_action_description_by_type(self, context,
                                       action_type, eager=False):
        return self._get_action_description(
            context, fieldname="action_type", value=action_type, eager=eager)

    def destroy_action_description(self, action_id):
        try:
            return self._destroy(models.ActionDescription, action_id)
        except exception.ResourceNotFound:
            raise exception.ActionDescriptionNotFound(
                action_id=action_id)

    def update_action_description(self, action_id, values):
        try:
            return self._update(models.ActionDescription,
                                action_id, values)
        except exception.ResourceNotFound:
            raise exception.ActionDescriptionNotFound(
                action_id=action_id)

    def soft_delete_action_description(self, action_id):
        try:
            return self._soft_delete(models.ActionDescription, action_id)
        except exception.ResourceNotFound:
            raise exception.ActionDescriptionNotFound(
                action_id=action_id)
