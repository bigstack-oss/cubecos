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

from eventlet import timeout as etimeout

from oslo_config import cfg
from oslo_log import log as logging
from oslo_service import loopingcall
from oslo_utils import strutils
from taskflow.patterns import linear_flow

import masakari.conf
from masakari.engine.drivers.taskflow import base
from masakari import exception


CONF = masakari.conf.CONF
LOG = logging.getLogger(__name__)
ACTION = "instance:recovery"
TASKFLOW_CONF = cfg.CONF.taskflow_driver_recovery_flows


class StopInstanceTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["instance_uuid"]
        super(StopInstanceTask, self).__init__(context,
                                               novaclient,
                                               **kwargs)

    def execute(self, instance_uuid):
        """Stop the instance for recovery."""
        instance = self.novaclient.get_server(self.context, instance_uuid)

        ha_enabled_key = CONF.instance_failure.ha_enabled_instance_metadata_key

        # If an instance is not HA_Enabled and "process_all_instances" config
        # option is also disabled, then there is no need to take any recovery
        # action.
        if not CONF.instance_failure.process_all_instances and not (
                strutils.bool_from_string(
                    instance.metadata.get(ha_enabled_key, False))):
            msg = ("Skipping recovery for instance: %(instance_uuid)s as it is"
                   " not Ha_Enabled") % {'instance_uuid': instance_uuid}
            LOG.info(msg)
            self.update_details(msg, 1.0)
            raise exception.SkipInstanceRecoveryException()

        vm_state = getattr(instance, 'OS-EXT-STS:vm_state')
        if vm_state in ['paused', 'rescued']:
            msg = ("Recovery of instance '%(instance_uuid)s' is ignored as it "
                   "is in '%(vm_state)s' state.") % {
                'instance_uuid': instance_uuid, 'vm_state': vm_state
            }
            LOG.warning(msg)
            self.update_details(msg, 1.0)
            raise exception.IgnoreInstanceRecoveryException(msg)

        if vm_state != 'stopped':
            if vm_state == 'resized':
                self.novaclient.reset_instance_state(
                    self.context, instance.id, 'active')

            msg = "Stopping instance: %s" % instance_uuid
            self.update_details(msg)

            try:
                self.novaclient.stop_server(self.context, instance.id)
            except exception.Conflict:
                msg = "Conflict when stopping instance: %s" % instance_uuid
                self.update_details(msg)
                instance = self.novaclient.get_server(self.context,
                                                      instance_uuid)
                vm_state = getattr(instance, 'OS-EXT-STS:vm_state')
                if vm_state != 'stopped':
                    raise

        def _wait_for_power_off():
            new_instance = self.novaclient.get_server(self.context,
                                                      instance_uuid)
            vm_state = getattr(new_instance, 'OS-EXT-STS:vm_state')
            if vm_state == 'stopped':
                raise loopingcall.LoopingCallDone()

        periodic_call = loopingcall.FixedIntervalLoopingCall(
            _wait_for_power_off)

        try:
            # add a timeout to the periodic call.
            periodic_call.start(interval=CONF.verify_interval)
            etimeout.with_timeout(CONF.wait_period_after_power_off,
                                  periodic_call.wait)
            msg = "Stopped instance: '%s'" % instance_uuid
            self.update_details(msg, 1.0)
        except etimeout.Timeout:
            msg = "Failed to stop instance %(instance)s" % {
                'instance': instance.id
            }
            self.update_details(msg, 1.0)
            raise exception.InstanceRecoveryFailureException(
                message=msg)
        finally:
            # stop the periodic call, in case of exceptions or Timeout.
            periodic_call.stop()


class StartInstanceTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["instance_uuid"]
        super(StartInstanceTask, self).__init__(context,
                                                novaclient,
                                                **kwargs)

    def execute(self, instance_uuid):
        """Start the instance."""
        msg = "Starting instance: '%s'" % instance_uuid
        self.update_details(msg)

        instance = self.novaclient.get_server(self.context, instance_uuid)
        vm_state = getattr(instance, 'OS-EXT-STS:vm_state')
        if vm_state == 'stopped':
            self.novaclient.start_server(self.context, instance.id)
            msg = "Instance started: '%s'" % instance_uuid
            self.update_details(msg, 1.0)
        else:
            msg = ("Invalid state for Instance %(instance)s. Expected state: "
                   "'STOPPED', Actual state: '%(actual_state)s'") % {
                'instance': instance_uuid,
                'actual_state': vm_state
            }
            self.update_details(msg, 1.0)
            raise exception.InstanceRecoveryFailureException(
                message=msg)


class ConfirmInstanceActiveTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["instance_uuid"]
        super(ConfirmInstanceActiveTask, self).__init__(context,
                                                        novaclient,
                                                        **kwargs)

    def execute(self, instance_uuid):
        def _wait_for_active():
            new_instance = self.novaclient.get_server(self.context,
                                                      instance_uuid)
            vm_state = getattr(new_instance, 'OS-EXT-STS:vm_state')
            if vm_state == 'active':
                raise loopingcall.LoopingCallDone()

        periodic_call = loopingcall.FixedIntervalLoopingCall(
            _wait_for_active)
        try:
            msg = "Confirming instance '%s' vm_state is ACTIVE" % instance_uuid
            self.update_details(msg)

            # add a timeout to the periodic call.
            periodic_call.start(interval=CONF.verify_interval)
            etimeout.with_timeout(CONF.wait_period_after_power_on,
                                  periodic_call.wait)

            msg = "Confirmed instance '%s' vm_state is ACTIVE" % instance_uuid
            self.update_details(msg, 1.0)
        except etimeout.Timeout:
            msg = "Failed to start instance %(instance)s" % {
                'instance': instance_uuid
            }
            self.update_details(msg, 1.0)
            raise exception.InstanceRecoveryFailureException(
                message=msg)
        finally:
            # stop the periodic call, in case of exceptions or Timeout.
            periodic_call.stop()


def get_instance_recovery_flow(context, novaclient, process_what):
    """Constructs and returns the engine entrypoint flow.

    This flow will do the following:

    1. Stop the instance
    2. Start the instance.
    3. Confirm instance is in active state.
    """

    flow_name = ACTION.replace(":", "_") + "_engine"
    nested_flow = linear_flow.Flow(flow_name)

    task_dict = TASKFLOW_CONF.instance_failure_recovery_tasks

    instance_recovery_workflow_pre = linear_flow.Flow('pre_tasks')
    for plugin in base.get_recovery_flow(task_dict['pre'], context=context,
                                         novaclient=novaclient):
        instance_recovery_workflow_pre.add(plugin)

    instance_recovery_workflow_main = linear_flow.Flow('main_tasks')
    for plugin in base.get_recovery_flow(task_dict['main'], context=context,
                                         novaclient=novaclient):
        instance_recovery_workflow_main.add(plugin)

    instance_recovery_workflow_post = linear_flow.Flow('post_tasks')
    for plugin in base.get_recovery_flow(task_dict['post'], context=context,
                                         novaclient=novaclient):
        instance_recovery_workflow_post.add(plugin)

    nested_flow.add(instance_recovery_workflow_pre)
    nested_flow.add(instance_recovery_workflow_main)
    nested_flow.add(instance_recovery_workflow_post)

    return base.load_taskflow_into_engine(ACTION, nested_flow,
                                          process_what)
