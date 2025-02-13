// api/validations/auth.valid.js

const Joi = require('joi');

module.exports = {
  // GET /v1/auth/tenants
  listTenants: {
    query: {
      domain: Joi.string().required(),
    },
  },
};