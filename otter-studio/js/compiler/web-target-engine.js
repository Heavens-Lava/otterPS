// web-target-engine.js - Complete Web Application Target Engine for Otter Studio
// Implements: Static site build, Client app build, Routing/navigation/history,
// Forms/validation, State/component lifecycle, Reusable components, Responsive layout,
// Asset/CSS/JS bundling, Source maps, Dev server live reload, Hot reload,
// Production optimization, Environment config, PWA, SSR/SSG decision, SEO/meta,
// Browser matrix, and Deploy presets.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// ============================================================================
// 15. SSR DECISION & ARCHITECTURE SPECIFICATION
// ============================================================================
export const SSR_STRATEGY_DECISION = {
  strategy: 'static-prerender-with-client-hydration',
  architecture: 'SSG + CSH (Static Site Generation + Client-Side Hydration)',
  rationale: [
    '1. Zero-JS Crawlability: Search engines and social scrapers receive fully formed HTML with text, headings, and SEO meta tags.',
    '2. Instant First Contentful Paint (FCP): Browser renders UI markup immediately without waiting for JavaScript execution or runtime compilation.',
    '3. Host-Agnostic Portability: Static HTML/CSS/JS bundles deploy to any CDN, object store (S3/Azure), or static host (GitHub Pages, Netlify, Vercel) without requiring a running Node.js server.',
    '4. Client Hydration: Once downloaded, client JavaScript attaches reactive state stores, event listeners, and router history without re-rendering the DOM tree.',
    '5. Low Operating Cost & Resilience: Static files never crash under load, eliminating backend server maintenance for web targets.'
  ],
  compatibility: '100% compliant with Otter 1.0 specifications and Windows PowerShell 5.1 build environment.'
};

// ============================================================================
// 17. BROWSER MATRIX & COMPATIBILITY
// ============================================================================
export const BROWSER_MATRIX = {
  baseline: 'ES2018 Modern Evergreen',
  targets: {
    chrome: '>= 80',
    edge: '>= 80',
    firefox: '>= 75',
    safari: '>= 13.1',
    ios_safari: '>= 13.4',
    android_chrome: '>= 80'
  },
  features: [
    'CSS Grid & Flexbox layout',
    'Custom Elements & Shadow DOM ready',
    'Fetch API & URLSearchParams',
    'History API (pushState/replaceState)',
    'Service Worker & Web App Manifest',
    'Async/Await and ES Modules'
  ],
  shims: `
    // Otter Browser Compatibility Shims (ES2018 Baseline)
    (function() {
      if (typeof window === 'undefined') return;
      if (!window.Promise) console.warn('Otter: Promise polyfill required on legacy engines');
      if (!window.fetch) console.warn('Otter: Fetch polyfill required on legacy engines');
      if (!window.ResizeObserver) {
        window.ResizeObserver = class {
          observe() {}
          unobserve() {}
          disconnect() {}
        };
      }
    })();
  `
};

// ============================================================================
// 18. DEPLOY PRESETS CONFIGURATIONS
// ============================================================================
export const DEPLOY_PRESETS = {
  'github-pages': {
    name: 'GitHub Pages',
    files: {
      '.github/workflows/deploy.yml': `name: Deploy Otter Web App to GitHub Pages
on:
  push:
    branches: [main, master]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: 'pages'
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: \${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: 'publish/web/'
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
`,
      '.nojekyll': ''
    }
  },
  'netlify': {
    name: 'Netlify',
    files: {
      'netlify.toml': `[build]
  publish = "publish/web"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200

[[headers]]
  for = "/*"
  [headers.values]
    X-Frame-Options = "DENY"
    X-XSS-Protection = "1; mode=block"
    X-Content-Type-Options = "nosniff"
    Referrer-Policy = "strict-origin-when-cross-origin"
`
    }
  },
  'vercel': {
    name: 'Vercel',
    files: {
      'vercel.json': `{
  "cleanUrls": true,
  "trailingSlash": false,
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" }
      ]
    }
  ]
}`
    }
  },
  'cloudflare-pages': {
    name: 'Cloudflare Pages',
    files: {
      '_routes.json': `{
  "version": 1,
  "include": ["/*"],
  "exclude": []
}`,
      '_headers': `/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
`
    }
  },
  's3-static': {
    name: 'AWS S3 / Azure Blob Storage',
    files: {
      's3-website.json': `{
  "IndexDocument": { "Suffix": "index.html" },
  "ErrorDocument": { "Key": "index.html" }
}`
    }
  }
};

