// api/middlewares/auth.js

const passport = require('passport');

exports.authorize = (req, res, next) => {
  if (req.isAuthenticated())
    return next();
  else
    res.redirect('/login')
};

exports.authenticate = passport.authenticate('saml', { failureRedirect: '/login' });