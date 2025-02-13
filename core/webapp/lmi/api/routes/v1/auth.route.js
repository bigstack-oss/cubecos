// api/routes/v1/auth.route.js

const express = require('express');
const validate = require('express-validation');
const controller = require('../../controllers/auth.control');
const { listTenants } = require('../../validations/auth.valid');
const { authenticate } = require('../../middlewares/auth');

const router = express.Router();

router.route('/metadata')
  .get(controller.metadata)

router.route('/connect')
  .get(authenticate, controller.connect)

router.route('/consume')
  .post(authenticate, controller.consume)

router.route('/profile')
  .get(controller.profile)

router.route('/logout')
  .get(controller.logout)

router.route('/domains')
  .get(controller.listDomains)

router.route('/tenants')
  .get(validate(listTenants), controller.listTenants)

module.exports = router;