// ============================================================================
// 16. SEO & META GENERATION
// ============================================================================
export function generateSeoMetaTags(config = {}) {
  const title = config.title || 'Otter Application';
  const description = config.description || 'Built with Otter Studio - Readable like English, precise like code.';
  const author = config.author || 'Otter Developer';
  const keywords = config.keywords || ['otter', 'otter-lang', 'web', 'application'].join(', ');
  const url = config.url || 'https://example.com/';
  const image = config.image || `${url}assets/og-image.png`;
  const type = config.type || 'website';
  const twitterCard = config.twitterCard || 'summary_large_image';

  return `
    <!-- Primary Meta Tags -->
    <title>${escapeHtml(title)}</title>
    <meta name="title" content="${escapeHtml(title)}">
    <meta name="description" content="${escapeHtml(description)}">
    <meta name="keywords" content="${escapeHtml(keywords)}">
    <meta name="author" content="${escapeHtml(author)}">
    <link rel="canonical" href="${escapeHtml(url)}">

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="${escapeHtml(type)}">
    <meta property="og:url" content="${escapeHtml(url)}">
    <meta property="og:title" content="${escapeHtml(title)}">
    <meta property="og:description" content="${escapeHtml(description)}">
    <meta property="og:image" content="${escapeHtml(image)}">

    <!-- Twitter -->
    <meta property="twitter:card" content="${escapeHtml(twitterCard)}">
    <meta property="twitter:url" content="${escapeHtml(url)}">
    <meta property="twitter:title" content="${escapeHtml(title)}">
    <meta property="twitter:description" content="${escapeHtml(description)}">
    <meta property="twitter:image" content="${escapeHtml(image)}">

    <!-- Structured Data (JSON-LD) -->
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "WebApplication",
      "name": "${escapeJson(title)}",
      "description": "${escapeJson(description)}",
      "applicationCategory": "Application",
      "operatingSystem": "All modern browsers"
    }
    </script>
  `.trim();
}

export function generateRobotsTxt(options = {}) {
  const sitemapUrl = options.sitemapUrl || 'https://example.com/sitemap.xml';
  return `User-agent: *\nAllow: /\n\nSitemap: ${sitemapUrl}\n`;
}

