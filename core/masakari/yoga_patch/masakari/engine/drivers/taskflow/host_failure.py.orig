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

import eventlet
from eventlet import greenpool
from eventlet import timeout as etimeout

from oslo_config import cfg
from oslo_log import log as logging
from oslo_service import loopingcall
from oslo_utils import excutils
from oslo_utils import strutils
from taskflow.patterns import linear_flow
from taskflow import retry

import masakari.conf
from masakari.engine.drivers.taskflow import base
from masakari import exception
from masakari import utils


CONF = masakari.conf.CONF
LOG = logging.getLogger(__name__)
ACTION = 'instance:evacuate'
# Instance power_state
SHUTDOWN = 4
TASKFLOW_CONF = cfg.CONF.taskflow_driver_recovery_flows


class DisableComputeServiceTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["host_name"]
        super(DisableComputeServiceTask, self).__init__(context, novaclient,
                                                        **kwargs)

    def execute(self, host_name):
        msg = "Disabling compute service on host: '%s'" % host_name
        self.update_details(msg)
        self.novaclient.enable_disable_service(self.context, host_name,
            reason=CONF.host_failure.service_disable_reason)
        # Sleep until nova-compute service is marked as disabled.
        log_msg = ("Sleeping %(wait)s sec before starting recovery "
               "thread until nova recognizes the node down.")
        LOG.info(log_msg, {'wait': CONF.wait_period_after_service_update})
        eventlet.sleep(CONF.wait_period_after_service_update)
        msg = "Disabled compute service on host: '%s'" % host_name
        self.update_details(msg, 1.0)


class PrepareHAEnabledInstancesTask(base.MasakariTask):
    """Get all HA_Enabled instances."""
    default_provides = set(["instance_list"])

    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["host_name"]
        super(PrepareHAEnabledInstancesTask, self).__init__(context,
                                                            novaclient,
                                                            **kwargs)

    def execute(self, host_name):
        def _filter_instances(instance_list):
            ha_enabled_instances = []
            non_ha_enabled_instances = []

            ha_enabled_key = CONF.host_failure.ha_enabled_instance_metadata_key

            for instance in instance_list:
                is_instance_ha_enabled = strutils.bool_from_string(
                    instance.metadata.get(ha_enabled_key, False))
                if CONF.host_failure.ignore_instances_in_error_state and (
                        getattr(instance, "OS-EXT-STS:vm_state") == "error"):
                    if is_instance_ha_enabled:
                        msg = ("Ignoring recovery of HA_Enabled instance "
                               "'%(instance_id)s' as it is in 'error' state."
                               ) % {'instance_id': instance.id}
                        LOG.info(msg)
                        self.update_details(msg, 0.4)
                    continue

                if is_instance_ha_enabled:
                    ha_enabled_instances.append(instance)
                else:
                    non_ha_enabled_instances.append(instance)

            msg = "Total HA Enabled instances count: '%d'" % len(
                ha_enabled_instances)
            self.update_details(msg, 0.6)

            if CONF.host_failure.evacuate_all_instances:
                msg = ("Total Non-HA Enabled instances count: '%d'" % len(
                    non_ha_enabled_instances))
                self.update_details(msg, 0.7)

                ha_enabled_instances.extend(non_ha_enabled_instances)

                msg = ("All instances (HA Enabled/Non-HA Enabled) should be "
                       "considered for evacuation. Total count is: '%d'") % (
                    len(ha_enabled_instances))
                self.update_details(msg, 0.8)

            return ha_enabled_instances

        msg = "Preparing instances for evacuation"
        self.update_details(msg)

        instance_list = self.novaclient.get_servers(self.context, host_name)

        msg = ("Total instances running on failed host '%(host_name)s' is "
               "%(instance_list)d") % {'host_name': host_name,
                                       'instance_list': len(instance_list)}
        self.update_details(msg, 0.3)

        instance_list = _filter_instances(instance_list)

        if not instance_list:
            msg = ("Skipped host '%s' recovery as no instances needs to be "
                   "evacuated" % host_name)
            self.update_details(msg, 1.0)
            LOG.info(msg)
            raise exception.SkipHostRecoveryException(message=msg)

        # List of instance UUID
        instance_list = [instance.id for instance in instance_list]

        msg = "Instances to be evacuated are: '%s'" % ','.join(instance_list)
        self.update_details(msg, 1.0)

        return {
            "instance_list": instance_list,
        }


