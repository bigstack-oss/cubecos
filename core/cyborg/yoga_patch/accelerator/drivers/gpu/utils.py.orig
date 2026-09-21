# Copyright 2018 Beijing Lenovo Software Ltd.
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


"""
Utils for GPU driver.
"""
from oslo_concurrency import processutils
from oslo_log import log as logging
from oslo_serialization import jsonutils

import re

from cyborg.accelerator.common import utils
from cyborg.common import constants
from cyborg.conf import CONF
from cyborg.objects.driver_objects import driver_attach_handle
from cyborg.objects.driver_objects import driver_attribute
from cyborg.objects.driver_objects import driver_controlpath_id
from cyborg.objects.driver_objects import driver_deployable
from cyborg.objects.driver_objects import driver_device
import cyborg.privsep

LOG = logging.getLogger(__name__)

GPU_FLAGS = ["VGA compatible controller", "3D controller"]
GPU_INFO_PATTERN = re.compile(r"(?P<devices>[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:"
                              r"[0-9a-fA-F]{2}\.[0-9a-fA-F]) "
                              r"(?P<controller>.*) [\[].*]: (?P<model>.*) .*"
                              r"[\[](?P<vendor_id>[0-9a-fA-F]"
                              r"{4}):(?P<product_id>[0-9a-fA-F]{4})].*")

VENDOR_MAPS = {"10de": "nvidia", "102b": "matrox"}


@cyborg.privsep.sys_admin_pctxt.entrypoint
def lspci_privileged():
    cmd = ['lspci', '-nnn', '-D']
    return processutils.execute(*cmd)


def get_pci_devices(pci_flags, vendor_id=None):
    device_for_vendor_out = []
    all_device_out = []
    lspci_out = lspci_privileged()[0].split('\n')
    for pci in lspci_out:
        if any(x in pci for x in pci_flags):
            all_device_out.append(pci)
            if vendor_id and vendor_id in pci:
                device_for_vendor_out.append(pci)
    return device_for_vendor_out if vendor_id else all_device_out


def get_traits(vendor_id, product_id):
    """Generate traits for GPUs.
    : param vendor_id: vendor_id of PGPU/VGPU, eg."10de"
    : param product_id: product_id of PGPU/VGPU, eg."1eb8".
    Example VGPU traits:
    {traits:["CUSTOM_GPU_NVIDIA", "CUSTOM_GPU_PRODUCT_ID_1EB8"]}
    """
    traits = []
    traits.append("CUSTOM_GPU_" + VENDOR_MAPS.get(vendor_id, "").upper())
    traits.append("CUSTOM_GPU_PRODUCT_ID_" + product_id.upper())
    return {"traits": traits}


def discover_vendors():
    vendors = set()
    gpus = get_pci_devices(GPU_FLAGS)
    for gpu in gpus:
        m = GPU_INFO_PATTERN.match(gpu)
        if m:
            vendor_id = m.groupdict().get("vendor_id")
            vendors.add(vendor_id)
    return vendors


def discover_gpus(vendor_id=None):
    gpu_list = []
    gpus = get_pci_devices(GPU_FLAGS, vendor_id)
    for gpu in gpus:
        m = GPU_INFO_PATTERN.match(gpu)
        if m:
            gpu_dict = m.groupdict()
            # generate hostname for deployable_name usage
            gpu_dict['hostname'] = CONF.host
            # generate traits info
            # TODO(yumeng) support and test VGPU rc generation soon.
            traits = get_traits(gpu_dict["vendor_id"], gpu_dict["product_id"])
            gpu_dict["rc"] = constants.RESOURCES["PGPU"]
            gpu_dict.update(traits)
            gpu_list.append(_generate_driver_device(gpu_dict))
    return gpu_list


def _generate_driver_device(gpu):
    driver_device_obj = driver_device.DriverDevice()
    driver_device_obj.vendor = gpu["vendor_id"]
    driver_device_obj.model = gpu.get('model', 'miss model info')
    std_board_info = {'product_id': gpu.get('product_id', None),
                      'controller': gpu.get('controller', None)}
    vendor_board_info = {'vendor_info': gpu.get('vendor_info', 'gpu_vb_info')}
    driver_device_obj.std_board_info = jsonutils.dumps(std_board_info)
    driver_device_obj.vendor_board_info = jsonutils.dumps(vendor_board_info)
    driver_device_obj.type = constants.DEVICE_GPU
    driver_device_obj.stub = gpu.get('stub', False)
    driver_device_obj.controlpath_id = _generate_controlpath_id(gpu)
    driver_device_obj.deployable_list = _generate_dep_list(gpu)
    return driver_device_obj


def _generate_controlpath_id(gpu):
    driver_cpid = driver_controlpath_id.DriverControlPathID()
    # NOTE: GPUs (either pGPU or vGPU), they all report "PCI" as
    # their cpid_type, while attach_handle_type of them are different.
    driver_cpid.cpid_type = "PCI"
    driver_cpid.cpid_info = utils.pci_str_to_json(gpu["devices"])
    return driver_cpid


def _generate_dep_list(gpu):
    dep_list = []
    driver_dep = driver_deployable.DriverDeployable()
    driver_dep.attribute_list = _generate_attribute_list(gpu)
    driver_dep.attach_handle_list = []
    # NOTE(wangzhh): The name of deployable should be unique, its format is
    # under disscussion, may looks like
    # <ComputeNodeName>_<NumaNodeName>_<CyborgName>_<NumInHost>
    # NOTE(yumeng) Now simply named as <Compute_hostname>_<Device_address>
    # once cyborg needs to support GPU devices discovered from a baremetal
    # node, we might need to support more formats.
    driver_dep.name = gpu.get('hostname', '') + '_' + gpu["devices"]
    driver_dep.driver_name = VENDOR_MAPS.get(gpu["vendor_id"]).upper()
    # driver_dep.num_accelerators for PGPU is 1, for VGPU should be the
    # sriov_numvfs of the vGPU device.
    # TODO(yumeng) support VGPU num report soon
    driver_dep.num_accelerators = 1
    driver_dep.attach_handle_list = \
        [_generate_attach_handle(gpu)]
    dep_list.append(driver_dep)
    return dep_list


def _generate_attach_handle(gpu):
    driver_ah = driver_attach_handle.DriverAttachHandle()
    if gpu["rc"] == "PGPU":
        driver_ah.attach_type = constants.AH_TYPE_PCI
    else:
        driver_ah.attach_type = constants.AH_TYPE_MDEV
    driver_ah.in_use = False
    driver_ah.attach_info = utils.pci_str_to_json(gpu["devices"])
    return driver_ah


def _generate_attribute_list(gpu):
    attr_list = []
    for k, v in gpu.items():
        if k == "rc":
            driver_attr = driver_attribute.DriverAttribute()
            driver_attr.key, driver_attr.value = k, v
            attr_list.append(driver_attr)
        if k == "traits":
            values = gpu.get(k, [])
            for index, val in enumerate(values):
                driver_attr = driver_attribute.DriverAttribute(
                    key="trait" + str(index), value=val)
                attr_list.append(driver_attr)
    return attr_list
