# Modifications Copyright (C) 2021 ZTE Corporation
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
Cyborg NVIDIA GPU driver implementation.
"""
from oslo_log import log as logging
from oslo_serialization import jsonutils

import collections
import os

import cyborg.conf

from cyborg.accelerator.common import utils
from cyborg.accelerator.drivers.gpu import utils as gpu_utils
from cyborg.common import constants
from cyborg.common import exception
from cyborg.conf import CONF
from cyborg.objects.driver_objects import driver_attach_handle
from cyborg.objects.driver_objects import driver_attribute
from cyborg.objects.driver_objects import driver_controlpath_id
from cyborg.objects.driver_objects import driver_deployable
from cyborg.objects.driver_objects import driver_device

LOG = logging.getLogger(__name__)


def _get_traits(vendor_id, product_id, vgpu_type_name=None):
    """Generate traits for GPUs.
    : param vendor_id: vendor_id of PGPU/VGPU, eg."10de"
    : param product_id: product_id of PGPU/VGPU, eg."1eb8".
    : param vgpu_type_name: vgpu type name, eg."T4_1B".
    Example VGPU traits:
    {traits:["OWNER_CYBORG", "CUSTOM_NVIDIA_1EB8_T4_2B"]}
    Example PGPU traits:
    {traits:["OWNER_CYBORG", "CUSTOM_NVIDIA_1EB8"]}
    """
    traits = ["OWNER_CYBORG"]
    # PGPU trait
    gpu_trait = "_".join(
        ('CUSTOM', gpu_utils.VENDOR_MAPS.get(vendor_id, "").upper(),
         product_id.upper()))
    # VGPU trait
    if vgpu_type_name:
        gpu_trait = "_".join((gpu_trait, vgpu_type_name.upper()))
    traits.append(gpu_trait)
    return {"traits": traits}


def _generate_attribute_list(gpu):
    attr_list = []
    index = 0
    for k, v in gpu.items():
        if k == "rc":
            driver_attr = driver_attribute.DriverAttribute()
            driver_attr.key, driver_attr.value = k, v
            attr_list.append(driver_attr)
        if k == "traits":
            values = gpu.get(k, [])
            for val in values:
                driver_attr = driver_attribute.DriverAttribute(
                    key="trait" + str(index), value=val)
                index = index + 1
                attr_list.append(driver_attr)
    return attr_list


def _generate_attach_handle(gpu, num=None):
    driver_ah = driver_attach_handle.DriverAttachHandle()
    driver_ah.in_use = False
    if gpu["rc"] == "PGPU":
        driver_ah.attach_type = constants.AH_TYPE_PCI
        driver_ah.attach_info = utils.pci_str_to_json(gpu["devices"])
    else:
        vgpu_mark = gpu["vGPU_type"] + '_' + str(num)
        driver_ah.attach_type = constants.AH_TYPE_MDEV
        driver_ah.attach_info = utils.mdev_str_to_json(
            gpu["devices"], gpu["vGPU_type"], vgpu_mark)
    return driver_ah


def _generate_dep_list(gpu):
    driver_dep = driver_deployable.DriverDeployable()
    driver_dep.attribute_list = _generate_attribute_list(gpu)
    driver_dep.attach_handle_list = []
    # NOTE(wangzhh): The name of deployable should be unique, its format is
    # under disscussion, may looks like
    # <ComputeNodeName>_<NumaNodeName>_<CyborgName>_<NumInHost>
    # NOTE(yumeng) Since Wallaby release, the deplpyable_name is named as
    # <Compute_hostname>_<Device_address>
    driver_dep.name = gpu.get('hostname', '') + '_' + gpu["devices"]
    driver_dep.driver_name = \
        gpu_utils.VENDOR_MAPS.get(gpu["vendor_id"], '').upper()
    # if is pGPU, num_accelerators = 1
    if gpu["rc"] == "PGPU":
        driver_dep.num_accelerators = 1
        driver_dep.attach_handle_list = \
            [_generate_attach_handle(gpu)]
    else:
        # if is vGPU, num_accelerators is the total vGPU capability of
        # the asked vGPU type
        vGPU_path = os.path.expandvars(
            '/sys/bus/pci/devices/{0}/mdev_supported_types/{1}/'
            .format(gpu["devices"], gpu["vGPU_type"]))
        num_available = 0
        with open(vGPU_path + 'available_instances', 'r') as f:
            num_available = int(f.read().strip())
        num_created = len(os.listdir(vGPU_path + 'devices'))
        driver_dep.num_accelerators = num_available + num_created
        # example: 1 pGPU has 16 vGPUs is represented as
        # 16 attach_handles, 1 deployable, 1 resource_provider
        # NOTE(yumeng): cyborg use attach_handle_uuid
        # to create each vGPU without the need to generate a new uuid
        # example: echo "attach_handle_uuid" > nvidia-223/create
        for num in range(driver_dep.num_accelerators):
            driver_dep.attach_handle_list.append(
                _generate_attach_handle(gpu, num))
    return [driver_dep]


def _generate_controlpath_id(gpu):
    driver_cpid = driver_controlpath_id.DriverControlPathID()
    driver_cpid.cpid_type = "PCI"
    driver_cpid.cpid_info = utils.pci_str_to_json(gpu["devices"])
    return driver_cpid


def _generate_driver_device(gpu):
    driver_device_obj = driver_device.DriverDevice()
    driver_device_obj.vendor = gpu['vendor_id']
    driver_device_obj.model = gpu.get('model', 'miss model info')
    std_board_info = {'product_id': gpu.get('product_id'),
                      'controller': gpu.get('controller'), }
    vendor_board_info = {'vendor_info': gpu.get('vendor_info',
                         'gpu_vb_info')}
    driver_device_obj.std_board_info = jsonutils.dumps(std_board_info)
    driver_device_obj.vendor_board_info = jsonutils.dumps(
        vendor_board_info)
    driver_device_obj.type = constants.DEVICE_GPU
    driver_device_obj.stub = gpu.get('stub', False)
    driver_device_obj.controlpath_id = _generate_controlpath_id(gpu)
    driver_device_obj.deployable_list = _generate_dep_list(gpu)
    return driver_device_obj


def _get_supported_vgpu_types():
    """Gets supported vgpu_types from cyborg.conf.

    Retrieves supported vgpu_types set by the operator and generates a
    record of vgpu_type and pgpu in the dict constant: pgpu_type_mapping.

    Returns:
        A list of all vgpu_types set in CONF.gpu_devices.enabled_vgpu_types.

    Raises:
        InvalidGPUConfig: An error occurred if same PCI appear twice
        or PCI address is not valid.
    """
    pgpu_type_mapping = collections.defaultdict(str)
    pgpu_type_mapping.clear()
    if not CONF.gpu_devices.enabled_vgpu_types:
        return [], pgpu_type_mapping

    for vgpu_type in CONF.gpu_devices.enabled_vgpu_types:
        group = getattr(CONF, 'vgpu_%s' % vgpu_type, None)
        if group is None or not group.device_addresses:
            # Device addresses must be configured explictly now for every
            # enabled vgpu type. Will improve after the disable and enable
            # devices interfaces implemented.
            raise exception.InvalidvGPUConfig(
                reason="Missing device addresses config for vgpu type %s"
                % vgpu_type
            )
        for device_address in group.device_addresses:
            if device_address in pgpu_type_mapping:
                raise exception.InvalidvGPUConfig(
                    reason="Duplicate types for PCI address %s"
                    % device_address
                )
            # Just checking whether the operator fat-fingered the address.
            # If it's wrong, it will return an exception
            try:
                # Validates whether it's a PCI ID...
                utils.parse_address(device_address)
            except exception.PciDeviceWrongAddressFormat:
                raise exception.InvalidvGPUConfig(
                    reason="Incorrect PCI address: %s" % device_address
                )
            pgpu_type_mapping[device_address] = vgpu_type
    return CONF.gpu_devices.enabled_vgpu_types, pgpu_type_mapping


def _get_vgpu_type_per_pgpu(device_address, supported_vgpu_types,
                            pgpu_type_mapping):
    """Provides the vGPU type the pGPU supports.

    :param device_address: the PCI device address in config,
                           eg.'0000:af:00.0'
    """
    supported_vgpu_types, pgpu_type_mapping = _get_supported_vgpu_types()
    # Bail out quickly if we don't support vGPUs
    if not supported_vgpu_types:
        LOG.warning('Unable to load vGPU_type from [gpu_devices] '
                    'Ensure "enabled_vgpu_types" is set if the gpu'
                    'is virtualized.')
        return

    try:
        # Validates whether it's a PCI ID...
        utils.parse_address(device_address)
    except (exception.PciDeviceWrongAddressFormat, IndexError):
        # this is not a valid PCI address
        LOG.warning("The PCI address %s was invalid for getting the"
                    "related vGPU type", device_address)
        return
    return pgpu_type_mapping.get(device_address)


def _discover_gpus(vendor_id):
    """param: vendor_id=VENDOR_ID means only discover Nvidia GPU on the host
    """
    # init vGPU conf
    cyborg.conf.devices.register_dynamic_opts(CONF)
    supported_vgpu_types, pgpu_type_mapping = _get_supported_vgpu_types()
    # discover gpu devices by "lspci"
    gpu_list = []
    gpus = gpu_utils.get_pci_devices(gpu_utils.GPU_FLAGS, vendor_id)
    # report trait,rc and generate driver object
    for gpu in gpus:
        m = gpu_utils.GPU_INFO_PATTERN.match(gpu)
        if m:
            gpu_dict = m.groupdict()
            # get hostname for deployable_name usage
            gpu_dict['hostname'] = CONF.host
            # get vgpu_type from cyborg.conf, otherwise vgpu_type=None
            vgpu_type = _get_vgpu_type_per_pgpu(
                gpu_dict["devices"], supported_vgpu_types, pgpu_type_mapping)
            # generate rc and trait for pGPU
            if not vgpu_type:
                gpu_dict["rc"] = constants.RESOURCES["PGPU"]
                traits = _get_traits(gpu_dict["vendor_id"],
                                     gpu_dict["product_id"])
            # generate rc and trait for vGPU
            else:
                # get rc
                gpu_dict["rc"] = constants.RESOURCES["VGPU"]
                mdev_path = os.path.expandvars(
                    '/sys/bus/pci/devices/{0}/mdev_supported_types'.
                    format(gpu_dict["devices"]))
                valid_types = os.listdir(mdev_path)
                if vgpu_type not in valid_types:
                    raise exception.InvalidVGPUType(name=vgpu_type)
                gpu_dict["vGPU_type"] = vgpu_type
                vGPU_path = os.path.expandvars(
                    '/sys/bus/pci/devices/{0}/mdev_supported_types/{1}/'
                    .format(gpu_dict["devices"], gpu_dict["vGPU_type"]))
                # transfer vgpu_type to vgpu_type_name.
                # eg. transfer 'nvidia-223' to 'T4_1B'
                with open(vGPU_path + 'name', 'r') as f:
                    name = f.read().strip()
                vgpu_type_name = name.split(' ')[1].replace('-', '_')
                traits = _get_traits(gpu_dict["vendor_id"],
                                     gpu_dict["product_id"],
                                     vgpu_type_name)
            gpu_dict.update(traits)
            gpu_list.append(_generate_driver_device(gpu_dict))
    return gpu_list


def discover(vendor_id):
    devs = _discover_gpus(vendor_id)
    return devs
