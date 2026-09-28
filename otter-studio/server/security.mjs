// security.mjs - Who may talk to the Studio server.
//
// Studio's API can read and write files in the workspace, run programs and
// open a terminal. It must only ever answer Studio itself, running in a
// browser window on this machine. Three rules enforce that:
//
// 1. Loopback only. The server listens on 127.0.0.1, so other machines on
//    the network cannot connect at all. (It used to listen on every
//    interface.)
//
// 2. The Host header must name this server (localhost / 127.0.0.1 / [::1]
//    with our port). This stops DNS rebinding: a web page on evil.example
//    whose DNS is switched to 127.0.0.1 counts as "same origin" to the
//    browser, but its requests still say `Host: evil.example:4200`.
//
// 3. If a request carries an Origin header (browsers add it to cross-site
//    requests and to every POST), it must be this server's own origin. So a
//    web page you visit cannot make Studio run code or overwrite files.
//    Studio used to reply `Access-Control-Allow-Origin: *`, which let any
//    web page call the API and read the answers; that header is gone.
//
// Requests without an Origin header (Studio's own page loading a GET, the
// test suites, command-line tools on this machine) are allowed: a browser
// cannot send a cross-site POST without Origin, and without CORS headers a
// cross-site page cannot read a GET response.

export const LOOPBACK_HOST = '127.0.0.1';
export const MAX_BODY_BYTES = 32 * 1024 * 1024;

const LOCAL_NAMES = new Set(['localhost', '127.0.0.1', '[::1]']);

function parseHost(value) {
  // "localhost:4200" -> { name: 'localhost', port: '4200' }; IPv6 "[::1]:4200".
  const match = /^(\[[^\]]+\]|[^:]+)(?::(\d+))?$/.exec(String(value || '').trim().toLowerCase());
  return match ? { name: match[1], port: match[2] || '80' } : null;
}

/**
 * Decide whether to serve a request. Returns null when allowed, otherwise
 * { status, error } to send back.
 */
export function checkRequest(headers, port) {
  const host = parseHost(headers.host);
  if (!host || !LOCAL_NAMES.has(host.name) || host.port !== String(port)) {
    return { status: 421, error: 'Otter Studio only answers requests addressed to this computer (localhost).' };
  }

  const origin = headers.origin;
  if (origin !== undefined && origin !== null) {
    let url;
    try { url = new URL(origin); } catch { url = null; }
    const originHost = url ? parseHost(url.host) : null;
    const same = url && url.protocol === 'http:' && originHost && LOCAL_NAMES.has(originHost.name) && originHost.port === String(port);
    if (!same) {
      return { status: 403, error: 'Requests from other web pages are not allowed.' };
    }
  }
  return null;
}

/**
 * Read a JSON request body, refusing bodies larger than `limit` bytes.
 * Resolves {} for an empty body and { raw } for text that is not JSON (as
 * before); rejects with err.status = 413 when the body is too large.
 */
export function readJsonBody(req, limit = MAX_BODY_BYTES) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let tooLarge = false;
    req.on('data', chunk => {
      if (tooLarge) return;
      size += chunk.length;
      if (size > limit) {
        tooLarge = true;
        const err = new Error(`The request is larger than ${Math.round(limit / 1024 / 1024)} MB.`);
        err.status = 413;
        reject(err);
        req.resume(); // drain and discard the rest
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (tooLarge) return;
      const body = Buffer.concat(chunks).toString('utf8');
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        resolve({ raw: body });
      }
    });
    req.on('error', reject);
  });
}

/** True when `target` is `root` or inside it (both absolute). */
export function isInside(root, target, pathModule) {
  const relative = pathModule.relative(root, target);
  return relative === '' || (!relative.startsWith('..') && !pathModule.isAbsolute(relative));
}
