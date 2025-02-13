// api/validations/stats.valid.js

const Joi = require('joi');

module.exports = {

  // GET /v1/stats/partition
  partition: {
    query: {},
  },

  // GET /v1/stats/cluster-cpu
  clusterCpu: {
    query: {},
  },

  // GET /v1/stats/cluster-mem
  clusterMem: {
    query: {},
  },

  // GET /v1/stats/storage-bandwidth
  storageBandwidth: {
    query: {},
  },

  // GET /v1/stats/storage-iops
  storageIops: {
    query: {},
  },

  // GET /v1/stats/storage-latency
  storageLatency: {
    query: {},
  },

  // GET /v1/stats/op-summary
  opSummary: {
    query: {},
  },

  // GET /v1/stats/op-summary
  infraSummary: {
    query: {},
  },

  // GET /v1/stats/topten-host-cpu/mem/disk/netin/netout
  toptenHostCpu: {
    query: {},
  },
  toptenHostMem: {
    query: {},
  },
  toptenHostDisk: {
    query: {},
  },
  toptenHostNetin: {
    query: {},
  },
  toptenHostNetout: {
    query: {},
  },

  // GET /v1/stats/topten-vm-cpu/mem/diskr/diskw/netin/netout
  toptenVmCpu: {
    query: {},
  },
  toptenVmMem: {
    query: {},
  },
  toptenVmDiskr: {
    query: {},
  },
  toptenVmDiskw: {
    query: {},
  },
  toptenVmNetin: {
    query: {},
  },
  toptenVmNetout: {
    query: {},
  },

  // GET /v1/stats/health/:comp
  health: {
    params: {
      comp:
        Joi.string()
          .valid([
            'link',
            'clock',
            'dns',
            'etcd',
            'hacluster',
            'rabbitmq',
            'mysql',
            'vip',
            'haproxy_ha',
            'haproxy',
            'httpd',
            'skyline',
            'lmi',
            'memcache',
            'keycloak',
            'ceph',
            'ceph_mon',
            'ceph_mgr',
            'ceph_mds',
            'ceph_osd',
            'ceph_rgw',
            'rbd_target',
            'nova',
            'cyborg',
            'ironic',
            'neutron',
            'glance',
            'cinder',
            'manila',
            'swift',
            'heat',
            'octavia',
            'designate',
            'k3s',
            'rancher',
            'masakari',
            'zookeeper',
            'kafka',
            'monasca',
            'manila',
            'senlin',
            'watcher',
            'telegraf',
            'influxdb',
            'kapacitor',
            'grafana',
            'filebeat',
            'auditbeat',
            'opensearch',
            'logstash',
            'opensearch-dashboards'])
         .required(),
    },
  },
};
