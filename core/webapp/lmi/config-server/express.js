// config-server/express.js

const express = require('express');
const session = require('express-session');
const morgan = require('morgan');
const bodyParser = require('body-parser');
const busboy = require('connect-busboy');
const fs = require('fs-extra');
const compress = require('compression');
const methodOverride = require('method-override');
const cors = require('cors');
const helmet = require('helmet');
const passport = require('passport');

const { logs } = require('./vars');
const strategies = require('./passport');
const routes = require('../api/routes/v1');
const error = require('../api/middlewares/error');

/**
* Passport instance
* @private
*/
passport.serializeUser(function(user, done) {
  done(null, user);
});

passport.deserializeUser(function(obj, done) {
  done(null, obj);
});

passport.use('saml', strategies.saml);

/**
* Express instance
* @public
*/
const app = express();

app.use(busboy({
  highWaterMark: 100 * 1024 * 1024, // Set 100MiB buffer
})); // Insert the busboy middle-ware

fs.ensureDir('/mnt/cephfs/glance'); // Make sure that the upload path exits

// request logging. dev: console | production: file
app.use(morgan(logs));

// parse body params and attache them to req.body
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// gzip compression
app.use(compress());

// lets you use HTTP verbs such as PUT or DELETE
// in places where the client doesn't support it
app.use(methodOverride());

// enable session store
app.use(session({
  secret: 'Cube0s!',
  resave: false,
  saveUninitialized: false,
}));

// secure apps by setting various HTTP headers
app.use(helmet());

// enable CORS - Cross Origin Resource Sharing
app.use(cors());

// enable authentication
app.use(passport.initialize());
app.use(passport.session());

// mount api v1 routes
app.use('/v1', routes);

// if error is not an instanceOf APIError, convert it.
app.use(error.converter);

// catch 404 and forward to error handler
//app.use(error.notFound);

// error handler, send stacktrace only during development
app.use(error.handler);

module.exports = app;