// data-viewer.test.mjs - Comprehensive Certification Suite for Otter Studio Data & Query Viewer (Section 5)
import assert from 'node:assert/strict';
import http from 'node:http';
import { parseCsv, parseJsonDataset, exportToCsv, queryDataset, DataViewer } from '../js/data/data-viewer.js';

console.log('Testing Otter Studio Data & Query Viewer (Section 5)...');

const PORT = 4200;

function apiRequest(method, endpoint, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint, `http://127.0.0.1:${PORT}`);
    const req = http.request(url, {
      method,
      headers: {
        'Content-Type': 'application/json'
      }
    }, res => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : {} });
        } catch {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// -------------------------------------------------------------
// 1. RFC 4180 CSV Parser Tests
// -------------------------------------------------------------
{
  const simpleCsv = "id,name,role\r\n1,Alice,Engineer\r\n2,Bob,Designer";
  const { headers, rows } = parseCsv(simpleCsv);
  assert.deepEqual(headers, ['id', 'name', 'role']);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].id, '1');
  assert.equal(rows[0].name, 'Alice');
  assert.equal(rows[0].role, 'Engineer');
  assert.equal(rows[1].id, '2');
  assert.equal(rows[1].name, 'Bob');

  // Quoted fields with embedded commas and quotes
  const complexCsv = 'title,notes\r\n"Report, Q1","Contains ""quoted"" notes"\r\nPlain,Normal';
  const parsedComplex = parseCsv(complexCsv);
  assert.deepEqual(parsedComplex.headers, ['title', 'notes']);
  assert.equal(parsedComplex.rows.length, 2);
  assert.equal(parsedComplex.rows[0].title, 'Report, Q1');
  assert.equal(parsedComplex.rows[0].notes, 'Contains "quoted" notes');
  assert.equal(parsedComplex.rows[1].title, 'Plain');
  assert.equal(parsedComplex.rows[1].notes, 'Normal');

  console.log('  pass  RFC 4180 CSV parser (headers, quotes, escaped quotes, newlines)');
}

// -------------------------------------------------------------
// 2. JSON Dataset Parser Tests
// -------------------------------------------------------------
{
  const jsonArr = [
    { id: 101, user: 'admin', active: true, profile: { role: 'superuser' } },
    { id: 102, user: 'guest', active: false, score: 95 }
  ];
  const { headers, rows } = parseJsonDataset(jsonArr);
  assert.ok(headers.includes('id'));
  assert.ok(headers.includes('user'));
  assert.ok(headers.includes('active'));
  assert.ok(headers.includes('profile'));
  assert.ok(headers.includes('score'));
  assert.equal(rows.length, 2);
  assert.equal(rows[0].id, 101);
  assert.equal(rows[0].profile, '{"role":"superuser"}');
  assert.equal(rows[1].score, 95);

  // Key-value object
  const jsonObj = { settingA: 'valA', settingB: 123 };
  const kv = parseJsonDataset(jsonObj);
  assert.deepEqual(kv.headers, ['key', 'value']);
  assert.equal(kv.rows.length, 2);
  assert.equal(kv.rows[0].key, 'settingA');
  assert.equal(kv.rows[0].value, 'valA');

  console.log('  pass  JSON dataset parser (arrays of objects, nested serialization, key-value maps)');
}

