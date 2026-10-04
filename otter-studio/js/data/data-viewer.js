// data-viewer.js - Interactive Data, CSV, JSON, and Query Viewer for Otter Studio
import { escapeHtml } from '../terminal/ansi-parser.js';

/**
 * Parses RFC 4180 CSV text into structured headers and rows.
 * @param {string} csvText 
 * @returns {{ headers: string[], rows: Record<string, string>[] }}
 */
export function parseCsv(csvText) {
  if (typeof csvText !== 'string' || !csvText.trim()) {
    return { headers: [], rows: [] };
  }

  const lines = [];
  let currentRow = [];
  let currentCell = '';
  let inQuotes = false;
  let i = 0;

  while (i < csvText.length) {
    const char = csvText[i];
    const nextChar = csvText[i + 1];

    if (inQuotes) {
      if (char === '"') {
        if (nextChar === '"') {
          currentCell += '"';
          i += 2;
          continue;
        } else {
          inQuotes = false;
        }
      } else {
        currentCell += char;
      }
    } else {
      if (char === '"') {
        inQuotes = true;
      } else if (char === ',') {
        currentRow.push(currentCell.trim());
        currentCell = '';
      } else if (char === '\r' && nextChar === '\n') {
        currentRow.push(currentCell.trim());
        lines.push(currentRow);
        currentRow = [];
        currentCell = '';
        i += 2;
        continue;
      } else if (char === '\n' || char === '\r') {
        currentRow.push(currentCell.trim());
        lines.push(currentRow);
        currentRow = [];
        currentCell = '';
      } else {
        currentCell += char;
      }
    }
    i++;
  }

  if (currentCell.length > 0 || currentRow.length > 0) {
    currentRow.push(currentCell.trim());
    lines.push(currentRow);
  }

  if (lines.length === 0) return { headers: [], rows: [] };

  const headers = lines[0].map((h, idx) => h || `column_${idx + 1}`);
  const rows = [];

  for (let r = 1; r < lines.length; r++) {
    const rawRow = lines[r];
    if (rawRow.length === 1 && rawRow[0] === '') continue; // skip trailing empty line
    const rowObj = {};
    for (let c = 0; c < headers.length; c++) {
      rowObj[headers[c]] = rawRow[c] !== undefined ? rawRow[c] : '';
    }
    rows.push(rowObj);
  }

  return { headers, rows };
}

/**
 * Normalizes JSON data into headers and rows.
 * @param {string|any} jsonInput 
 * @returns {{ headers: string[], rows: Record<string, any>[] }}
 */
export function parseJsonDataset(jsonInput) {
  let parsed = jsonInput;
  if (typeof jsonInput === 'string') {
    try {
      parsed = JSON.parse(jsonInput);
    } catch (e) {
      throw new Error(`Invalid JSON dataset: ${e.message}`);
    }
  }

  if (!parsed) return { headers: [], rows: [] };

  if (Array.isArray(parsed)) {
    if (parsed.length === 0) return { headers: [], rows: [] };
    const headerSet = new Set();
    for (const item of parsed) {
      if (item && typeof item === 'object') {
        for (const key of Object.keys(item)) headerSet.add(key);
      }
    }
    const headers = Array.from(headerSet);
    const rows = parsed.map(item => {
      if (item && typeof item === 'object') {
        const row = {};
        for (const h of headers) {
          const val = item[h];
          row[h] = (val !== null && typeof val === 'object') ? JSON.stringify(val) : (val ?? '');
        }
        return row;
      }
      return { value: item };
    });
    return { headers: headers.length > 0 ? headers : ['value'], rows };
  } else if (typeof parsed === 'object') {
    const headers = ['key', 'value'];
    const rows = Object.entries(parsed).map(([k, v]) => ({
      key: k,
      value: (v !== null && typeof v === 'object') ? JSON.stringify(v) : (v ?? '')
    }));
    return { headers, rows };
  }

  return { headers: ['value'], rows: [{ value: parsed }] };
}

/**
 * Serializes rows and headers to CSV string.
 */
