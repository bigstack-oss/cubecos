// api/routes/v1/stats.route.js

const express = require('express');
const validate = require('express-validation');
const controller = require('../../controllers/stats.control');
const { partition, clusterCpu, clusterMem,
        storageBandwidth, storageIops, storageLatency, opSummary, infraSummary,
        toptenHostCpu, toptenHostMem, toptenHostDisk, toptenHostNetin, toptenHostNetout,
        toptenVmCpu, toptenVmMem, toptenVmDiskr, toptenVmDiskw, toptenVmNetin, toptenVmNetout, health } = require('../../validations/stats.valid');

const router = express.Router();

/**
 * @api {get} v1/stats/partition Get control node partition information
 * @apiDescription Get control node partition information
 * @apiVersion 1.0.0
 * @apiName PartitionInfo
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  partition  control node partition information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/partition')
  .get(validate(partition), controller.partition);

/**
 * @api {get} v1/stats/cluster-cpu Get cpu usage of the cluster
 * @apiDescription Get cpu usage of the cluster
 * @apiVersion 1.0.0
 * @apiName ClusterCpuUsage
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  cpu usage of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/cluster-cpu')
  .get(validate(clusterCpu), controller.clusterCpu);

/**
 * @api {get} v1/stats/cluster-mem Get memory usage of the cluster
 * @apiDescription Get memory usage of the cluster
 * @apiVersion 1.0.0
 * @apiName ClusterCpuUsage
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  memory usage of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/cluster-mem')
  .get(validate(clusterMem), controller.clusterMem);

/**
 * @api {get} v1/stats/storage-bandwidth Get bandwidth usage of the storage
 * @apiDescription Get bandwidth usage of the storage
 * @apiVersion 1.0.0
 * @apiName StorageBandwidthUsage
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  bandwidth usage of the storage
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/storage-bandwidth')
  .get(validate(storageBandwidth), controller.storageBandwidth);

/**
 * @api {get} v1/stats/storage-iops Get iops usage of the storage
 * @apiDescription Get iops usage of the storage
 * @apiVersion 1.0.0
 * @apiName StorageBandwidthUsage
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  iops usage of the storage
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/storage-iops')
  .get(validate(storageIops), controller.storageIops);

/**
 * @api {get} v1/stats/storage-latency Get latency usage of the storage
 * @apiDescription Get latency usage of the storage
 * @apiVersion 1.0.0
 * @apiName StorageBandwidthUsage
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  latency usage of the storage
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/storage-latency')
  .get(validate(storageLatency), controller.storageLatency);

/**
 * @api {get} v1/stats/op-summary Get operation summary of the cluster
 * @apiDescription Get operation summary of the cluster
 * @apiVersion 1.0.0
 * @apiName OperationSummary
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  summary  operation summary of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/op-summary')
  .get(validate(opSummary), controller.opSummary);

/**
 * @api {get} v1/stats/infra-summary Get infrastructure summary of the cluster
 * @apiDescription Get infrastructure summary of the cluster
 * @apiVersion 1.0.0
 * @apiName InfrastructureSummary
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  summary  infrastructure summary of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/infra-summary')
  .get(validate(infraSummary), controller.infraSummary);

/**
 * @api {get} v1/stats/topten-host Get top 10 used host regards to cpu / memory / disk / netio
 * @apiDescription Get top 10 used host regards to cpu / memory / disk / netio
 * @apiVersion 1.0.0
 * @apiName ToptenHost
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  topten  top 10 used host regards to cpu / memory / disk / netio
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/topten-host-cpu')
  .get(validate(toptenHostCpu), controller.toptenHostCpu);
router.route('/topten-host-mem')
  .get(validate(toptenHostMem), controller.toptenHostMem);
router.route('/topten-host-disk')
  .get(validate(toptenHostDisk), controller.toptenHostDisk);
router.route('/topten-host-netin')
  .get(validate(toptenHostNetin), controller.toptenHostNetin);
router.route('/topten-host-netout')
  .get(validate(toptenHostNetout), controller.toptenHostNetout);

/**
 * @api {get} v1/stats/topten-vm Get top 10 used vm regards to cpu / memory / diskio / netio
 * @apiDescription Get top 10 used vm regards to cpu / memory / diskio / netio
 * @apiVersion 1.0.0
 * @apiName ToptenVM
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  topten  top 10 used vm regards to cpu / memory / diskio / netio
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/topten-vm-cpu')
  .get(validate(toptenVmCpu), controller.toptenVmCpu);
router.route('/topten-vm-mem')
  .get(validate(toptenVmMem), controller.toptenVmMem);
router.route('/topten-vm-diskr')
  .get(validate(toptenVmDiskr), controller.toptenVmDiskr);
router.route('/topten-vm-diskw')
  .get(validate(toptenVmDiskw), controller.toptenVmDiskw);
router.route('/topten-vm-netin')
  .get(validate(toptenVmNetin), controller.toptenVmNetin);
router.route('/topten-vm-netout')
  .get(validate(toptenVmNetout), controller.toptenVmNetout);

/**
 * @api {get} v1/stats/health/:comp Get cube core componments health information
 * @apiDescription Get cube core componments health information
 * @apiVersion 1.0.0
 * @apiName Health
 * @apiGroup Stats
 * @apiPermission public
 *
 * @apiSuccess  {String}  health  cube core componments health information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/health/:comp')
  .get(validate(health), controller.health);

module.exports = router;
