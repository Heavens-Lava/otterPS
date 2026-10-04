// backend-services.test.mjs - Comprehensive Test Suite for Section 16: Services / API / Backend Target
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  OtterHttpServer,
  OtterRouter,
  OtterAuthHooks,
  corsMiddleware,
  serveStatic,
  OtterUploadHandler,
  OtterStreamEngine,
  OtterWebSocketHandler,
  OtterStructuredLogger,
  OtterServiceConfig,
  OtterDatabaseAdapter,
  OtterJobQueue,
  OtterHealthCheckEngine,
  registerGracefulShutdown,
  generateSystemdService,
  generateDockerDeployment,
  buildBackendServicePackage
} from '../js/project/backend-target-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ----------------------------------------------------------------------------
// 1. HTTP Server, Routing & Request/Response Model (Section 16.1, 16.2, 16.3, 16.4, 16.5)
// ----------------------------------------------------------------------------
test('Section 16.1-16.5: HTTP Server, Routing, JSON API & Middleware', async () => {
  const router = new OtterRouter();

  router.get('/api/users/:id', async (req, res) => {
    res.status(200).json({
      id: req.params.id,
      query: req.query,
      user: req.user || null
    });
  });

  router.post('/api/echo', async (req, res) => {
    const body = await req.json();
    res.status(201).json({ received: body });
  });

  const server = new OtterHttpServer({ port: 9123, router });

  // Add custom middleware
  server.use(async (req, res, next) => {
    res.header('X-Custom-Middleware', 'Passed');
    await next();
  });

  await server.listen();

  try {
    // 1. GET route with parameter and query string
    const getRes = await fetch('http://127.0.0.1:9123/api/users/42?filter=active');
    assert.equal(getRes.status, 200);
    assert.equal(getRes.headers.get('x-custom-middleware'), 'Passed');
    const getData = await getRes.json();
    assert.equal(getData.id, '42');
    assert.equal(getData.query.filter, 'active');

    // 2. POST route with JSON body
    const postRes = await fetch('http://127.0.0.1:9123/api/echo', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: 'Hello Otter Backend', count: 5 })
    });
    assert.equal(postRes.status, 201);
    const postData = await postRes.json();
    assert.equal(postData.received.message, 'Hello Otter Backend');
    assert.equal(postData.received.count, 5);

    // 3. 404 route
    const notFoundRes = await fetch('http://127.0.0.1:9123/api/nonexistent');
    assert.equal(notFoundRes.status, 404);
  } finally {
    await server.close();
  }
});

// ----------------------------------------------------------------------------
// 2. Auth Hooks & CORS (Section 16.7, 16.8)
// ----------------------------------------------------------------------------
test('Section 16.7, 16.8: Auth Hooks & CORS Middleware', async () => {
  const router = new OtterRouter();

  const authMiddleware = OtterAuthHooks.bearerAuth(async (token) => {
    if (token === 'secret-token-123') {
      return { id: 1, name: 'Admin', roles: ['admin'] };
    }
    return null;
  });

  const roleGuard = OtterAuthHooks.requireRole('admin');

  router.get('/api/admin', async (req, res) => {
    res.status(200).json({ ok: true, admin: req.user.name });
  });

  const server = new OtterHttpServer({ port: 9124, router });
  server.use(corsMiddleware({ origin: 'https://app.otter-lang.org' }));
  server.use(authMiddleware);
  server.use(roleGuard);

  await server.listen();

  try {
    // OPTIONS CORS preflight
    const optRes = await fetch('http://127.0.0.1:9124/api/admin', { method: 'OPTIONS' });
    assert.equal(optRes.status, 204);
    assert.equal(optRes.headers.get('access-control-allow-origin'), 'https://app.otter-lang.org');

    // Unauthenticated GET (401)
    const unauthRes = await fetch('http://127.0.0.1:9124/api/admin');
    assert.equal(unauthRes.status, 401);

    // Authenticated GET (200)
    const authRes = await fetch('http://127.0.0.1:9124/api/admin', {
      headers: { 'Authorization': 'Bearer secret-token-123' }
    });
    assert.equal(authRes.status, 200);
    const authData = await authRes.json();
    assert.equal(authData.ok, true);
    assert.equal(authData.admin, 'Admin');
  } finally {
    await server.close();
  }
});

// ----------------------------------------------------------------------------
// 3. Static Files & Uploads (Section 16.9, 16.10)
// ----------------------------------------------------------------------------
test('Section 16.9, 16.10: Static File Serving and Upload Handling', async () => {
  const testStaticDir = path.join(REPO_ROOT, 'publish', 'test-static-backend');
  fs.mkdirSync(testStaticDir, { recursive: true });
  fs.writeFileSync(path.join(testStaticDir, 'test.txt'), 'Hello Static Content', 'utf8');

  const router = new OtterRouter();
  router.post('/api/upload', async (req, res) => {
    const upload = await OtterUploadHandler.parseUpload(req, 1024 * 1024);
    res.status(200).json({ size: upload.size, contentType: upload.contentType });
  });

  const server = new OtterHttpServer({ port: 9125, router });
  server.use(serveStatic(testStaticDir));

  await server.listen();

  try {
    // Static file fetch
    const fileRes = await fetch('http://127.0.0.1:9125/test.txt');
    assert.equal(fileRes.status, 200);
    const fileText = await fileRes.text();
    assert.equal(fileText, 'Hello Static Content');

    // Upload fetch
    const uploadRes = await fetch('http://127.0.0.1:9125/api/upload', {
      method: 'POST',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: Buffer.from('Binary upload payload')
    });
    assert.equal(uploadRes.status, 200);
    const uploadData = await uploadRes.json();
    assert.equal(uploadData.size, 21);
  } finally {
    await server.close();
    if (fs.existsSync(testStaticDir)) {
      fs.rmSync(testStaticDir, { recursive: true, force: true });
    }
  }
});