// -------------------------------------------------------------
// 3. Query, Sort, Search, and Pagination Engine
// -------------------------------------------------------------
{
  const headers = ['id', 'name', 'score'];
  const rows = [
    { id: '1', name: 'Carol', score: '88' },
    { id: '2', name: 'Alice', score: '95' },
    { id: '3', name: 'Bob', score: '72' },
    { id: '4', name: 'Dave', score: '100' },
    { id: '5', name: 'Eve', score: '60' }
  ];

  // Sorting alphabetically
  const sortedAlpha = queryDataset(headers, rows, { sortColumn: 'name', sortDesc: false });
  assert.equal(sortedAlpha.rows[0].name, 'Alice');
  assert.equal(sortedAlpha.rows[1].name, 'Bob');
  assert.equal(sortedAlpha.rows[4].name, 'Eve');

  // Sorting numerically desc
  const sortedScoreDesc = queryDataset(headers, rows, { sortColumn: 'score', sortDesc: true });
  assert.equal(sortedScoreDesc.rows[0].score, '100');
  assert.equal(sortedScoreDesc.rows[1].score, '95');
  assert.equal(sortedScoreDesc.rows[4].score, '60');

  // Search filter
  const searched = queryDataset(headers, rows, { search: 'li' }); // matches Alice
  assert.equal(searched.totalRows, 1);
  assert.equal(searched.rows[0].name, 'Alice');

  // Pagination
  const page1 = queryDataset(headers, rows, { page: 1, pageSize: 2 });
  assert.equal(page1.rows.length, 2);
  assert.equal(page1.page, 1);
  assert.equal(page1.totalPages, 3);
  assert.equal(page1.totalRows, 5);

  const page2 = queryDataset(headers, rows, { page: 2, pageSize: 2 });
  assert.equal(page2.rows.length, 2);
  assert.equal(page2.page, 2);

  console.log('  pass  Query engine (alphabetic & numeric sort, search filter, multi-page pagination)');
}

// -------------------------------------------------------------
// 4. Export Serialization Tests
// -------------------------------------------------------------
{
  const headers = ['code', 'desc'];
  const rows = [
    { code: 'OK', desc: 'Success, completed' },
    { code: 'ERR', desc: 'Failure with "quotes"' }
  ];
  const csv = exportToCsv(headers, rows);
  assert.ok(csv.includes('code,desc'));
  assert.ok(csv.includes('"Success, completed"'));
  assert.ok(csv.includes('"Failure with ""quotes"""'));

  console.log('  pass  Export serialization (RFC 4180 CSV export with escaping)');
}

// -------------------------------------------------------------
// 5. Live Studio Server API (/api/data/query) Tests
// -------------------------------------------------------------
{
  // 5a. Query with inline CSV
  const csvBody = {
    content: "fruit,qty,price\r\nApple,10,1.5\r\nBanana,25,0.75\r\nCherry,50,3.00",
    format: 'csv',
    sortColumn: 'qty',
    sortDesc: true,
    page: 1,
    pageSize: 10
  };
  const resCsv = await apiRequest('POST', '/api/data/query', csvBody);
  assert.equal(resCsv.status, 200);
  assert.ok(resCsv.body.ok);
  assert.deepEqual(resCsv.body.headers, ['fruit', 'qty', 'price']);
  assert.equal(resCsv.body.totalRows, 3);
  assert.equal(resCsv.body.rows[0].fruit, 'Cherry'); // qty 50 is highest

  // 5b. Query with inline JSON
  const jsonBody = {
    content: JSON.stringify([
      { metric: 'cpu', value: 45 },
      { metric: 'memory', value: 80 },
      { metric: 'disk', value: 30 }
    ]),
    format: 'json',
    search: 'mem'
  };
  const resJson = await apiRequest('POST', '/api/data/query', jsonBody);
  assert.equal(resJson.status, 200);
  assert.ok(resJson.body.ok);
  assert.equal(resJson.body.totalRows, 1);
  assert.equal(resJson.body.rows[0].metric, 'memory');

  // 5c. Query with structured rows
  const rowsBody = {
    headers: ['colA', 'colB'],
    rows: [
      { colA: 'x1', colB: 'y1' },
      { colA: 'x2', colB: 'y2' }
    ]
  };
  const resRows = await apiRequest('POST', '/api/data/query', rowsBody);
  assert.equal(resRows.status, 200);
  assert.equal(resRows.body.totalRows, 2);

  // 5d. Path traversal protection
  const traversalRes = await apiRequest('POST', '/api/data/query', { path: '../../evil.csv' });
  assert.equal(traversalRes.status, 403);

  // 5e. Nonexistent path
  const notFoundRes = await apiRequest('POST', '/api/data/query', { path: 'nonexistent_test_123.csv' });
  assert.equal(notFoundRes.status, 404);

  console.log('  pass  Live Studio Server API (/api/data/query for CSV, JSON, sort, search, pagination, security)');
}

console.log('All Otter Studio Data & Query Viewer tests passed (5/5).');