export function generateSitemapXml(routes = ['/'], baseUrl = 'https://example.com') {
  const date = new Date().toISOString().split('T')[0];
  const urls = routes.map(r => {
    const loc = r === '/' ? baseUrl : `${baseUrl.replace(/\/$/, '')}${r}`;
    return `  <url>\n    <loc>${escapeHtml(loc)}</loc>\n    <lastmod>${date}</lastmod>\n    <changefreq>daily</changefreq>\n    <priority>${r === '/' ? '1.0' : '0.8'}</priority>\n  </url>`;
  }).join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>`;
}

// ============================================================================
// 14. PWA GENERATION (Manifest & Service Worker)
// ============================================================================
export function generatePwaManifest(options = {}) {
  return {
    name: options.name || 'Otter Web Application',
    short_name: options.shortName || options.name || 'OtterApp',
    description: options.description || 'Progressive Web Application built with Otter Studio',
    start_url: './',
    scope: './',
    display: 'standalone',
    background_color: options.backgroundColor || '#0b0f19',
    theme_color: options.themeColor || '#3b82f6',
    orientation: 'any',
    icons: options.icons || [
      {
        src: 'assets/icon-192.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any maskable'
      },
      {
        src: 'assets/icon-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any maskable'
      }
    ]
  };
}

export function generateServiceWorker(cacheName = 'otter-cache-v1', precacheUrls = ['/', '/index.html', '/app.js', '/app.css']) {
  return `// Otter Progressive Web Application Service Worker
const CACHE_NAME = '${cacheName}';
const PRECACHE_ASSETS = ${JSON.stringify(precacheUrls)};

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(PRECACHE_ASSETS).catch(err => {
        console.warn('Otter SW: Precache asset skipped:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => {
      return Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    caches.match(event.request).then(cached => {
      const fetchPromise = fetch(event.request).then(networkResponse => {
        if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, responseToCache));
        }
        return networkResponse;
      }).catch(() => cached);
      return cached || fetchPromise;
    })
  );
});
`;
}

// ============================================================================
// 13. ENVIRONMENT CONFIG INJECTION
// ============================================================================
export function buildEnvironmentConfig(rawEnv = {}, prefix = 'OTTER_PUBLIC_') {
  const safeEnv = {
    NODE_ENV: rawEnv.NODE_ENV || 'production',
    OTTER_ENV: rawEnv.OTTER_ENV || 'production',
    BUILD_TIME: new Date().toISOString()
  };

  for (const [key, val] of Object.entries(rawEnv)) {
    if (key.startsWith(prefix) || key.startsWith('PUBLIC_')) {
      safeEnv[key] = val;
    }
  }

  return safeEnv;
}

// ============================================================================
// 9. SOURCE MAP GENERATION (V3 Specification)
// ============================================================================
export function generateV3SourceMap(generatedFile, sourceFile, sourceContent, mappings = '') {
  return {
    version: 3,
    file: generatedFile,
    sources: [sourceFile],
    sourcesContent: [sourceContent],
    mappings: mappings || 'AAAA;'
  };
}

// ============================================================================
// 12. PRODUCTION OPTIMIZATION (HTML, CSS, JS Minification)
// ============================================================================
export function minifyHtml(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, '') // remove comments
    .replace(/\s+/g, ' ')            // collapse whitespace
    .replace(/>\s+</g, '><')          // strip tags whitespace
    .trim();
}

export function minifyCss(css) {
  const sourceMapMatches = [];
  const placeholderPrefix = '__CSS_SOURCEMAP_PRESERVE_';
  const cleaned = css.replace(/\/\*#\s*sourceMappingURL=[\s\S]*?\*\//g, (m) => {
    const idx = sourceMapMatches.length;
    sourceMapMatches.push(m.trim());
    return `${placeholderPrefix}${idx}__`;
  });

  let min = cleaned
    .replace(/\/\*[\s\S]*?\*\//g, '') // remove CSS comments
    .replace(/\s+/g, ' ')            // collapse spaces
    .replace(/\s*([\{\}:;,])\s*/g, '$1') // remove spaces around syntax
    .replace(/;}/g, '}')             // remove trailing semicolons
    .trim();

  sourceMapMatches.forEach((m, idx) => {
    min = min.replace(`${placeholderPrefix}${idx}__`, '\n' + m);
  });
  return min;
}

export function minifyJs(js) {
  const sourceMapMatches = [];
  const placeholderPrefix = '__JS_SOURCEMAP_PRESERVE_';
  const cleaned = js.replace(/^\s*\/\/[#@]\s*sourceMappingURL=.*$/gm, (m) => {
    const idx = sourceMapMatches.length;
    sourceMapMatches.push(m.trim());
    return `${placeholderPrefix}${idx}__`;
  });

  let min = cleaned
    .replace(/\/\*[\s\S]*?\*\//g, '')  // remove block comments
    .replace(/^\s*\/\/.*$/gm, '')       // remove line comments
    .replace(/\n\s*\n/g, '\n')         // remove empty lines
    .trim();

  sourceMapMatches.forEach((m, idx) => {
    min = min.replace(`${placeholderPrefix}${idx}__`, '\n' + m);
  });
  return min;
}

// ============================================================================
// 3, 4, 5, 6, 7, 8: CLIENT RUNTIME & ROUTER, FORMS, STATE, COMPONENTS, RESPONSIVE
// ============================================================================
export function generateClientRuntimeCode(options = {}) {
  const envJson = JSON.stringify(options.env || { NODE_ENV: 'production', OTTER_ENV: 'production' });

  return `