class EvacuateInstancesTask(base.MasakariTask):

    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["host_name", "instance_list"]
        self.update_host_method = kwargs['update_host_method']
        super(EvacuateInstancesTask, self).__init__(context, novaclient,
                                                    **kwargs)

    def _get_state_and_host_of_instance(self, context, instance):
        new_instance = self.novaclient.get_server(context, instance.id)
        instance_host = getattr(new_instance,
                                "OS-EXT-SRV-ATTR:hypervisor_hostname")
        old_vm_state = getattr(instance, "OS-EXT-STS:vm_state")
        new_vm_state = getattr(new_instance, "OS-EXT-STS:vm_state")

        return (old_vm_state, new_vm_state, instance_host)

    def _stop_after_evacuation(self, context, instance):
        def _wait_for_stop_confirmation():
            old_vm_state, new_vm_state, instance_host = (
                self._get_state_and_host_of_instance(context, instance))

            if new_vm_state == 'stopped':
                raise loopingcall.LoopingCallDone()

        periodic_call_stopped = loopingcall.FixedIntervalLoopingCall(
            _wait_for_stop_confirmation)

        try:
            self.novaclient.stop_server(context, instance.id)
            # confirm instance is stopped after recovery
            periodic_call_stopped.start(interval=CONF.verify_interval)
            etimeout.with_timeout(
                CONF.wait_period_after_power_off,
                periodic_call_stopped.wait)
        except etimeout.Timeout:
            with excutils.save_and_reraise_exception():
                msg = ("Instance '%(uuid)s' is successfully evacuated but "
                       "timeout to stop.") % {'uuid': instance.id}
                LOG.warning(msg)
        finally:
            periodic_call_stopped.stop()

    def _evacuate_and_confirm(self, context, instance, host_name,
                              failed_evacuation_instances,
                              reserved_host=None):
        # Before locking the instance check whether it is already locked
        # by user, if yes don't lock the instance
        instance_already_locked = self.novaclient.get_server(
            context, instance.id).locked

        if not instance_already_locked:
            # lock the instance so that until evacuation and confirmation
            # is not complete, user won't be able to perform any actions
            # on the instance.
            self.novaclient.lock_server(context, instance.id)

        def _wait_for_evacuation_confirmation():
            old_vm_state, new_vm_state, instance_host = (
                self._get_state_and_host_of_instance(context, instance))

            if (new_vm_state == 'error' and
                    new_vm_state != old_vm_state):
                raise exception.InstanceEvacuateFailed(
                    instance_uuid=instance.id)

            if instance_host != host_name:
                if ((old_vm_state == 'error' and
                    new_vm_state == 'active') or
                        old_vm_state == new_vm_state):
                    raise loopingcall.LoopingCallDone()

        def _wait_for_evacuation():
            periodic_call = loopingcall.FixedIntervalLoopingCall(
                _wait_for_evacuation_confirmation)

            try:
                # add a timeout to the periodic call.
                periodic_call.start(interval=CONF.verify_interval)
                etimeout.with_timeout(
                    CONF.wait_period_after_evacuation,
                    periodic_call.wait)
            except etimeout.Timeout:
                with excutils.save_and_reraise_exception():
                    msg = ("Timeout for instance '%(uuid)s' evacuation."
                           % {'uuid': instance.id})
                    LOG.warning(msg)
            finally:
                # stop the periodic call, in case of exceptions or
                # Timeout.
                periodic_call.stop()

        try:
            vm_state = getattr(instance, "OS-EXT-STS:vm_state")
            task_state = getattr(instance, "OS-EXT-STS:task_state")

            # Nova evacuates an instance only when vm_state is in active,
            # stopped or error state. If an instance is in other than active,
            # error and stopped vm_state, masakari resets the instance state
            # to *error* so that the instance can be evacuated.
            stop_instance = True
            if vm_state not in ['active', 'error', 'stopped']:
                self.novaclient.reset_instance_state(context, instance.id)
                instance = self.novaclient.get_server(context, instance.id)
                power_state = getattr(instance, "OS-EXT-STS:power_state")
                if vm_state == 'resized' and power_state != SHUTDOWN:
                    stop_instance = False

            elif vm_state == 'stopped' and task_state is None:
                # If vm_state is stopped and task_state is none, the instance
                # will be recovered with vm_state 'stopped'.
                # So it doesn't need to stop the instance after evacuation.
                stop_instance = False

            elif task_state is not None:
                # Nova fails evacuation when the instance's task_state is not
                # none. In this case, masakari resets the instance's vm_state
                # to 'error' and task_state to none.
                self.novaclient.reset_instance_state(context, instance.id)
                instance = self.novaclient.get_server(context, instance.id)
                if vm_state == 'active':
                    stop_instance = False

            # evacuate the instance
            self.novaclient.evacuate_instance(context, instance.id,
                                              target=reserved_host)

            _wait_for_evacuation()

            if vm_state != 'active':
                if stop_instance:
                    self._stop_after_evacuation(self.context, instance)
                    # If the instance was in 'error' state before failure
                    # it should be set to 'error' after recovery.
                    if vm_state == 'error':
                        self.novaclient.reset_instance_state(
                            context, instance.id)
        except etimeout.Timeout:
            # Instance is not stop in the expected time_limit.
            failed_evacuation_instances.append(instance.id)
        except Exception as e:
            # Exception is raised while resetting instance state or
            # evacuating the instance itself.
            LOG.warning(str(e))
            failed_evacuation_instances.append(instance.id)
        finally:
            if not instance_already_locked:
                # Unlock the server after evacuation and confirmation
                self.novaclient.unlock_server(context, instance.id)

    def execute(self, host_name, instance_list, reserved_host=None):
        msg = ("Start evacuation of instances from failed host '%(host_name)s'"
               ", instance uuids are: '%(instance_list)s'") % {
            'host_name': host_name, 'instance_list': ','.join(instance_list)}
        self.update_details(msg)

        def _do_evacuate(context, host_name, instance_list,
                         reserved_host=None):
            failed_evacuation_instances = []

            if reserved_host:
                msg = "Enabling reserved host: '%s'" % reserved_host
                self.update_details(msg, 0.1)
                if CONF.host_failure.add_reserved_host_to_aggregate:
                    # Assign reserved_host to an aggregate to which the failed
                    # compute host belongs to.
                    aggregates = self.novaclient.get_aggregate_list(context)
                    for aggregate in aggregates:
                        if host_name in aggregate.hosts:
                            try:
                                msg = ("Add host %(reserved_host)s to "
                                       "aggregate %(aggregate)s") % {
                                    'reserved_host': reserved_host,
                                    'aggregate': aggregate.name}
                                self.update_details(msg, 0.2)

                                self.novaclient.add_host_to_aggregate(
                                    context, reserved_host, aggregate)
                                msg = ("Added host %(reserved_host)s to "
                                       "aggregate %(aggregate)s") % {
                                    'reserved_host': reserved_host,
                                    'aggregate': aggregate.name}
                                self.update_details(msg, 0.3)
                            except exception.Conflict:
                                msg = ("Host '%(reserved_host)s' already has "
                                       "been added to aggregate "
                                       "'%(aggregate)s'.") % {
                                    'reserved_host': reserved_host,
                                    'aggregate': aggregate.name}
                                self.update_details(msg, 1.0)
                                LOG.info(msg)

                self.novaclient.enable_disable_service(
                    context, reserved_host, enable=True)

                # Set reserved property of reserved_host to False
                self.update_host_method(self.context, reserved_host)

            thread_pool = greenpool.GreenPool(
                CONF.host_failure_recovery_threads)

            for instance_id in instance_list:
                msg = "Evacuation of instance started: '%s'" % instance_id
                self.update_details(msg, 0.5)
                instance = self.novaclient.get_server(self.context,
                                                      instance_id)
                thread_pool.spawn_n(self._evacuate_and_confirm, context,
                                    instance, host_name,
                                    failed_evacuation_instances,
                                    reserved_host)

            thread_pool.waitall()

            evacuated_instances = list(set(instance_list).difference(set(
                failed_evacuation_instances)))

            if evacuated_instances:
                evacuated_instances.sort()
                msg = ("Successfully evacuate instances '%(instance_list)s' "
                       "from host '%(host_name)s'") % {
                    'instance_list': ','.join(evacuated_instances),
                    'host_name': host_name}
                self.update_details(msg, 0.7)

            if failed_evacuation_instances:
                msg = ("Failed to evacuate instances "
                       "'%(failed_evacuation_instances)s' from host "
                       "'%(host_name)s'") % {
                    'failed_evacuation_instances':
                        ','.join(failed_evacuation_instances),
                    'host_name': host_name}
                self.update_details(msg, 0.7)
                raise exception.HostRecoveryFailureException(
                    message=msg)

            msg = "Evacuation process completed!"
            self.update_details(msg, 1.0)

        lock_name = reserved_host if reserved_host else None

        @utils.synchronized(lock_name)
        def do_evacuate_with_reserved_host(context, host_name, instance_list,
                                           reserved_host):
            _do_evacuate(self.context, host_name, instance_list,
                         reserved_host=reserved_host)

        if lock_name:
            do_evacuate_with_reserved_host(self.context, host_name,
                                           instance_list, reserved_host)
        else:
            # No need to acquire lock on reserved_host when recovery_method is
            # 'auto' as the selection of compute host will be decided by nova.
            _do_evacuate(self.context, host_name, instance_list)


