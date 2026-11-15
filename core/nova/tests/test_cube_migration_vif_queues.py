# Unit tests for the cube _update_vif_xml queue fix (#2357): a live-migrated
# interface keeps the source's vhost queue count, not the current flavor's.
#
# Run against a node's epoxy venv (nova already importable):
#   /opt/openstack-epoxy/bin/python -m unittest discover -s . -p 'test_*.py' -v

import unittest

from lxml import etree

from nova.virt.libvirt import config as vconfig
from nova.virt.libvirt import migration

MAC = 'fa:16:3e:00:00:01'
PCI = ("<address type='pci' domain='0x0000' bus='0x00' slot='0x03' "
       "function='0x0'/>")


def _domain(driver_xml):
    return etree.fromstring(
        "<domain><uuid>u</uuid><devices>"
        "<interface type='ethernet'><mac address='%s'/>"
        "<model type='virtio'/>%s<target dev='tap0'/>%s</interface>"
        "</devices></domain>" % (MAC, driver_xml, PCI))


class FakeMigrateVif(object):
    source_vif = {'address': MAC}

    def get_dest_vif(self):
        return {'address': MAC}


class FakeMigrateData(object):
    vifs = [FakeMigrateVif()]


def _vif_config(queues, driver_name='vhost'):
    def get_vif_config(vif):
        conf = vconfig.LibvirtConfigGuestInterface()
        conf.net_type = 'ethernet'
        conf.target_dev = 'tap0'
        conf.mac_addr = MAC
        conf.model = 'virtio'
        conf.driver_name = driver_name
        conf.vhost_queues = queues
        conf.vhost_rx_queue_size = 1024
        return conf
    return get_vif_config


def _driver(xml_doc):
    return xml_doc.find('./devices/interface/driver')


class TestKeepVifQueues(unittest.TestCase):
    def _update(self, src_driver_xml, dest_queues, driver_name='vhost'):
        return migration._update_vif_xml(
            _domain(src_driver_xml), FakeMigrateData(),
            _vif_config(dest_queues, driver_name))

    def test_source_without_queues_drops_dest_queues(self):
        # booted on 1 vCPU, live-resized to 4
        doc = self._update("<driver name='vhost'/>", 4)
        drv = _driver(doc)
        self.assertIsNone(drv.get('queues'))
        self.assertEqual('vhost', drv.get('name'))
        self.assertEqual('1024', drv.get('rx_queue_size'))

    def test_source_queues_override_dest_queues(self):
        # booted on 2 vCPU, live-resized to 4
        doc = self._update("<driver name='vhost' queues='2'/>", 4)
        self.assertEqual('2', _driver(doc).get('queues'))

    def test_unchanged_queues_are_kept(self):
        doc = self._update("<driver name='vhost' queues='2'/>", 2)
        self.assertEqual('2', _driver(doc).get('queues'))

    def test_source_without_driver_drops_dest_driver(self):
        # booted on 1 vCPU (no <driver>), live-resized to 2: libvirt
        # refuses a <driver> the source lacks ("virtio options don't match")
        doc = self._update("", 2)
        self.assertIsNone(_driver(doc))

    def test_source_queues_copied_when_dest_has_no_driver(self):
        def get_vif_config(vif):
            conf = _vif_config(None, driver_name=None)(vif)
            conf.vhost_rx_queue_size = None
            return conf
        doc = migration._update_vif_xml(
            _domain("<driver name='vhost' queues='2'/>"), FakeMigrateData(),
            get_vif_config)
        self.assertEqual('2', _driver(doc).get('queues'))

    def test_guest_pci_address_still_kept(self):
        doc = self._update("<driver name='vhost' queues='2'/>", 4)
        addr = doc.find('./devices/interface/address')
        self.assertEqual('0x03', addr.get('slot'))


if __name__ == '__main__':
    unittest.main()
