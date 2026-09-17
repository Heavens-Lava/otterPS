// project-manifest.js - Rich Project Manifest Schema, Validation, and Helpers for Otter Studio

export const VALID_ARCHETYPES = ['console', 'desktop', 'web', 'game'];

export function createDefaultManifest(name, archetype = 'desktop', entryFile = null, options = {}) {
  const cleanName = (name || 'my-app').trim().replace(/[^a-zA-Z0-9_\-\.]/g, '-');
  const target = VALID_ARCHETYPES.includes(archetype) ? archetype : 'desktop';
  const defaultEntry = entryFile || (target === 'console' ? 'script.ot' : (target === 'web' ? 'web-app.ot' : (target === 'game' ? 'game.ot' : 'main.ot')));

  const manifest = {
    $schema: 'https://otter-lang.org/schema/project-v1.json',
    name: cleanName,
    version: options.version || '1.0.0',
    description: options.description || `Modern Otter ${target} application`,
    archetype: target,
    target: target,
    entryPoint: defaultEntry,
    author: options.author || 'Otter Developer',
    license: options.license || 'MIT',
    created: options.created || new Date().toISOString(),
    build: {
      outputDir: options.outputDir || 'dist',
      minify: options.minify || false,
      sourceMaps: options.sourceMaps !== undefined ? options.sourceMaps : true,
      clean: options.clean !== undefined ? options.clean : true
    },
    permissions: {
      filesystem: options.filesystem !== undefined ? options.filesystem : true,
      network: options.network || (target === 'web'),
      clipboard: options.clipboard !== undefined ? options.clipboard : true,
      process: options.process || false
    },
    dependencies: options.dependencies || {
      core: '^1.0.0'
    },
    assets: options.assets || (target === 'web' || target === 'desktop' ? ['styles.css'] : []),
    scripts: options.scripts || {
      start: `otter run ${defaultEntry}`,
      build: 'otter build',
      test: 'otter test'
    }
  };

  return manifest;
}

export function normalizeManifest(raw) {
  if (!raw || typeof raw !== 'object') {
    return createDefaultManifest('my-app', 'desktop', 'main.ot');
  }

  const name = typeof raw.name === 'string' && raw.name.trim() ? raw.name.trim() : 'my-app';
  const archetype = typeof raw.archetype === 'string' ? raw.archetype : (raw.target || 'desktop');
  const target = typeof raw.target === 'string' ? raw.target : archetype;
  const entryPoint = typeof raw.entryPoint === 'string' ? raw.entryPoint : (raw.main || 'main.ot');

  return {
    $schema: raw.$schema || 'https://otter-lang.org/schema/project-v1.json',
    name,
    version: typeof raw.version === 'string' ? raw.version : '1.0.0',
    description: typeof raw.description === 'string' ? raw.description : '',
    archetype,
    target,
    entryPoint,
    author: typeof raw.author === 'string' ? raw.author : '',
    license: typeof raw.license === 'string' ? raw.license : 'MIT',
    created: raw.created || new Date().toISOString(),
    build: {
      outputDir: raw.build?.outputDir || 'dist',
      minify: Boolean(raw.build?.minify),
      sourceMaps: raw.build?.sourceMaps !== false,
      clean: raw.build?.clean !== false
    },
    permissions: {
      filesystem: raw.permissions?.filesystem !== false,
      network: Boolean(raw.permissions?.network),
      clipboard: raw.permissions?.clipboard !== false,
      process: Boolean(raw.permissions?.process)
    },
    dependencies: (raw.dependencies && typeof raw.dependencies === 'object') ? { ...raw.dependencies } : {},
    assets: Array.isArray(raw.assets) ? [...raw.assets] : [],
    scripts: (raw.scripts && typeof raw.scripts === 'object') ? { ...raw.scripts } : {}
  };
}

export function validateManifest(manifest, projectFiles = []) {
  const errors = [];
  const warnings = [];

  if (!manifest || typeof manifest !== 'object') {
    errors.push('Manifest is empty or not a valid JSON object.');
    return { ok: false, errors, warnings };
  }

  // Name validation
  if (!manifest.name || typeof manifest.name !== 'string' || !manifest.name.trim()) {
    errors.push('Project name is required.');
  } else if (!/^[a-zA-Z0-9_\-\.]+$/.test(manifest.name)) {
    warnings.push('Project name should only contain alphanumeric characters, hyphens, dots, or underscores.');
  }

  // Version validation (SemVer check)
  if (!manifest.version || typeof manifest.version !== 'string') {
    warnings.push('Project version is missing; defaulting to 1.0.0.');
  } else if (!/^\d+\.\d+\.\d+(-[a-zA-Z0-9_\-\.]+)?$/.test(manifest.version.trim())) {
    warnings.push(`Version "${manifest.version}" does not strictly adhere to Semantic Versioning (e.g. 1.0.0).`);
  }

  // Archetype & Target validation
  const target = manifest.target || manifest.archetype;
  if (!target || !VALID_ARCHETYPES.includes(target)) {
    warnings.push(`Target "${target}" is not one of the certified Otter archetypes (console, desktop, web, game).`);
  }

  // Entrypoint existence check
  if (!manifest.entryPoint || typeof manifest.entryPoint !== 'string' || !manifest.entryPoint.trim()) {
    errors.push('Project entryPoint is required (e.g. main.ot).');
  } else if (projectFiles.length > 0) {
    const entryBase = manifest.entryPoint.replace(/\\/g, '/').split('/').pop().toLowerCase();
    const found = projectFiles.some(f => {
      const p = (typeof f === 'string' ? f : (f.path || f.name || '')).replace(/\\/g, '/').toLowerCase();
      return p.endsWith(entryBase);
    });
    if (!found) {
      warnings.push(`Entrypoint file "${manifest.entryPoint}" was not found in the project directory.`);
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings
  };
}

export function serializeManifest(manifest) {
  return JSON.stringify(normalizeManifest(manifest), null, 2) + '\n';
}