export function exportToCsv(headers, rows) {
  const formatCell = val => {
    const s = String(val ?? '');
    if (s.includes(',') || s.includes('"') || s.includes('\n') || s.includes('\r')) {
      return '"' + s.replace(/"/g, '""') + '"';
    }
    return s;
  };

  const lines = [headers.map(formatCell).join(',')];
  for (const row of rows) {
    lines.push(headers.map(h => formatCell(row[h])).join(','));
  }
  return lines.join('\r\n');
}

/**
 * Filters, sorts, and paginates a dataset.
 */
export function queryDataset(headers, rows, options = {}) {
  let result = [...rows];

  // Search filter
  if (options.search && typeof options.search === 'string') {
    const q = options.search.toLowerCase().trim();
    result = result.filter(row => {
      return headers.some(h => String(row[h] ?? '').toLowerCase().includes(q));
    });
  }

  // Column sorting
  if (options.sortColumn && headers.includes(options.sortColumn)) {
    const col = options.sortColumn;
    const desc = options.sortDesc === true;
    result.sort((a, b) => {
      const va = a[col] ?? '';
      const vb = b[col] ?? '';
      const numA = Number(va);
      const numB = Number(vb);
      let cmp = 0;
      if (!isNaN(numA) && !isNaN(numB) && va !== '' && vb !== '') {
        cmp = numA - numB;
      } else {
        cmp = String(va).localeCompare(String(vb));
      }
      return desc ? -cmp : cmp;
    });
  }

  const totalRows = result.length;
  const pageSize = options.pageSize || 50;
  const page = Math.max(1, options.page || 1);
  const totalPages = Math.max(1, Math.ceil(totalRows / pageSize));
  const startIndex = (page - 1) * pageSize;
  const paginatedRows = result.slice(startIndex, startIndex + pageSize);

  return {
    headers,
    rows: paginatedRows,
    totalRows,
    page,
    totalPages,
    pageSize
  };
}

export class DataViewer {
  constructor(options = {}) {
    this.container = options.container || null;
    this.headers = [];
    this.rows = [];
    this.sortColumn = null;
    this.sortDesc = false;
    this.searchQuery = '';
    this.currentPage = 1;
    this.pageSize = options.pageSize || 25;
    this.title = options.title || 'Data Viewer';
  }

  loadData(headers, rows, title = null) {
    this.headers = headers || [];
    this.rows = rows || [];
    if (title) this.title = title;
    this.currentPage = 1;
    this.sortColumn = null;
    this.sortDesc = false;
    this.searchQuery = '';
    this.render();
  }

  loadCsv(csvText, title = 'CSV Data') {
    const { headers, rows } = parseCsv(csvText);
    this.loadData(headers, rows, title);
  }

  loadJson(jsonInput, title = 'JSON Data') {
    const { headers, rows } = parseJsonDataset(jsonInput);
    this.loadData(headers, rows, title);
  }

  getCurrentView() {
    return queryDataset(this.headers, this.rows, {
      search: this.searchQuery,
      sortColumn: this.sortColumn,
      sortDesc: this.sortDesc,
      page: this.currentPage,
      pageSize: this.pageSize
    });
  }

  render() {
    if (!this.container) return;
    const view = this.getCurrentView();

    let html = `
      <div class="data-viewer-toolbar">
        <div class="data-viewer-title">${escapeHtml(this.title)} <span class="data-badge">${view.totalRows} rows</span></div>
        <div class="data-viewer-controls">
          <input type="text" class="data-search-input" placeholder="Search data..." value="${escapeHtml(this.searchQuery)}">
          <button class="data-btn data-btn-export-csv" title="Export to CSV">CSV</button>
          <button class="data-btn data-btn-export-json" title="Export to JSON">JSON</button>
        </div>
      </div>
      <div class="data-table-container">
        <table class="data-grid-table">
          <thead>
            <tr>
              <th class="data-row-num">#</th>
              ${view.headers.map(h => {
                const isSorted = this.sortColumn === h;
                const arrow = isSorted ? (this.sortDesc ? ' ▼' : ' ▲') : '';
                return `<th class="data-header-cell" data-col="${escapeHtml(h)}">${escapeHtml(h)}${arrow}</th>`;
              }).join('')}
            </tr>
          </thead>
          <tbody>
            ${view.rows.map((row, idx) => {
              const rowNum = (view.page - 1) * view.pageSize + idx + 1;
              return `<tr>
                <td class="data-row-num">${rowNum}</td>
                ${view.headers.map(h => `<td class="data-cell">${escapeHtml(String(row[h] ?? ''))}</td>`).join('')}
              </tr>`;
            }).join('')}
          </tbody>
        </table>
      </div>
      <div class="data-viewer-pagination">
        <span>Page ${view.page} of ${view.totalPages} (${view.totalRows} total entries)</span>
        <div class="data-page-buttons">
          <button class="data-page-btn data-btn-prev" ${view.page <= 1 ? 'disabled' : ''}>Previous</button>
          <button class="data-page-btn data-btn-next" ${view.page >= view.totalPages ? 'disabled' : ''}>Next</button>
        </div>
      </div>
    `;

    this.container.innerHTML = html;
    this.bindEvents();
  }

  bindEvents() {
    if (!this.container) return;

    const searchInput = this.container.querySelector('.data-search-input');
    searchInput?.addEventListener('input', e => {
      this.searchQuery = e.target.value;
      this.currentPage = 1;
      this.render();
    });

    const headers = this.container.querySelectorAll('.data-header-cell');
    headers.forEach(th => {
      th.addEventListener('click', () => {
        const col = th.getAttribute('data-col');
        if (this.sortColumn === col) {
          if (!this.sortDesc) this.sortDesc = true;
          else {
            this.sortColumn = null;
            this.sortDesc = false;
          }
        } else {
          this.sortColumn = col;
          this.sortDesc = false;
        }
        this.render();
      });
    });

    const prevBtn = this.container.querySelector('.data-btn-prev');
    prevBtn?.addEventListener('click', () => {
      if (this.currentPage > 1) {
        this.currentPage--;
        this.render();
      }
    });

    const nextBtn = this.container.querySelector('.data-btn-next');
    nextBtn?.addEventListener('click', () => {
      const view = this.getCurrentView();
      if (this.currentPage < view.totalPages) {
        this.currentPage++;
        this.render();
      }
    });

    const exportCsvBtn = this.container.querySelector('.data-btn-export-csv');
    exportCsvBtn?.addEventListener('click', () => {
      const csv = exportToCsv(this.headers, this.rows);
      this.downloadFile(`${this.title.replace(/\s+/g, '_').toLowerCase()}.csv`, csv, 'text/csv');
    });

    const exportJsonBtn = this.container.querySelector('.data-btn-export-json');
    exportJsonBtn?.addEventListener('click', () => {
      const json = JSON.stringify(this.rows, null, 2);
      this.downloadFile(`${this.title.replace(/\s+/g, '_').toLowerCase()}.json`, json, 'application/json');
    });
  }

  downloadFile(filename, content, mimeType) {
    if (typeof document === 'undefined' || !document.createElement) return;
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }
}
