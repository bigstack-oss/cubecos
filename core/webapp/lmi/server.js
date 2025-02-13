// server.js

// make bluebird default Promise
Promise = require('bluebird');

const next = require('next');
const LRUCache = require('lru-cache');

const { port, env } = require('./config-server/vars');
const logger = require('./config-server/logger');
const server = require('./config-server/express');

const dev = process.env.NODE_ENV !== 'production';
const dir = process.env.NODE_ENV == 'production' ? '/var/www/lmi' : process.cwd();
const app = next({ dev, dir: process.cwd() });
const handle = app.getRequestHandler();

const ssrCache = new LRUCache({
  max: 100,
  maxAge: 1000 * 60 * 60,
});

app.prepare().then(() => {

  //server.get('/dashboard', (req, res) => {
  //  renderAndCache(req, res, '/dashboard');
  //});

  server.get('*', (req, res) => {
    return handle(req, res);
  });

  server.listen(port, () =>
    logger.info(`server started on port ${port} (${env})`)
  );
});

/*
 * make sure to modify this to take into account anything that should trigger
 * an immediate page change (e.g a locale stored in req.session)
 */
function getCacheKey(req) {
  return `${req.url}`;
}

function renderAndCache(req, res, pagePath, queryParams) {
  const key = getCacheKey(req);

  // If we have a page in the cache, let's serve it
  if (ssrCache.has(key)) {
    logger.info(`CACHE HIT: ${key}`);
    res.send(ssrCache.get(key));
    return;
  }

  // If not let's render the page into HTML
  app
    .renderToHTML(req, res, pagePath, queryParams)
    .then(html => {
      // Let's cache this page
      logger.info(`CACHE MISS: ${key}`);
      ssrCache.set(key, html);

      res.send(html);
    })
    .catch(err => {
      app.renderError(err, req, res, pagePath, queryParams);
    });
}
