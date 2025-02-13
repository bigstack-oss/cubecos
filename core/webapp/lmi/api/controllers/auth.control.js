// api/controllers/auth.control.js

const httpStatus = require('http-status');
const passport = require("passport");
const { HexSdk } = require('../services/hex-cmds');
const strategies = require('../../config-server/passport');
const logger = require('../../config-server/logger');
const fs  = require('fs');

/**
* Returns sp saml metadata
 * @public
 */
exports.metadata = async (req, res, next) => {
  res.type('application/xml');
  res.status(200).send(
    strategies.saml.generateServiceProviderMetadata(
      fs.readFileSync("/var/www/certs/server.cert", "utf-8"),
      fs.readFileSync("/var/www/certs/server.cert", "utf-8")
  ));
};

/**
 * SAML2 SP initiated entry point
 * @public
 */
exports.connect = async (req, res, next) => {
  if (req.user) {
    if (req.user.role == 'admin')
      res.redirect('/dashboard');
    else if (req.user.role == '_member_')
      res.redirect('/logs/alert');
    else
      res.redirect('/dashboard/application');
  }
  else
    res.redirect('/login');
};

/**
 * SAML2 HTTP-POST Binding
 * @public
 */
exports.consume = async (req, res, next) => {
  if (req.user) {
    if (req.user.role == 'admin')
      res.redirect('/dashboard');
    else if (req.user.role == '_member_')
      res.redirect('/logs/alert');
    else
      res.redirect('/dashboard/application');
  }
  else
    res.redirect('/login');
};

/**
 * Returns user profile
 * @public
 */
exports.profile = async (req, res, next) => {
  try {
    return res.status(200).json(req.user);
  } catch (error) {
    return next(error);
  }
};

/**
 * Logout and remove session
 * @public
 */
exports.logout = async (req, res, next) => {
  req.logout();
  req.session.destroy(function (err) {
    if (!err) {
      res
        .status(200)
        .clearCookie('connect.sid', {path: '/'})
        .json({status: "success"});
    }
  });
};

/**
 * Returns keystone domain list
 * @public
 */
exports.listDomains = async (req, res, next) => {
  try {
    const info = await new HexSdk().run('os_list_domain');
    const domains = info.split(',');
    return res.json(domains);
  } catch (error) {
    return next(error);
  }
};

/**
 * Returns keystone project list under a given domain
 * @public
 */
exports.listTenants = async (req, res, next) => {
  try {
    const info = await new HexSdk().run(`os_list_project_by_domain ${req.query.domain}`);
    const tenants = info.split(',');
    return res.json(tenants);
  } catch (error) {
    return next(error);
  }
};