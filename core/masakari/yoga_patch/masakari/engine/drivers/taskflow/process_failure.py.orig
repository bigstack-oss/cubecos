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
from taskflow.patterns import linear_flow

import masakari.conf
from masakari.engine.drivers.taskflow import base
from masakari import exception


CONF = masakari.conf.CONF
LOG = logging.getLogger(__name__)
ACTION = "process:recovery"
TASKFLOW_CONF = cfg.CONF.taskflow_driver_recovery_flows


class DisableComputeNodeTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["process_name", "host_name"]
        super(DisableComputeNodeTask, self).__init__(context,
                                                     novaclient,
                                                     **kwargs)

    def execute(self, process_name, host_name):
        msg = "Disabling compute service on host: '%s'" % host_name
        self.update_details(msg)

        if not self.novaclient.is_service_disabled(self.context, host_name,
                                                   process_name):
            # disable compute node on given host
            self.novaclient.enable_disable_service(self.context, host_name,
                reason=CONF.process_failure.service_disable_reason)
            msg = "Disabled compute service on host: '%s'" % host_name
            self.update_details(msg, 1.0)
        else:
            msg = ("Skipping recovery for process %(process_name)s as it is "
                   "already disabled") % {'process_name': process_name}
            LOG.info(msg)
            self.update_details(msg, 1.0)


class ConfirmComputeNodeDisabledTask(base.MasakariTask):
    def __init__(self, context, novaclient, **kwargs):
        kwargs['requires'] = ["process_name", "host_name"]
        super(ConfirmComputeNodeDisabledTask, self).__init__(context,
                                                             novaclient,
                                                             **kwargs)

    def execute(self, process_name, host_name):
        def _wait_for_disable():
            service_disabled = self.novaclient.is_service_disabled(
                self.context, host_name, process_name)
            if service_disabled:
                raise loopingcall.LoopingCallDone()

        periodic_call = loopingcall.FixedIntervalLoopingCall(
            _wait_for_disable)
        try:
            msg = "Confirming compute service is disabled on host: '%s'" % (
                host_name)
            self.update_details(msg)

            # add a timeout to the periodic call.
            periodic_call.start(interval=CONF.verify_interval)
            etimeout.with_timeout(
                CONF.wait_period_after_service_update,
                periodic_call.wait)

            msg = "Confirmed compute service is disabled on host: '%s'" % (
                host_name)
            self.update_details(msg, 1.0)
        except etimeout.Timeout:
            msg = "Failed to disable service %(process_name)s" % {
                'process_name': process_name
            }
            self.update_details(msg, 1.0)
            raise exception.ProcessRecoveryFailureException(
                message=msg)
        finally:
            # stop the periodic call, in case of exceptions or Timeout.
            periodic_call.stop()


def get_compute_process_recovery_flow(context, novaclient, process_what):
    """Constructs and returns the engine entrypoint flow.

    This flow will do the following:

    1. Disable nova-compute process
    2. Confirm nova-compute process is disabled
    """

    flow_name = ACTION.replace(":", "_") + "_engine"
    nested_flow = linear_flow.Flow(flow_name)

    task_dict = TASKFLOW_CONF.process_failure_recovery_tasks

    process_recovery_workflow_pre = linear_flow.Flow('pre_tasks')
    for plugin in base.get_recovery_flow(task_dict['pre'], context=context,
                                         novaclient=novaclient):
        process_recovery_workflow_pre.add(plugin)

    process_recovery_workflow_main = linear_flow.Flow('main_tasks')
    for plugin in base.get_recovery_flow(task_dict['main'], context=context,
                                         novaclient=novaclient):
        process_recovery_workflow_main.add(plugin)

    process_recovery_workflow_post = linear_flow.Flow('post_tasks')
    for plugin in base.get_recovery_flow(task_dict['post'], context=context,
                                         novaclient=novaclient):
        process_recovery_workflow_post.add(plugin)

    nested_flow.add(process_recovery_workflow_pre)
    nested_flow.add(process_recovery_workflow_main)
    nested_flow.add(process_recovery_workflow_post)

    return base.load_taskflow_into_engine(ACTION, nested_flow,
                                          process_what)
