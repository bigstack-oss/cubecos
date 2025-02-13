// api/routes/v1/manage.route.js

const express = require('express');
const validate = require('express-validation');
const controller = require('../../controllers/manage.control');
const { nodeList, nodeRemove, licenseStatus, images, imageAdd, imageRemove, instances, userInstances, exportInstance, getExports, exportDownload } = require('../../validations/manage.valid');

const router = express.Router();

/**
 * @api {get} v1/manage/node-list List nodes of the cluster
 * @apiDescription List nodes of the cluster
 * @apiVersion 1.0.0
 * @apiName NodeList
 * @apiGroup Manage
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  nodes of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/node-list')
  .get(validate(nodeList), controller.nodeList);

/*
 * @api {DELETE} v1/manage/nodes Remove a node from the cluster
 * @apiDescription Remove a node from the cluster
 * @apiVersion 1.0.0
 * @apiName NodeRemove
 * @apiGroup Manage
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  nodes of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/nodes/:hostname?')
  .delete(validate(nodeRemove), controller.nodeRemove);

/**
 * @api {get} v1/manage/license-status List license status of the cluster
 * @apiDescription List license status of the cluster
 * @apiVersion 1.0.0
 * @apiName LicenseStatus
 * @apiGroup Manage
 * @apiPermission public
 *
 * @apiSuccess  {String}  usage  nodes of the cluster
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/license-status')
  .get(validate(licenseStatus), controller.licenseStatus);

router.route('/images')
  .get(validate(images), controller.images);

router.route('/images')
  .post(validate(imageAdd), controller.imageAdd);

router.route('/images/:id?')
  .delete(validate(imageRemove), controller.imageRemove);

router.route('/instances')
  .get(validate(instances), controller.instances);

router.route('/instances/:username?')
  .get(validate(userInstances), controller.userInstances);

router.route('/exports/:id?')
  .post(validate(exportInstance), controller.exportInstance);

router.route('/exports')
  .get(validate(getExports), controller.getExports);

router.route('/exports/:filename?')
  .get(validate(exportDownload), controller.exportDownload);

module.exports = router;
