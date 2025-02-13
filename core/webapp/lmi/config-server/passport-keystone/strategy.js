/**
 * Module dependencies.
 */
var passport = require('passport-strategy'),
util = require('util'),
Identity = require('pkgcloud/lib/pkgcloud/openstack/identity');

/**
 * `Strategy` constructor.
 *
 * The Keystone authentication strategy authenticates requests against an Identity endpoint
 * based on the credentials submitted through a POST request
 *
 * Applications must supply a `verify` callback which accepts the identity object, and then calls the `done` callback supplying a
 * `user`, which should be set to `false` if the credentials are not valid.
 * If an exception occured, `err` should be set.
 *
 * Optionally, `options` can be used to change the fields in which the
 * credentials are found.
 *
 * Options:
 *   - `usernameField`  field name where the username is found, defaults to _username_
 *   - `passwordField`  field name where the password is found, defaults to _password_
 *   - 'domainNameField' field name where the domainName is found, defaults to _domainName_
 *   - 'region'         sets region
 *   - 'authUrl'        sets auth url
 *   - `passReqToCallback`  when `true`, `req` is the first argument to the verify callback (default: `false`)
 *
 * Examples:
 *
 *     passport.use(new KeystoneStrategy({
 *           region: "ord",
 *           authUrl: "https://yoursite.com",
 *           passReqToCallback: true
 *       },
 *       function(req, identity, done) {
 *         User.findOne({ id: identity.user.name }, function (err, user) {
 *           done(err, user);
 *         });
 *       }
 *     ));
 *
 * @param {Object} options
 * @param {Function} verify
 * @api public
 */
function Strategy(options, verify) {
  if (typeof options == 'function') {
    verify = options;
    options = {};
  }

  if (!verify) { throw new TypeError('KeystoneStrategy requires a verify callback'); }

  this._usernameField = options.usernameField || 'username';
  this._passwordField = options.passwordField || 'password';
  this._domainNameField = options.domainNameField || 'domain';
  this._tenantNameField = options.tenantNameField || 'tenant';
  this._region = options.region || '';
  this._authUrl = options.authUrl || '';
  this._tenantId = options.tenantId || '';

  passport.Strategy.call(this);
  this.name = 'keystone';
  this._verify = verify;
  this._passReqToCallback = options.passReqToCallback;
}

/**
 * Inherit from `passport.Strategy`.
 */
util.inherits(Strategy, passport.Strategy);

/**
 * Get value for given field from given object. Taken from passport-local,
 * copyright 2011-2013 Jared Hanson
 */
var lookup = function (obj, field) {
  var i, len, chain, prop;
  if (!obj) { return null; }
  chain = field.split(']').join('').split('[');
  for (i = 0, len = chain.length; i < len; i++) {
    prop = obj[chain[i]];
    if (typeof(prop) === 'undefined') { return null; }
    if (typeof(prop) !== 'object') { return prop; }
    obj = prop;
  }
  return null;
};


/**
 * Authenticate request based on the contents of a form submission.
 *
 * @param {Object} req
 * @api protected
 */
Strategy.prototype.authenticate = function(req, options) {
  var config = {};
  options = options || {};
  config.username = lookup(req.body, this._usernameField) || lookup(req.query, this._usernameField);
  config.password = lookup(req.body, this._passwordField) || lookup(req.query, this._passwordField);
  config.domainName = lookup(req.body, this._domainNameField) || lookup(req.query, this._domainNameField);
  config.tenantName = lookup(req.body, this._tenantNameField) || lookup(req.query, this._tenantNameField);
  config.authUrl = this._authUrl;
  config.region = this._region;
  config.tenantId = this._tenantId;

  config.projectDomainName = config.domainName;

  if (config.domainName) {
    config.keystoneAuthVersion = 'v3';
  }

  if (!config.username || !config.password) {
    return this.fail({ message: options.badRequestMessage || 'Missing credentials' }, 400);
  }
  var self = this;

  if (!config.authUrl) {
    return this.fail({ message: options.badRequestMessage || 'Missing Identity Endpoint' }, 400);
  }

  var verified = function(self) {
    // Callback given to user given verify function.
    return function(err, user, info) {
      if (err)   return self.error(err);
      if (!user) return self.fail(info);
      return self.success(user, info);
    };
  };

  var client = Identity.createClient(config);

  client.auth(function(err) {
    try {
      if (!client._identity.token.id) {
        if (err)
          return self.fail(err);
        else
          return self.fail('Auth token not generated');
      }
      else {
        if (self._verify) {
          if (self._passReqToCallback) {
            return self._verify(req, client._identity, verified(self));
          } else {
            return self._verify(client._identity, verified(self));
          }
        } else {
          return self.success(client._identity);
        }
      }
    } catch (ex) {
      return self.error(ex);
    }
  });


};


/**
 * Expose `Strategy`.
 */
module.exports = Strategy;
