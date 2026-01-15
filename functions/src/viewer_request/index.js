'use strict';

const https = require('https');
const config = require('./configs/config');
const defaultRules = require('./configs/redirectRules.json');

// Global variable for caching
let cachedRules = null;
let lastFetchTime = 0;

/**
 * For Node.js 24+:
 * Return request/response instead of using callback
 */
async function handler(event) {
  console.log('event: ' + JSON.stringify(event));

  const commonHeaders = {
    'content-type': [
      {
        key: 'Content-Type',
        value: 'text/html',
      },
    ],
  };

  try {
    const request = event.Records[0].cf.request;
    const { headers, clientIp } = request;

    // Return 403 Forbidden if the client IP is not in the allowed list
    const allowedIPs = config.allowedIPs || [];
    if (allowedIPs.length > 0) {
      if (!allowedIPs.includes(clientIp)) {
        return {
          status: '418', // Return 418 because 403 is used for error handling for SPA entry point
          statusDescription: 'Forbidden',
          headers: commonHeaders,
          body: '<html><body><h1>403 Forbidden</h1><p>Access denied.</p></body></html>',
        };
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
          return {
            status: '401',
            statusDescription: 'Unauthorized',
            headers: {
              'www-authenticate': [{ key: 'WWW-Authenticate', value: 'Basic' }],
              ...commonHeaders,
            },
            body: '<html><body><h1>401 Unauthorized</h1><p>Authentication required.</p></body></html>',
          };
        }
      }
    }

    const rd = config.redirect || {};

    // Forward the request immediately if the redirect is not enabled
    if (!rd.isEnabled) {
      return processRequest(request, [], null);
    }

    // If the rulesUrl is not set, use the default rules
    if (!rd.rulesUrl) {
      return processRequest(request, defaultRules, null);
    }

    const now = Date.now();
    const ttl = rd.cacheTtl;

    // Return cached rules if TTL is set and not expired
    if (ttl && cachedRules && now - lastFetchTime < ttl) {
      return processRequest(request, cachedRules, null);
    }

    // Keep a fallback to local rules
    let rulesToUse = defaultRules;

    // Get remote rules (Promise-ified and awaited)
    try {
      const remote = await fetchRedirectRules({
        rulesUrl: rd.rulesUrl,
        jsonKey: rd.jsonKey,
      });

      if (Array.isArray(remote)) {
        rulesToUse = remote;

        // Cache the rules if TTL is set
        if (ttl) {
          cachedRules = remote;
          lastFetchTime = now;
        }
      }
    } catch (e) {
      console.error('Redirect fetch error:', e);
    }

    return processRequest(request, rulesToUse, null);
  } catch (error) {
    console.error('Lambda@Edge Error:', error);
    return {
      status: '500',
      statusDescription: 'Internal Server Error',
      headers: commonHeaders,
      body: '<html><body><h1>500 Internal Server Error</h1><p>There was an error processing your request.</p></body></html>',
    };
  }
}

/**
 * Retrieve redirect rules from a remote JSON file
 * - returns a Promise that resolves to the parsed JSON data
 */
function fetchRedirectRules({ rulesUrl, jsonKey }) {
  return new Promise((resolve, reject) => {
    https
      .get(rulesUrl, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            const remote = jsonKey ? parsed?.[jsonKey] : parsed;
            resolve(remote);
          } catch (e) {
            console.error('Redirect JSON parse error:', e);
            reject(e);
          }
        });
      })
      .on('error', (e) => {
        reject(e);
      });
  });
}

/**
 * Process the incoming request and apply redirect rules
 * - returns modified request or redirect response
 */
function processRequest(request, redirectRules) {
  const { headers, uri, querystring: qs } = request;
  const origin = 'https://' + headers.host[0].value;
  const raw = uri.replace(/^\/+|\/$/g, '');

  if (redirectRules) {
    const rule = redirectRules.find((r) => {
      const key = r.condition.key;
      if (key.type === 'exactMatch') return raw === key.value;
      if (key.type === 'prefixMatch') return raw.startsWith(key.value);
      if (key.type === 'regexp') return new RegExp(key.value, 'g').test(raw);
      return false;
    });

    if (rule) {
      let loc = buildRedirectUri(rule, raw, origin);
      if (qs) loc += (loc.includes('?') ? '&' : '?') + qs;

      return {
        status: rule.redirect.statusCode,
        headers: { location: [{ key: 'Location', value: loc }] },
      };
    }
  }

  // Redirect to add trailing slash
  const lastSegment = raw.split('/').pop() || '';
  if (!uri.endsWith('/') && !lastSegment.includes('.')) {
    let loc = origin + '/' + raw + '/';
    if (qs) loc += (loc.includes('?') ? '&' : '?') + qs;

    return {
      status: '302',
      headers: { location: [{ key: 'Location', value: loc }] },
    };
  }

  // Fallback to index.html
  request.uri = uri.endsWith('/') ? uri + 'index.html' : uri;
  return request;
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

