// config-server/vars.js

const path = require('path');

// import .env variables
require('dotenv-safe').load({
  path: path.join(__dirname, '../.env'),
  sample: path.join(__dirname, '../.env.example'),
});

module.exports = {
  env: process.env.NODE_ENV,
  port: process.env.PORT,
  vip: process.env.VIP,
  samlSpUrl: process.env.SAML_SP_URL,
  samlIdpUrl: process.env.SAML_IDP_URL,
  samlIdpCert: process.env.SAML_IDP_CERT,
  logs: process.env.NODE_ENV === 'production' ? 'combined' : 'dev',
  remote: process.env.REMOTE_CUBE === undefined ? '' : process.env.REMOTE_CUBE
};