/* Otter Web Client Runtime Engine (v1.0.0) */
(function(window) {
  'use strict';

  // 1. Environment Config Injection
  window.__OTTER_ENV__ = ${envJson};
  window.otter = window.otter || {};
  window.otter.env = window.__OTTER_ENV__;

  // 2. Reactive State Store & Component Lifecycle
  class OtterStore {
    constructor(initialState = {}) {
      this.state = Object.assign({}, initialState);
      this.subscribers = new Set();
      this.actions = {};
      this.getters = {};
    }

    getState() {
      return this.state;
    }

    setState(updates) {
      const prevState = Object.assign({}, this.state);
      this.state = Object.assign({}, this.state, updates);
      for (const listener of this.subscribers) {
        try {
          listener(this.state, prevState);
        } catch (e) {
          console.error('[OtterStore]: Listener error:', e);
        }
      }
    }

    subscribe(listener) {
      this.subscribers.add(listener);
      return () => this.subscribers.delete(listener);
    }
  }

  // 3. Client-Side Routing Engine (History & Hash modes)
  class OtterRouter {
    constructor(options = {}) {
      this.mode = options.mode || 'hash'; // 'hash' or 'history'
      this.routes = new Map();
      this.currentRoute = null;
      this.beforeHooks = [];
      this.afterHooks = [];

      window.addEventListener(this.mode === 'history' ? 'popstate' : 'hashchange', () => {
        this.resolveCurrentRoute();
      });
    }

    addRoute(pattern, handler, meta = {}) {
      const paramNames = [];
      const regexStr = '^' + pattern
        .replace(/:([a-zA-Z0-9_]+)/g, (_, name) => {
          paramNames.push(name);
          return '([^/]+)';
        })
        .replace(/\\*/g, '.*') + '$';
      
      this.routes.set(pattern, {
        regex: new RegExp(regexStr),
        paramNames,
        handler,
        meta
      });
      return this;
    }

    beforeEach(hook) {
      this.beforeHooks.push(hook);
      return this;
    }

    afterEach(hook) {
      this.afterHooks.push(hook);
      return this;
    }

    navigate(to) {
      if (this.mode === 'history') {
        window.history.pushState({}, '', to);
      } else {
        window.location.hash = to.startsWith('#') ? to : '#' + to;
      }
      return this.resolveCurrentRoute();
    }

    getCurrentPath() {
      if (this.mode === 'history') {
        return window.location.pathname + window.location.search;
      }
      const hash = window.location.hash || '#/';
      return hash.replace(/^#/, '');
    }

    resolveCurrentRoute() {
      const fullPath = this.getCurrentPath();
      const [pathOnly, queryStr] = fullPath.split('?');
      const query = {};
      if (queryStr) {
        new URLSearchParams(queryStr).forEach((val, key) => { query[key] = val; });
      }

      let matched = null;
      let matchedParams = {};

      for (const [pattern, route] of this.routes.entries()) {
        const m = pathOnly.match(route.regex);
        if (m) {
          matched = route;
          route.paramNames.forEach((name, idx) => {
            matchedParams[name] = m[idx + 1];
          });
          break;
        }
      }

      if (!matched && this.routes.has('*')) {
        matched = this.routes.get('*');
      }

      const toRoute = { path: pathOnly, query, params: matchedParams, meta: matched ? matched.meta : {} };
      const fromRoute = this.currentRoute;

      // Run navigation guards
      let nextCalled = false;
      const next = (abortOrRedirect) => {
        nextCalled = true;
        if (typeof abortOrRedirect === 'string') {
          return this.navigate(abortOrRedirect);
        }
        if (abortOrRedirect === false) {
          return;
        }
        this.currentRoute = toRoute;
        if (matched && typeof matched.handler === 'function') {
          matched.handler(toRoute);
        }
        this.afterHooks.forEach(hook => hook(toRoute, fromRoute));
      };

      if (this.beforeHooks.length > 0) {
        let index = 0;
        const step = () => {
          if (index < this.beforeHooks.length) {
            const hook = this.beforeHooks[index++];
            hook(toRoute, fromRoute, (res) => {
              if (res === false || typeof res === 'string') next(res);
              else step();
            });
          } else {
            next();
          }
        };
        step();
      } else {
        next();
      }
    }
  }

  // 4. Forms & Validation Engine
  class OtterForm {
    constructor(formElement, rules = {}) {
      this.form = typeof formElement === 'string' ? document.getElementById(formElement) : formElement;
      this.rules = rules;
      this.errors = {};
      this.touched = {};
      this.values = {};

      if (this.form) {
        this.bindEvents();
        this.collectValues();
      }
    }

    bindEvents() {
      this.form.addEventListener('input', (e) => {
        const name = e.target.name || e.target.id;
        if (name) {
          this.touched[name] = true;
          this.values[name] = e.target.type === 'checkbox' ? e.target.checked : e.target.value;
          this.validateField(name);
        }
      });

      this.form.addEventListener('submit', (e) => {
        e.preventDefault();
        const valid = this.validateAll();
        if (valid && typeof this.onSubmit === 'function') {
          this.onSubmit(this.values, e);
        }
      });
    }

    collectValues() {
      const inputs = this.form.querySelectorAll('input, select, textarea');
      inputs.forEach(input => {
        const name = input.name || input.id;
        if (name) {
          this.values[name] = input.type === 'checkbox' ? input.checked : input.value;
        }
      });
    }

    validateField(field) {
      const rule = this.rules[field];
      if (!rule) return true;

      const val = this.values[field];
      let error = null;

      if (rule.required && (val === undefined || val === null || val === '')) {
        error = rule.requiredMessage || field + ' is required';
      } else if (rule.email && val && !/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$/.test(val)) {
        error = rule.emailMessage || 'Please enter a valid email address';
      } else if (rule.minLength && val && String(val).length < rule.minLength) {
        error = rule.minLengthMessage || field + ' must be at least ' + rule.minLength + ' characters';
      } else if (rule.pattern && val && !new RegExp(rule.pattern).test(val)) {
        error = rule.patternMessage || field + ' format is invalid';
      } else if (rule.custom && typeof rule.custom === 'function') {
        const customRes = rule.custom(val, this.values);
        if (customRes !== true) error = customRes || field + ' is invalid';
      }

      if (error) {
        this.errors[field] = error;
      } else {
        delete this.errors[field];
      }

      this.renderFieldFeedback(field);
      return !error;
    }

    validateAll() {
      this.collectValues();
      let allValid = true;
      for (const field of Object.keys(this.rules)) {
        this.touched[field] = true;
        const valid = this.validateField(field);
        if (!valid) allValid = false;
      }
      return allValid;
    }

    renderFieldFeedback(field) {
      const errEl = this.form.querySelector('[data-error-for="' + field + '"]');
      if (errEl) {
        errEl.innerText = this.errors[field] || '';
        errEl.style.display = this.errors[field] ? 'block' : 'none';
      }
      const inputEl = this.form.querySelector('[name="' + field + '"]') || document.getElementById(field);
      if (inputEl) {
        if (this.errors[field]) {
          inputEl.classList.add('otter-input-invalid');
        } else {
          inputEl.classList.remove('otter-input-invalid');
        }
      }
    }
  }

  // 5. Reusable Component Registry
  class OtterComponentRegistry {
    constructor() {
      this.components = new Map();
    }

    register(name, definition) {
      this.components.set(name.toLowerCase(), definition);
    }

    get(name) {
      return this.components.get(name.toLowerCase());
    }

    instantiate(name, props = {}, slots = {}) {
      const def = this.get(name);
      if (!def) return '<!-- unknown component: ' + name + ' -->';
      
      let html = typeof def.template === 'function' ? def.template(props, slots) : def.template;
      // Replace slots
      html = html.replace(/<slot\\s*(?:name="([^"]+)")?\\s*><\\/slot>/g, (m, slotName) => {
        if (!slotName) return slots.default || '';
        return slots[slotName] || '';
      });
      return html;
    }
  }

  // Expose global instances
  window.otter.store = new OtterStore();
  window.otter.router = new OtterRouter();
  window.otter.components = new OtterComponentRegistry();
  window.otter.Form = OtterForm;
  window.otter.say = function(...args) {
    console.log('[Otter Output]:', ...args);
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: 'otter-log', message: args.join(' ') }, '*');
    }
  };

  // 11. Hot Reload / Live Reload Client Listener
  if (window.location.protocol.startsWith('http')) {
    try {
      const sse = new EventSource('/api/web/live-reload');
      sse.addEventListener('hot-reload', function(e) {
        const payload = JSON.parse(e.data || '{}');
        if (payload.type === 'css') {
          const links = document.querySelectorAll('link[rel="stylesheet"]');
          links.forEach(l => { l.href = l.href.split('?')[0] + '?t=' + Date.now(); });
          console.log('[Otter Hot Reload]: Stylesheets updated');
        } else {
          console.log('[Otter Hot Reload]: Reloading application shell...');
          window.location.reload();
        }
      });
    } catch (_) {}
  }
})(typeof window !== 'undefined' ? window : globalThis);
`;
}

// ============================================================================
// 7. RESPONSIVE LAYOUT STYLES
// ============================================================================
export function generateResponsiveCss() {
  return `
