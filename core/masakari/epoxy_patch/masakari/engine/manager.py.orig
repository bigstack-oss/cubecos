# Copyright 2016 NTT DATA
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

"""Handles all processes relating to notifications.

The :py:class:`MasakariManager` class is a
:py:class:`masakari.manager.Manager` that handles RPC calls relating to
notifications. It is responsible for processing notifications and executing
workflows.

"""
import traceback

from oslo_log import log as logging
import oslo_messaging as messaging
from oslo_service import periodic_task
from oslo_utils import timeutils

import masakari.conf
from masakari.engine import driver
from masakari.engine import instance_events as virt_events
from masakari.engine import rpcapi
from masakari.engine import utils as engine_utils
from masakari import exception
from masakari.i18n import _
from masakari import manager
from masakari import objects
from masakari.objects import fields
from masakari import utils

CONF = masakari.conf.CONF

LOG = logging.getLogger(__name__)


def update_host_method(context, host_name, reserved=False):
    reserved_host = objects.Host.get_by_name(context, host_name)
    reserved_host.reserved = reserved
    reserved_host.save()


class MasakariManager(manager.Manager):
    """Manages the running notifications"""
    RPC_API_VERSION = rpcapi.EngineAPI.RPC_API_VERSION
    target = messaging.Target(version=RPC_API_VERSION)

    def __init__(self, masakari_driver=None, *args, **kwargs):
        """Load configuration options"""
        LOG.debug("Initializing Masakari Manager.")
        super(MasakariManager, self).__init__(service_name="engine",
                                             *args, **kwargs)

        self.driver = driver.load_masakari_driver(masakari_driver)

    def _handle_notification_type_process(self, context, notification):
        notification_status = fields.NotificationStatus.FINISHED
        notification_event = notification.payload.get('event')
        process_name = notification.payload.get('process_name')
        exception_info = None

        if notification_event.upper() == 'STARTED':
            LOG.info("Notification type '%(type)s' received for host "
                     "'%(host_uuid)s': '%(process_name)s' has been "
                     "%(event)s.",
                     {'type': notification.type,
                      'host_uuid': notification.source_host_uuid,
                      'process_name': process_name,
                      'event': notification_event})
        elif notification_event.upper() == 'STOPPED':
            host_obj = objects.Host.get_by_uuid(
                context, notification.source_host_uuid)
            host_name = host_obj.name

            # Mark host on_maintenance mode as True
            update_data = {
                'on_maintenance': True,
            }
            host_obj.update(update_data)
            host_obj.save()

            try:
                self.driver.execute_process_failure(
                    context, process_name, host_name,
                    notification.notification_uuid)
            except exception.SkipProcessRecoveryException:
                notification_status = fields.NotificationStatus.FINISHED
            except (exception.MasakariException,
                    exception.ProcessRecoveryFailureException) as e:
                notification_status = fields.NotificationStatus.ERROR
                LOG.error("Failed to process notification '%(uuid)s'."
                          " Reason: %(error)s",
                          {"uuid": notification.notification_uuid,
                           "error": e.message})
                exception_info = e
        else:
            LOG.warning("Invalid event: %(event)s received for "
                        "notification type: %(notification_type)s",
                        {'event': notification_event,
                         'notification_type': notification.type})
            notification_status = fields.NotificationStatus.IGNORED

        if exception_info:
            tb = traceback.format_exc()
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.ERROR,
                exception=str(exception_info),
                tb=tb)
        else:
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.END)

        return notification_status

    def _handle_notification_type_instance(self, context, notification):
        if not virt_events.is_valid_event(notification.payload):
            LOG.info("Notification '%(uuid)s' received with payload "
                     "%(payload)s is ignored.",
                     {"uuid": notification.notification_uuid,
                      "payload": notification.payload})
            return fields.NotificationStatus.IGNORED

        notification_status = fields.NotificationStatus.FINISHED
        exception_info = None
        try:
            self.driver.execute_instance_failure(
                context, notification.payload.get('instance_uuid'),
                notification.notification_uuid)
        except exception.IgnoreInstanceRecoveryException as e:
            notification_status = fields.NotificationStatus.IGNORED
            exception_info = e
        except exception.SkipInstanceRecoveryException:
            notification_status = fields.NotificationStatus.FINISHED
        except (exception.MasakariException,
                exception.InstanceRecoveryFailureException) as e:
            notification_status = fields.NotificationStatus.ERROR
            LOG.error("Failed to process notification '%(uuid)s'."
                      " Reason: %(error)s",
                      {"uuid": notification.notification_uuid,
                       "error": e.message})
            exception_info = e

        if exception_info:
            tb = traceback.format_exc()
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.ERROR,
                exception=str(exception_info),
                tb=tb)
        else:
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.END)

        return notification_status

    def _handle_notification_type_host(self, context, notification):
        host_status = notification.payload.get('host_status')
        notification_status = fields.NotificationStatus.FINISHED
        notification_event = notification.payload.get('event')
        exception_info = None

        if host_status is None:
            LOG.warning("Notification '%(uuid)s' ignored as host_status is "
                        "not provided.",
                        {'uuid': notification.notification_uuid})
            notification_status = fields.NotificationStatus.IGNORED
        elif host_status.upper() != fields.HostStatusType.NORMAL:
            # NOTE(shilpasd): Avoid host recovery for host_status other than
            # 'NORMAL' otherwise it could lead to unsafe evacuation of
            # instances running on the failed source host.
            LOG.warning("Notification '%(uuid)s' ignored as host_status "
                        "is '%(host_status)s'",
                        {'uuid': notification.notification_uuid,
                         'host_status': host_status.upper()})
            notification_status = fields.NotificationStatus.IGNORED
        elif notification_event.upper() == 'STARTED':
            LOG.info("Notification type '%(type)s' received for host "
                     "'%(host_uuid)s' has been %(event)s.",
                     {'type': notification.type,
                      'host_uuid': notification.source_host_uuid,
                      'event': notification_event})
        elif notification_event.upper() == 'STOPPED':
            host_obj = objects.Host.get_by_uuid(
                context, notification.source_host_uuid)
            host_name = host_obj.name
            recovery_method = host_obj.failover_segment.recovery_method

            # Mark host on_maintenance mode as True
            update_data = {
                'on_maintenance': True,
            }

            # Set reserved flag to False if this host is reserved
            if host_obj.reserved:
                update_data['reserved'] = False

            LOG.info("Set host %s on maintenance.", host_name)
            host_obj.update(update_data)
            host_obj.save()

            reserved_host_list = None

            if not recovery_method == (
                    fields.FailoverSegmentRecoveryMethod.AUTO):
                reserved_host_object_list = objects.HostList.get_all(
                    context, filters={
                        'failover_segment_id': host_obj.failover_segment.uuid,
                        'reserved': True,
                        'on_maintenance': False
                        })
                # Create list of host name from reserved_host_object_list
                reserved_host_list = [host.name for host in
                                      reserved_host_object_list]

            try:
                self.driver.execute_host_failure(
                    context, host_name, recovery_method,
                    notification.notification_uuid,
                    update_host_method=update_host_method,
                    reserved_host_list=reserved_host_list)
            except exception.SkipHostRecoveryException:
                notification_status = fields.NotificationStatus.FINISHED
            except (exception.HostRecoveryFailureException,
                    exception.ReservedHostsUnavailable,
                    exception.MasakariException) as e:
                notification_status = fields.NotificationStatus.ERROR
                LOG.error("Failed to process notification '%(uuid)s'."
                          " Reason: %(error)s",
                          {"uuid": notification.notification_uuid,
                           "error": e.message})
                exception_info = e
        else:
            LOG.warning("Invalid event: %(event)s received for "
                        "notification type: %(type)s",
                        {'event': notification_event,
                         'type': notification.type})
            notification_status = fields.NotificationStatus.IGNORED

        if exception_info:
            tb = traceback.format_exc()
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.ERROR,
                exception=str(exception_info),
                tb=tb)
        else:
            engine_utils.notify_about_notification_update(context,
                notification,
                action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
                phase=fields.EventNotificationPhase.END)

        return notification_status

    def _process_notification(self, context, notification):
        @utils.synchronized(notification.source_host_uuid, blocking=True)
        def do_process_notification(notification):
            LOG.info('Processing notification %(notification_uuid)s of '
                     'type: %(type)s',
                     {'notification_uuid': notification.notification_uuid,
                      'type': notification.type})

            # Get notification from db
            notification_db = objects.Notification.get_by_uuid(context,
                                        notification.notification_uuid)

            # NOTE(tpatil): To fix bug 1773132, process notification only
            # if the notification status is New and the current notification
            # from DB status is Not New to avoid recovering from failure twice
            if (notification.status == fields.NotificationStatus.NEW and
                    notification_db.status != fields.NotificationStatus.NEW):
                LOG.warning("Processing of notification is skipped to avoid "
                            "recovering from failure twice. "
                            "Notification received is '%(uuid)s' "
                            "and it's status is '%(new_status)s' and the "
                            "current status of same notification in db "
                            "is '%(old_status)s'",
                            {"uuid": notification.notification_uuid,
                            "new_status": notification.status,
                            "old_status": notification_db.status})
                return

            update_data = {
                'status': fields.NotificationStatus.RUNNING,
            }
            notification.update(update_data)
            notification.save()

            if notification.type == fields.NotificationType.PROCESS:
                notification_status = self._handle_notification_type_process(
                    context, notification)
            elif notification.type == fields.NotificationType.VM:
                notification_status = self._handle_notification_type_instance(
                    context, notification)
            elif notification.type == fields.NotificationType.COMPUTE_HOST:
                notification_status = self._handle_notification_type_host(
                    context, notification)

            LOG.info("Notification %(notification_uuid)s exits with "
                     "status: %(status)s.",
                     {'notification_uuid': notification.notification_uuid,
                      'status': notification_status})

            update_data = {
                'status': notification_status
            }
            notification.update(update_data)
            notification.save()

        engine_utils.notify_about_notification_update(context,
            notification,
            action=fields.EventNotificationAction.NOTIFICATION_PROCESS,
            phase=fields.EventNotificationPhase.START)

        do_process_notification(notification)

    def process_notification(self, context, notification=None):
        """Processes the notification"""
        host = objects.Host.get_by_uuid(
            context, notification.source_host_uuid)
        if not host.failover_segment.enabled:
            update_data = {
                'status': fields.NotificationStatus.IGNORED,
            }
            notification.update(update_data)
            notification.save()
            msg = ('Notification %(notification_uuid)s of type: %(type)s '
                   'is ignored, because the failover segment is disabled.',
                   {'notification_uuid': notification.notification_uuid,
                    'type': notification.type})
            raise exception.FailoverSegmentDisabled(msg)

        self._process_notification(context, notification)

    @periodic_task.periodic_task(
        spacing=CONF.process_unfinished_notifications_interval)
    def _process_unfinished_notifications(self, context):
        filters = {
            'status': [fields.NotificationStatus.ERROR,
                       fields.NotificationStatus.NEW]
        }
        notifications_list = objects.NotificationList.get_all(context,
                                                              filters=filters)

        for notification in notifications_list:
            if (notification.status == fields.NotificationStatus.ERROR or
                    (notification.status == fields.NotificationStatus.NEW and
                timeutils.is_older_than(
                    notification.generated_time,
                    CONF.retry_notification_new_status_interval))):
                self._process_notification(context, notification)

            # get updated notification from db after workflow execution
            notification_db = objects.Notification.get_by_uuid(
                context, notification.notification_uuid)

            if notification_db.status == fields.NotificationStatus.ERROR:
                # update notification status as failed
                notification_status = fields.NotificationStatus.FAILED
                update_data = {
                    'status': notification_status
                }

                notification_db.update(update_data)
                notification_db.save()
                LOG.error(
                    "Periodic task 'process_unfinished_notifications': "
                    "Notification %(notification_uuid)s exits with "
                    "status: %(status)s.",
                    {'notification_uuid': notification.notification_uuid,
                     'status': notification_status})

    @periodic_task.periodic_task(
        spacing=CONF.check_expired_notifications_interval)
    def _check_expired_notifications(self, context):
        filters = {
            'status': [fields.NotificationStatus.RUNNING,
                       fields.NotificationStatus.ERROR,
                       fields.NotificationStatus.NEW]
        }
        notifications_list = objects.NotificationList.get_all(context,
                                                              filters=filters)

        for notification in notifications_list:
            if timeutils.is_older_than(
                    notification.generated_time,
                    CONF.notifications_expired_interval):
                # update running expired notification status as failed
                notification_status = fields.NotificationStatus.FAILED
                update_data = {
                    'status': notification_status
                }

                notification.update(update_data)
                notification.save()
                LOG.error(
                    "Periodic task 'check_expired_notifications': "
                    "Notification %(notification_uuid)s is expired.",
                    {'notification_uuid': notification.notification_uuid})

    def get_notification_recovery_workflow_details(self, context,
                                                   notification):
        """Retrieve recovery workflow details of the notification"""
        try:
            host_obj = objects.Host.get_by_uuid(
                context, notification.source_host_uuid)
            recovery_method = host_obj.failover_segment.recovery_method

            progress_details = (
                self.driver.get_notification_recovery_workflow_details(
                    context, recovery_method, notification))
            notification['recovery_workflow_details'] = progress_details
        except Exception:
            msg = (_('Failed to fetch notification recovery workflow details '
                     'for %s') % notification.notification_uuid)
            LOG.exception(msg)
            raise exception.MasakariException(msg)

        return notification