def get_auto_flow(context, novaclient, process_what):
    """Constructs and returns the engine entrypoint flow.

    This flow will do the following:

    1. Disable compute service on source host
    2. Get all HA_Enabled instances.
    3. Evacuate all the HA_Enabled instances.
    4. Confirm evacuation of instances.
    """

    flow_name = ACTION.replace(":", "_") + "_engine"
    nested_flow = linear_flow.Flow(flow_name)

    task_dict = TASKFLOW_CONF.host_auto_failure_recovery_tasks

    auto_evacuate_flow_pre = linear_flow.Flow('pre_tasks')
    for plugin in base.get_recovery_flow(task_dict['pre'], context=context,
                                         novaclient=novaclient,
                                         update_host_method=None):
        auto_evacuate_flow_pre.add(plugin)

    auto_evacuate_flow_main = linear_flow.Flow('main_tasks')
    for plugin in base.get_recovery_flow(task_dict['main'], context=context,
                                         novaclient=novaclient,
                                         update_host_method=None):
        auto_evacuate_flow_main.add(plugin)

    auto_evacuate_flow_post = linear_flow.Flow('post_tasks')
    for plugin in base.get_recovery_flow(task_dict['post'], context=context,
                                         novaclient=novaclient,
                                         update_host_method=None):
        auto_evacuate_flow_post.add(plugin)

    nested_flow.add(auto_evacuate_flow_pre)
    nested_flow.add(auto_evacuate_flow_main)
    nested_flow.add(auto_evacuate_flow_post)

    return base.load_taskflow_into_engine(ACTION, nested_flow,
                                          process_what)


