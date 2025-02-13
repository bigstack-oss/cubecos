// api/routes/v1/index.js

const express = require('express');
const authRoutes = require('./auth.route');
const statsRoutes = require('./stats.route');
const logsRoutes = require('./logs.route');
const manageRoutes = require('./manage.route');

const router = express.Router();

router.use('/docs', express.static('docs'));
router.use('/auth', authRoutes);
router.use('/stats', statsRoutes);
router.use('/logs', logsRoutes);
router.use('/manage', manageRoutes);

module.exports = router;