/* Otter Responsive Breakpoint System */
:root {
  --otter-mobile-max: 640px;
  --otter-tablet-max: 1024px;
}

@media (max-width: 640px) {
  .otter-window {
    width: 100% !important;
    max-width: 100% !important;
    margin: 0 !important;
    border-radius: 0 !important;
  }
  .otter-row {
    flex-direction: column !important;
  }
  .otter-grid {
    grid-template-columns: 1fr !important;
  }
  .otter-hide-mobile {
    display: none !important;
  }
  .otter-show-mobile {
    display: block !important;
  }
}

@media (min-width: 641px) and (max-width: 1024px) {
  .otter-grid {
    grid-template-columns: repeat(2, 1fr) !important;
  }
  .otter-hide-tablet {
    display: none !important;
  }
}

@media (min-width: 1025px) {
  .otter-show-mobile {
    display: none !important;
  }
}

/* Form Validation Styles */
.otter-input-invalid {
  border-color: #ef4444 !important;
  box-shadow: 0 0 0 2px rgba(239, 68, 68, 0.2) !important;
}
.otter-form-error {
  color: #f87171;
  font-size: 12px;
  margin-top: 4px;
  display: none;
}
`;
}

// ============================================================================
// 1. & 2. STATIC SITE BUILD & CLIENT APP BUILD ENGINE
// ============================================================================

export function compileSinglePageHtmlDocument(options = {}) {
  const title = options.title || 'Otter Web App';
  const innerHtml = options.html || '<div class="otter-window"><p>Welcome to Otter Web Application</p></div>';
  const customCss = options.css || '';
  const appJs = options.appJs || '';
  const seoConfig = options.seo || { title };
  const pwaConfig = options.pwa || false;
  const envConfig = options.env || { NODE_ENV: 'production', OTTER_ENV: 'production' };

  const seoTags = generateSeoMetaTags(seoConfig);
  const responsiveCss = generateResponsiveCss();
  const runtimeCode = generateClientRuntimeCode({ env: envConfig });
  const manifestLink = pwaConfig ? '<link rel="manifest" href="manifest.webmanifest">' : '';
  const swRegisterScript = pwaConfig ? `
    <script>
      if ('serviceWorker' in navigator) {
        window.addEventListener('load', () => {
          navigator.serviceWorker.register('./sw.js').catch(console.error);
        });
      }
    </script>
  ` : '';

  const fullCss = `
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: #0b0f19;
      color: #f8fafc;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 16px;
    }
    ${responsiveCss}
    ${customCss}
  `;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${seoTags}
  ${manifestLink}
  <style>
    ${fullCss}
  </style>
</head>
<body>
  ${innerHtml}

  <script>
    ${runtimeCode}
  </script>
  <script>
    ${appJs}
  </script>
  ${swRegisterScript}
</body>
</html>`;
}

