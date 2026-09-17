// workspace-solution.js - Multi-Project Solution Format, Workspace Settings, and Trust Engine
export const DEFAULT_SOLUTION_SCHEMA = 'https://otter-lang.org/schema/workspace-v1.json';

export function createDefaultSolution(name, folders = [], settings = {}, trust = {}) {
  const cleanName = (name || 'my-solution').trim();
  return {
    $schema: DEFAULT_SOLUTION_SCHEMA,
    name: cleanName,
    version: '1.0.0',
    folders: Array.isArray(folders) && folders.length > 0 ? folders.map(f => ({
      name: f.name || (typeof f.path === 'string' ? f.path.split('/').pop() : 'project'),
      path: f.path || f
    })) : [],
    settings: {
      'editor.wordWrap': settings['editor.wordWrap'] !== undefined ? settings['editor.wordWrap'] : true,
      'editor.tabSize': settings['editor.tabSize'] || 4,
      'otter.lintOnType': settings['otter.lintOnType'] !== false,
      ...settings
    },
    trust: {
      isTrusted: trust.isTrusted !== undefined ? Boolean(trust.isTrusted) : true,
      trustedAt: trust.trustedAt || new Date().toISOString()
    }
  };
}

export function normalizeSolution(raw) {
  if (!raw || typeof raw !== 'object') {
    return createDefaultSolution('solution');
  }

  const name = typeof raw.name === 'string' && raw.name.trim() ? raw.name.trim() : 'solution';
  const folders = Array.isArray(raw.folders) ? raw.folders.map(f => {
    if (typeof f === 'string') {
      return { name: f.split('/').pop() || f, path: f.replace(/\\/g, '/') };
    }
    return {
      name: f?.name || (f?.path ? f.path.split('/').pop() : 'project'),
      path: (f?.path || '').replace(/\\/g, '/')
    };
  }).filter(f => Boolean(f.path)) : [];

  return {
    $schema: raw.$schema || DEFAULT_SOLUTION_SCHEMA,
    name,
    version: typeof raw.version === 'string' ? raw.version : '1.0.0',
    folders,
    settings: (raw.settings && typeof raw.settings === 'object') ? { ...raw.settings } : {
      'editor.wordWrap': true,
      'editor.tabSize': 4,
      'otter.lintOnType': true
    },
    trust: {
      isTrusted: Boolean(raw.trust?.isTrusted),
      trustedAt: raw.trust?.trustedAt || null
    }
  };
}

export function validateSolution(solution) {
  const errors = [];
  const warnings = [];

  if (!solution || typeof solution !== 'object') {
    errors.push('Solution is empty or not a valid JSON object.');
    return { ok: false, errors, warnings };
  }

  if (!solution.name || typeof solution.name !== 'string' || !solution.name.trim()) {
    errors.push('Solution name is required.');
  }

  if (!Array.isArray(solution.folders) || solution.folders.length === 0) {
    warnings.push('Solution currently contains no project folders.');
  } else {
    solution.folders.forEach((f, idx) => {
      if (!f || !f.path) {
        errors.push(`Folder entry at index ${idx} is missing a path.`);
      }
    });
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings
  };
}

export function serializeSolution(solution) {
  return JSON.stringify(normalizeSolution(solution), null, 2) + '\n';
}

const TRUSTED_STORAGE_KEY = 'otter-studio-trusted-workspaces';

export function isWorkspaceTrusted(workspacePath, solutionObj = null) {
  if (solutionObj?.trust?.isTrusted === true) {
    return true;
  }
  if (!workspacePath) return true; // untitled / clean workspace default
  if (typeof localStorage === 'undefined') return true;

  try {
    const raw = localStorage.getItem(TRUSTED_STORAGE_KEY);
    const set = raw ? JSON.parse(raw) : {};
    return Boolean(set[workspacePath]);
  } catch {
    return true;
  }
}

export function setWorkspaceTrust(workspacePath, isTrusted = true) {
  if (!workspacePath || typeof localStorage === 'undefined') return;
  try {
    const raw = localStorage.getItem(TRUSTED_STORAGE_KEY);
    const set = raw ? JSON.parse(raw) : {};
    if (isTrusted) {
      set[workspacePath] = { trusted: true, time: new Date().toISOString() };
    } else {
      delete set[workspacePath];
    }
    localStorage.setItem(TRUSTED_STORAGE_KEY, JSON.stringify(set));
  } catch (e) {
    console.warn('Could not save workspace trust to localStorage:', e);
  }
}
