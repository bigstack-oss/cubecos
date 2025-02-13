// api/validations/manage.valid.js

const Joi = require('joi');

module.exports = {
  // GET /v1/manage/node-list
  nodeList: {
    query: {},
  },

  // DELETE /v1/manage/nodes/:hostname?
  nodeRemove: {
    query: {},
  },

  // GET /v1/manage/node-list
  licenseStatus: {
    query: {},
  },

  // GET /v1/manage/images
  images: {
    query: {},
  },

  // POST /v1/manage/images
  imageAdd: {
    query: {
      project: Joi.string().required(),
      name: Joi.string().required(),
    },
  },

  // DELETE /v1/manage/images/:id?
  imageRemove: {
    params: {
      id: Joi.string().required(),
    }
  },

  // GET /v1/manage/instances
  instances: {
    query: {},
  },

  // GET /v1/manage/instances/:username?
  userInstances: {
    params: {
      username: Joi.string().required(),
    }
  },

  // POST /v1/manage/exports/:id?
  exportInstance: {
    params: {
      id: Joi.string().required(),
    }
  },

  // GET /v1/manage/getExports
  getExports: {
    query: {},
  },

  // GET /v1/manage/exports/:filename?
  exportDownload: {
    params: {
      filename: Joi.string().required(),
    }
  },
};