def get_rh_flow(context, novaclient, process_what, **kwargs):
    """Constructs and returns the engine entrypoint flow.

    This flow will do the following:

    1. Disable compute service on source host
    2. Get all HA_Enabled instances.
    3. Evacuate all the HA_Enabled instances using reserved_host.
    4. Confirm evacuation of instances.
    """
    flow_name = ACTION.replace(":", "_") + "_engine"
    nested_flow = linear_flow.Flow(flow_name)

    task_dict = TASKFLOW_CONF.host_rh_failure_recovery_tasks

    rh_evacuate_flow_pre = linear_flow.Flow('pre_tasks')
    for plugin in base.get_recovery_flow(
            task_dict['pre'],
            context=context, novaclient=novaclient, **kwargs):
        rh_evacuate_flow_pre.add(plugin)

    rh_evacuate_flow_main = linear_flow.Flow(
        "retry_%s" % flow_name, retry=retry.ParameterizedForEach(
            rebind=['reserved_host_list'], provides='reserved_host'))

    for plugin in base.get_recovery_flow(
            task_dict['main'],
            context=context, novaclient=novaclient, **kwargs):
        rh_evacuate_flow_main.add(plugin)

    rh_evacuate_flow_post = linear_flow.Flow('post_tasks')
    for plugin in base.get_recovery_flow(
            task_dict['post'],
            context=context, novaclient=novaclient, **kwargs):
        rh_evacuate_flow_post.add(plugin)

    nested_flow.add(rh_evacuate_flow_pre)
    nested_flow.add(rh_evacuate_flow_main)
    nested_flow.add(rh_evacuate_flow_post)

    return base.load_taskflow_into_engine(ACTION, nested_flow,
                                          process_what)
