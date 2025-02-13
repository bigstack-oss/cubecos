// api/validations/logs.valid.js

const Joi = require('joi');

module.exports = {
  // GET /v1/logs/alert-summary
  alertSummary: {
    query: {},
  },
  // GET /v1/logs/system-alerts
  systemAlerts: {
    query: {},
  },
  // GET /v1/logs/host-alerts
  hostAlerts: {
    query: {},
  },
  // GET /v1/logs/instance-alerts/:tid
  instanceAlerts: {
    query: {},
  },
  // GET /v1/logs/responses/:category/:tid
  responses: {
    params: {
      category:
        Joi.string()
          .valid([
            'admin',
            'instance'])
         .required(),
    },
  },
  // PUT /v1/logs/responses/:category/:tid
  responseUpdate: {
    params: {
      category:
        Joi.string()
          .valid([
            'admin',
            'instance'])
         .required(),
    },
    body: {
      action: Joi.string().valid('add', 'update').required(),
      name: Joi.string().required(),
      enabled: Joi.boolean().required(),
      type: Joi.string().valid('email', 'slack').required(),
      topic: Joi.string().valid('events', 'instance-events').required(),
      match: Joi.string().required(),
      url: Joi.string().when('type', { is: 'slack', then: Joi.required() }),
      host: Joi.string().when('type', { is: 'email', then: Joi.required() }),
      port: Joi.number().min(0).max(65535).when('type', { is: 'email', then: Joi.required() }),
      username: Joi.string().when('type', { is: 'email', then: Joi.required() }),
      password: Joi.string().when('type', { is: 'email', then: Joi.required() }),
      from: Joi.string().when('type', { is: 'email', then: Joi.required() }),
      to: Joi.string().when('type', { is: 'email', then: Joi.required() }),
    },
  },
};