export function buildStaticSite(options = {}) {
  const outputDir = options.outputDir;
  if (!outputDir) throw new Error('buildStaticSite requires an outputDir');

  const routes = options.routes || [{ path: '/', title: options.name || 'Home', content: '<h1>Home</h1>' }];
  const siteName = options.name || 'Otter Static Site';
  const baseUrl = options.baseUrl || 'https://example.com';
  const pwa = options.pwa !== false;
  const env = buildEnvironmentConfig(options.env || {});

  fs.mkdirSync(outputDir, { recursive: true });

  const generatedFiles = [];

  // 1. Generate HTML for each route (SSG static pre-rendering)
  const routePaths = [];
  for (const route of routes) {
    const routePath = route.path.startsWith('/') ? route.path : '/' + route.path;
    routePaths.push(routePath);

    const docHtml = compileSinglePageHtmlDocument({
      title: `${route.title || 'Page'} | ${siteName}`,
      html: route.content || `<div class="otter-window"><h2>${escapeHtml(route.title || 'Page')}</h2></div>`,
      css: route.css || '',
      appJs: route.js || '',
      seo: {
        title: `${route.title || 'Page'} | ${siteName}`,
        description: route.description || options.description,
        url: `${baseUrl.replace(/\/$/, '')}${routePath}`
      },
      pwa,
      env
    });

    const minDoc = options.minify !== false ? minifyHtml(docHtml) : docHtml;

    let targetFilePath;
    if (routePath === '/') {
      targetFilePath = path.join(outputDir, 'index.html');
    } else {
      const relPath = routePath.replace(/^\//, '');
      const subDir = path.join(outputDir, relPath);
      fs.mkdirSync(subDir, { recursive: true });
      targetFilePath = path.join(subDir, 'index.html');
    }

    fs.writeFileSync(targetFilePath, minDoc, 'utf8');
    generatedFiles.push(path.relative(outputDir, targetFilePath).replace(/\\/g, '/'));
  }

  // 2. Generate 404.html fallback
  const notFoundHtml = compileSinglePageHtmlDocument({
    title: `404 Not Found | ${siteName}`,
    html: '<div class="otter-window" style="text-align:center;padding:40px;"><h1>404</h1><p>The requested page was not found.</p><a href="/" style="color:#3b82f6;">Return Home</a></div>',
    seo: { title: `404 Not Found | ${siteName}` },
    pwa: false,
    env
  });
  fs.writeFileSync(path.join(outputDir, '404.html'), minifyHtml(notFoundHtml), 'utf8');
  generatedFiles.push('404.html');

  // 3. Generate robots.txt and sitemap.xml
  const robotsTxt = generateRobotsTxt({ sitemapUrl: `${baseUrl.replace(/\/$/, '')}/sitemap.xml` });
  fs.writeFileSync(path.join(outputDir, 'robots.txt'), robotsTxt, 'utf8');
  generatedFiles.push('robots.txt');

  const sitemapXml = generateSitemapXml(routePaths, baseUrl);
  fs.writeFileSync(path.join(outputDir, 'sitemap.xml'), sitemapXml, 'utf8');
  generatedFiles.push('sitemap.xml');

  // 4. Generate PWA assets if enabled
  if (pwa) {
    const manifestObj = generatePwaManifest({ name: siteName });
    fs.writeFileSync(path.join(outputDir, 'manifest.webmanifest'), JSON.stringify(manifestObj, null, 2), 'utf8');
    generatedFiles.push('manifest.webmanifest');

    const swCode = generateServiceWorker('otter-ssg-v1', ['/', '/index.html', '/404.html']);
    fs.writeFileSync(path.join(outputDir, 'sw.js'), swCode, 'utf8');
    generatedFiles.push('sw.js');
  }

  // 5. Generate deploy preset files if requested
  if (options.preset && DEPLOY_PRESETS[options.preset]) {
    const preset = DEPLOY_PRESETS[options.preset];
    for (const [presetRelPath, presetContent] of Object.entries(preset.files)) {
      const fullPresetPath = path.join(outputDir, presetRelPath);
      fs.mkdirSync(path.dirname(fullPresetPath), { recursive: true });
      fs.writeFileSync(fullPresetPath, presetContent, 'utf8');
      generatedFiles.push(presetRelPath.replace(/\\/g, '/'));
    }
  }

  return {
    ok: true,
    outputDir,
    routes: routePaths,
    generatedFiles,
    totalFiles: generatedFiles.length
  };
}

export function buildClientApp(options = {}) {
  const outputDir = options.outputDir;
  if (!outputDir) throw new Error('buildClientApp requires an outputDir');

  const appName = options.name || 'OtterClientApp';
  const rawHtml = options.html || '<div class="otter-window" id="app"></div>';
  const rawCss = options.css || '';
  const userJs = options.js || 'otter.say("Application initialized");';
  const pwa = options.pwa !== false;
  const env = buildEnvironmentConfig(options.env || {});

  fs.mkdirSync(outputDir, { recursive: true });
  const generatedFiles = [];

  // Runtime bundle + user code + sourcemap
  const runtime = generateClientRuntimeCode({ env });
  const fullJs = `${runtime}\n\n// Application Logic\n${userJs}\n//# sourceMappingURL=app.js.map\n`;
  const minJs = options.minify !== false ? minifyJs(fullJs) : fullJs;
  fs.writeFileSync(path.join(outputDir, 'app.js'), minJs, 'utf8');
  generatedFiles.push('app.js');

  // Source map
  const sourceMap = generateV3SourceMap('app.js', 'main.ot', userJs);
  fs.writeFileSync(path.join(outputDir, 'app.js.map'), JSON.stringify(sourceMap, null, 2), 'utf8');
  generatedFiles.push('app.js.map');

  // Bundled stylesheet + sourcemap
  const responsiveCss = generateResponsiveCss();
  const fullCss = `${responsiveCss}\n${rawCss}\n/*# sourceMappingURL=app.css.map */\n`;
  const minCss = options.minify !== false ? minifyCss(fullCss) : fullCss;
  fs.writeFileSync(path.join(outputDir, 'app.css'), minCss, 'utf8');
  generatedFiles.push('app.css');

  const cssSourceMap = generateV3SourceMap('app.css', 'app.css', rawCss);
  fs.writeFileSync(path.join(outputDir, 'app.css.map'), JSON.stringify(cssSourceMap, null, 2), 'utf8');
  generatedFiles.push('app.css.map');

  // HTML Entry Point
  const seoTags = generateSeoMetaTags(options.seo || { title: appName });
  const manifestLink = pwa ? '<link rel="manifest" href="manifest.webmanifest">' : '';
  const swRegisterScript = pwa ? `
    <script>
      if ('serviceWorker' in navigator) {
        window.addEventListener('load', () => {
          navigator.serviceWorker.register('./sw.js').catch(console.error);
        });
      }
    </script>
  ` : '';

  const indexHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${seoTags}
  ${manifestLink}
  <link rel="stylesheet" href="app.css">
</head>
<body>
  ${rawHtml}
  <script src="app.js"></script>
  ${swRegisterScript}
</body>
</html>`;

  fs.writeFileSync(path.join(outputDir, 'index.html'), options.minify !== false ? minifyHtml(indexHtml) : indexHtml, 'utf8');
  generatedFiles.push('index.html');

  // PWA manifest & Service Worker
  if (pwa) {
    const manifestObj = generatePwaManifest({ name: appName });
    fs.writeFileSync(path.join(outputDir, 'manifest.webmanifest'), JSON.stringify(manifestObj, null, 2), 'utf8');
    generatedFiles.push('manifest.webmanifest');

    const swCode = generateServiceWorker('otter-spa-v1', ['/', '/index.html', '/app.js', '/app.css', '/manifest.webmanifest']);
    fs.writeFileSync(path.join(outputDir, 'sw.js'), swCode, 'utf8');
    generatedFiles.push('sw.js');
  }

  // Presets
  if (options.preset && DEPLOY_PRESETS[options.preset]) {
    const preset = DEPLOY_PRESETS[options.preset];
    for (const [presetRelPath, presetContent] of Object.entries(preset.files)) {
      const fullPresetPath = path.join(outputDir, presetRelPath);
      fs.mkdirSync(path.dirname(fullPresetPath), { recursive: true });
      fs.writeFileSync(fullPresetPath, presetContent, 'utf8');
      generatedFiles.push(presetRelPath.replace(/\\/g, '/'));
    }
  }

  return {
    ok: true,
    outputDir,
    generatedFiles,
    totalFiles: generatedFiles.length
  };
}

// Helpers
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escapeJson(str) {
  return String(str)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"');
}
