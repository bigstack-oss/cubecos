const SamlStrategy = require('passport-saml').Strategy;
const { samlSpUrl, samlIdpUrl, samlIdpCert } = require('./vars');
const logger = require('./logger');
const fs  = require('fs');

const SamlOptions = {
  issuer: `${samlSpUrl}/v1/auth/metadata`,
  callbackUrl: `${samlSpUrl}/v1/auth/consume`,
  entryPoint: `${samlIdpUrl}/auth/realms/master/protocol/saml`,
  cert: `${samlIdpCert}`,
  privateKey: fs.readFileSync("/var/www/certs/server.key", "utf-8"),
  decryptionPvk: fs.readFileSync("/var/www/certs/server.key", "utf-8"),
  identifierFormat: 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent',
  signatureAlgorithm: 'sha256',
  passReqToCallback: true,
};

const CUBE_ADMIN_GRP = 'cube-admins';
const OPS_DOMAIN_GRP = 'ops-domain';
const OPS_PROJ_GRP = 'ops-project';
const ADMIN_ROLE = 'admin';
const MEMBER_ROLE = '_member_';
const USER_ROLE = 'user';

const SamlVerify = async (req, profile, done) => {
  if (!req.user) {
    logger.info('first time logged in');
    logger.info('saml profile:', profile);

    let domain = 'default';
    let tenantId = '';
    let role = USER_ROLE;

    // determine admin role
    if (profile.username == 'admin')
      role = ADMIN_ROLE;
    else if (profile.groups) {
      if (typeof profile.groups == 'string') {
        if (profile.groups == CUBE_ADMIN_GRP) {
          role = ADMIN_ROLE;
        }
      }
      else {
        for (var i = 0; i < profile.groups.length; i++) {
          if (profile.groups[i] == CUBE_ADMIN_GRP) {
            role = ADMIN_ROLE;
            break;
          }
        }
      }
    }

    // determine openstack domain and tenantId for _member_ role
    if (role == USER_ROLE && profile.groups) {
      if (typeof profile.groups == 'string') {
        const attrs = profile.groups.split(':')
        if (attrs.length >= 2) {
          if (attrs[0] == OPS_DOMAIN_GRP) {
            domain = attrs[1];
          }
          if (attrs[0] == OPS_PROJ_GRP) {
            tenantId = attrs[1];
            role = MEMBER_ROLE;
          }
        }
      }
      else {
        for (var i = 0; i < profile.groups.length; i++) {
          const attrs = profile.groups[i].split(':')
          if (attrs.length >= 2) {
            if (attrs[0] == OPS_DOMAIN_GRP) {
              domain = attrs[1];
            }
            if (attrs[0] == OPS_PROJ_GRP) {
              tenantId = attrs[1];
              role = MEMBER_ROLE;
            }
          }
        }
      }
    }

    const user = {
      domain: domain,
      tenantId: tenantId,
      username: profile.username,
      groups: profile.groups,
      role: role,
    };

    logger.info('user:', user)
    // Set session expiration to 30 mins
    var age = 1800000
    req.session.cookie.expires = new Date(Date.now() + age)
    req.session.cookie.maxAge = age
    done(null, user);
  } else {
    // user already exists
    logger.info('already logged in');

    const user = req.user; // pull the user out of the session
    logger.info('user:', user)
    return done(null, user);
  }
};

exports.saml = new SamlStrategy(SamlOptions, SamlVerify);