'use strict';

const https = require('https');
const config = require('./configs/config');
const defaultRules = require('./configs/redirectRules.json');

// Global variable for caching
let cachedRules = null;
let lastFetchTime = 0;

function handler(event, _context, callback) {
  console.log('event: ' + JSON.stringify(event));
  try {
    const request = event.Records[0].cf.request;
    const { headers, clientIp } = request;

    const commonHeaders = {
      'content-type': [
        {
          key: 'Content-Type',
          value: 'text/html',
        },
      ],
    };

    // Return 403 Forbidden if the client IP is not in the allowed list
    const allowedIPs = config.allowedIPs || [];
    // console.log("Allowed IPs:", allowedIPs);
    // console.log("Client IP:", clientIp);
    if (allowedIPs.length > 0) {
      if (!allowedIPs.includes(clientIp)) {
        const response = {
          status: '418', // Return 418 because 403 is used for error handling for SPA entry point
          statusDescription: 'Forbidden',
          headers: commonHeaders,
          body: '<html><body><h1>403 Forbidden</h1><p>Access denied.</p></body></html>',
        };
        return callback(null, response);
      }
    }

    // For Basic Authentication
    if (config.basicAuth != null) {
      const authRequiredPaths = config.basicAuth.requiredPaths || [];
      if (authRequiredPaths.some((prefix) => request.uri.startsWith(prefix))) {
        const { id, password } = config.basicAuth.account;
        const expected =
          'Basic ' + Buffer.from(`${id}:${password}`).toString('base64');
        const auth = headers.authorization?.[0]?.value;
        if (auth !== expected) {
          const response = {
            status: '401',
            statusDescription: 'Unauthorized',
            headers: {
              'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Basic' }],
              ...commonHeaders,
            },
            body: '<html><body><h1>401 Unauthorized</h1><p>Authentication required.</p></body></html>',
          };
          return callback(null, response);
        }
      }
    }

    const rd = config.redirect || {};
    // Forward the request immediately if the redirect is not enabled
    if (!rd.isEnabled) {
      return processRequest(request, [], callback);
    }
    // If the rulesUrl is not set, use the default rules
    if (!rd.rulesUrl) {
      return processRequest(request, defaultRules, callback);
    }

    // Return cached rules if the cache TTL is set and not expired
    const now = Date.now();
    const ttl = rd.cacheTtl;
    if (ttl && cachedRules && now - lastFetchTime < ttl) {
      return processRequest(request, cachedRules, callback);
    }

    // フォールバック用としてローカルルールを保持
    let rulesToUse = defaultRules;

    https
      .get(rd.rulesUrl, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            const key = rd.jsonKey;
            const remote = key ? parsed[key] : parsed;
            if (Array.isArray(remote)) {
              rulesToUse = remote;
              // Cache the rules if TTL is set
              if (ttl) {
                cachedRules = remote;
                lastFetchTime = now;
              }
            }
          } catch (e) {
            console.error('Redirect JSON parse error:', e);
          }
          processRequest(request, rulesToUse, callback);
        });
      })
      .on('error', (e) => {
        console.error('Redirect fetch error:', e);
        processRequest(request, rulesToUse, callback);
      });
  } catch (error) {
    console.error('Lambda@Edge Error:', error);
    const response = {
      status: '500',
      statusDescription: 'Internal Server Error',
      headers: commonHeaders,
      body: '<html><body><h1>500 Internal Server Error</h1><p>There was an error processing your request.</p></body></html>',
    };
    callback(null, response);
  }
}

function processRequest(request, redirectRules, callback) {
  const { headers, uri, querystring: qs } = request;
  const origin = 'https://' + headers.host[0].value;
  const raw = uri.replace(/^\/+|\/$/g, '');

  if (redirectRules) {
    const rule = redirectRules.find((r) => {
      const key = r.condition.key;
      if (key.type === 'exactMatch') return raw === key.value;
      if (key.type === 'prefixMatch') return raw.startsWith(key.value);
      if (key.type === 'regexp') return new RegExp(key.value, 'g').test(raw);
    });
    if (rule) {
      let loc = buildRedirectUri(rule, raw, origin);
      if (qs) loc += (loc.includes('?') ? '&' : '?') + qs;
      return callback(null, {
        status: rule.redirect.statusCode,
        headers: { location: [{ key: 'Location', value: loc }] },
      });
    }
  }

  // Redirect to add trailing slash
  const lastSegment = raw.split('/').pop() || '';
  if (!uri.endsWith('/') && !lastSegment.includes('.')) {
    let loc = origin + '/' + raw + '/';
    if (qs) loc += (loc.includes('?') ? '&' : '?') + qs;
    return callback(null, {
      status: '302',
      headers: { location: [{ key: 'Location', value: loc }] },
    });
  }

  // Fallback to index.html
  request.uri = uri.endsWith('/') ? uri + 'index.html' : uri;
  return callback(null, request);
}

function buildRedirectUri(rule, checkUri, origin) {
  let baseUri = '';
  const ruleUri = rule.redirect.uri;
  const isRegexp = rule.condition.key.type === 'regexp';

  if (isRegexp) {
    const regexp = new RegExp(rule.condition.key.value);
    if (typeof ruleUri === 'string') {
      baseUri = checkUri.replace(regexp, ruleUri);
    } else if (typeof ruleUri === 'object') {
      baseUri = checkUri.replace(regexp, ruleUri.path);
    }
  } else {
    if (typeof ruleUri === 'string') {
      baseUri = ruleUri;
    } else if (typeof ruleUri === 'object') {
      const ruleOrigin = ruleUri.origin ? ruleUri.origin : origin;
      baseUri = ruleOrigin + ruleUri.path;
    }
  }
  if (typeof ruleUri === 'object' && ruleUri.querystring) {
    baseUri += (baseUri.includes('?') ? '&' : '?') + ruleUri.querystring;
  }
  return baseUri;
}

module.exports = {
  handler,
  processRequest,
  buildRedirectUri,
};
