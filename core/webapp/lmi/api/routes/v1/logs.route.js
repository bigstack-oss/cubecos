// api/routes/v1/logs.route.js

const express = require('express');
const validate = require('express-validation');
const controller = require('../../controllers/logs.control');
const { alertSummary, systemAlerts, hostAlerts, instanceAlerts, responses, responseUpdate } = require('../../validations/logs.valid');

const router = express.Router();

/**
 * @api {get} v1/logs/alert-summary Get alert summary as of today
 * @apiDescription Get alert summary as of today
 * @apiVersion 1.0.0
 * @apiName Alerts
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  alert summary information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/alert-summary')
  .get(validate(alertSummary), controller.alertSummary);

/**
 * @api {get} v1/logs/system-alerts Get system alert information
 * @apiDescription Get system alert information
 * @apiVersion 1.0.0
 * @apiName System Alerts
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  system alert information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/system-alerts')
  .get(validate(systemAlerts), controller.systemAlerts);

/**
 * @api {get} v1/logs/host-alerts Get host alert information
 * @apiDescription Get host alert information
 * @apiVersion 1.0.0
 * @apiName Host Alerts
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  host alert information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/host-alerts')
  .get(validate(hostAlerts), controller.hostAlerts);

/**
 * @api {get} v1/logs/instance-alerts Get instance alert information
 * @apiDescription Get instance alert information
 * @apiVersion 1.0.0
 * @apiName Instance Alerts
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  instance alert information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/instance-alerts/:tid?')
  .get(validate(instanceAlerts), controller.instanceAlerts);

/**
 * @api {get} v1/logs/responses/:category Get alert response information
 * @apiDescription Get alert response information
 * @apiVersion 1.0.0
 * @apiName Alert Responses
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  response information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/responses/:category/:tid?')
  .get(validate(responses), controller.responses);

/**
 * @api {put} v1/logs/responses/:category Update alert response information
 * @apiDescription Update alert response information
 * @apiVersion 1.0.0
 * @apiName Alert Responses
 * @apiGroup logs
 * @apiPermission public
 *
 * @apiSuccess  {String}  response information
 *
 * @apiError  (Bad Request 400)  ValidationError  Some parameters may contain invalid values
 */
router.route('/responses/:category/:tid?')
  .put(validate(responseUpdate), controller.responseUpdate)

module.exports = router;