// ----------------------------------------------------------------------------
// 4. Streaming, WebSockets, Logging, Config & Secrets (Section 16.11, 16.12, 16.13, 16.14, 16.15)
// ----------------------------------------------------------------------------
test('Section 16.11-16.15: Streaming, WebSockets, Logging & Config Secrets', async () => {
  // 1. Streaming / SSE
  const mockRes = {
    headers: {},
    raw: {
      writeHead: () => {},
      write: (data) => { sseOutput.push(data); },
      end: () => {}
    }
  };
  const sseOutput = [];
  const sse = OtterStreamEngine.createEventStream(mockRes);
  sse.send('metric', { cpu: 12.5 });
  assert.ok(sseOutput.some(chunk => chunk.includes('event: metric')));
  assert.ok(sseOutput.some(chunk => chunk.includes('"cpu":12.5')));

  // 2. WebSockets Handler
  const wsHandler = new OtterWebSocketHandler();
  let clientReceived = null;
  const mockSocket = {
    write: (msg) => { clientReceived = msg; },
    on: () => {}
  };
  wsHandler.addClient(mockSocket);
  const sentCount = wsHandler.broadcast({ type: 'notification', text: 'Alert' });
  assert.equal(sentCount, 1);
  assert.match(clientReceived, /Alert/);

  // 3. Structured Logging
  const logger = new OtterStructuredLogger();
  const entry = logger.info('Database connection established', { host: 'localhost', port: 5432 });
  assert.equal(entry.level, 'INFO');
  assert.equal(entry.meta.port, 5432);

  // 4. Config & Secrets
  const cfg = new OtterServiceConfig(
    { port: 8080, dbUser: 'otter', dbPassword: 'super_secret_password' },
    { apiKey: 'sk_test_12345' }
  );
  assert.equal(cfg.get('port'), 8080);
  assert.equal(cfg.getSecret('apiKey'), 'sk_test_12345');
  const redacted = cfg.redact();
  assert.equal(redacted.dbPassword, '********');
});

// ----------------------------------------------------------------------------
// 5. Database Integration & Background Jobs (Section 16.16, 16.17)
// ----------------------------------------------------------------------------
test('Section 16.16, 16.17: Database Adapter & Background Jobs Queue', async () => {
  // Database Adapter
  const db = new OtterDatabaseAdapter();
  db.beginTransaction();
  db.insert('users', { name: 'Alice', role: 'admin' });
  db.insert('users', { name: 'Bob', role: 'user' });
  db.commit();

  const admins = db.find('users', u => u.role === 'admin');
  assert.equal(admins.length, 1);
  assert.equal(admins[0].name, 'Alice');

  // Background Job Queue
  const queue = new OtterJobQueue();
  queue.register('send_email', async (payload) => {
    return { sentTo: payload.to, status: 'ok' };
  });

  const job = queue.enqueue('send_email', { to: 'alice@example.com' });
  assert.equal(job.status, 'pending');

  const processed = await queue.processNext();
  assert.equal(processed.status, 'completed');
  assert.equal(processed.result.sentTo, 'alice@example.com');
});

// ----------------------------------------------------------------------------
// 6. Graceful Shutdown & Health Checks (Section 16.18, 16.19)
// ----------------------------------------------------------------------------
test('Section 16.18, 16.19: Graceful Shutdown & Health Check Engine', async () => {
  let dbHealthy = true;
  const health = new OtterHealthCheckEngine({
    database: async () => dbHealthy,
    storage: async () => true
  });

  const status1 = await health.check();
  assert.equal(status1.status, 'healthy');
  assert.equal(status1.checks.database, 'up');

  dbHealthy = false;
  const status2 = await health.check();
  assert.equal(status2.status, 'degraded');
  assert.equal(status2.checks.database, 'down');

  // Graceful shutdown trigger
  let drained = false;
  const mockServer = {
    close: async () => { drained = true; }
  };
  let hookCalled = false;
  const shutdown = registerGracefulShutdown(mockServer, [async () => { hookCalled = true; }]);
  await shutdown.trigger('SIGTERM');
  assert.equal(drained, true);
  assert.equal(hookCalled, true);
});

// ----------------------------------------------------------------------------
// 7. Production Deployment & Containers (Section 16.20, 16.21)
// ----------------------------------------------------------------------------
test('Section 16.20, 16.21: Systemd Service, Docker & Deployment Package', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-backend-deploy');

  try {
    const res = buildBackendServicePackage({
      outputDir: testOutDir,
      name: 'otter-billing-api',
      port: 8080
    });

    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'otter-billing-api.service')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'Dockerfile')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'docker-compose.yml')));

    const systemd = fs.readFileSync(path.join(testOutDir, 'otter-billing-api.service'), 'utf8');
    assert.match(systemd, /Description=Otter Backend Service: otter-billing-api/);
    assert.match(systemd, /Restart=always/);

    const dockerfile = fs.readFileSync(path.join(testOutDir, 'Dockerfile'), 'utf8');
    assert.match(dockerfile, /FROM mcr\.microsoft\.com\/powershell/);
    assert.match(dockerfile, /EXPOSE 8080/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});
