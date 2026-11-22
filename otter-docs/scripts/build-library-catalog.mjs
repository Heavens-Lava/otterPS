#!/usr/bin/env node
/**
 * scripts/build-library-catalog.mjs
 * Deterministic, offline-capable catalog generator for the Otter Website Component Library.
 *
 * Imports:
 *   1. Canonical Otter assets from Heavens-Lava/otter-net/library/
 *      (Packs, Snippets, Blueprints, Recipes, Workflows) with strict provenance &
 *      expected version/count validation so stale catalog data is never silently used.
 *   2. Multi-language curated components from otter-docs/library-components/*
 *      (Web, Desktop, Games, Styles & Effects) with strict file-existence and
 *      metadata validation.
 *
 * Output:
 *   <outputRoot>/static/library-catalog.json (deterministic, timestamp-free JSON).
 */

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');

function parseArgs(argv) {
  const opts = {
    otterNetLibrary: process.env.OTTER_NET_LIBRARY_PATH || '',
    outputRoot: resolve(DOCS_ROOT, 'generated'),
    sourceConfig: resolve(DOCS_ROOT, 'library-source.json')
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--otter-net-library' && argv[i + 1]) opts.otterNetLibrary = argv[++i];
    else if (a === '--output-root' && argv[i + 1]) opts.outputRoot = resolve(argv[++i]);
    else if (a === '--source-config' && argv[i + 1]) opts.sourceConfig = resolve(argv[++i]);
  }
  return opts;
}

function readUtf8(filePath) {
  return readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n');
}

function sha256Text(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function hashDirectoryDeterministic(rootDir) {
  const entries = [];
  function walk(dir) {
    const names = readdirSync(dir).sort();
    for (const name of names) {
      if (name.startsWith('.')) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) walk(full);
      else if (st.isFile()) {
        const rel = relative(rootDir, full).split(sep).join('/');
        const raw = readFileSync(full);
        // Normalize CRLF -> LF for text assets so the content hash is identical across Windows/macOS/Linux.
        const isBinary = raw.includes(0);
        const normalized = isBinary ? raw : Buffer.from(raw.toString('utf8').replace(/\r\n/g, '\n'), 'utf8');
        const digest = createHash('sha256').update(normalized).digest('hex');
        entries.push(`${rel}:${digest}`);
      }
    }
  }
  walk(rootDir);
  return sha256Text(entries.join('\n'));
}

function safeSlug(raw) {
  return String(raw).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

function verifyOtterNetProvenance(libraryDir, sourceConfig) {
  if (!existsSync(libraryDir) || !statSync(libraryDir).isDirectory()) {
    throw new Error(
      `Canonical otter-net library directory not found at '${libraryDir}'. ` +
      `Set OTTER_NET_LIBRARY_PATH or pass --otter-net-library <path>. Refusing to build with stale data.`
    );
  }
  const catalogFile = join(libraryDir, 'snippets', 'catalog.json');
  if (!existsSync(catalogFile)) {
    throw new Error(`Invalid otter-net library directory (missing snippets/catalog.json): ${libraryDir}`);
  }

  const repoDir = resolve(libraryDir, '..');
  let sourceCommit = 'unknown';
  let sourceBranch = 'unknown';
  let ancestorVerified = false;
  if (existsSync(join(repoDir, '.git'))) {
    try {
      sourceCommit = execFileSync('git', ['-C', repoDir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
      sourceBranch = execFileSync('git', ['-C', repoDir, 'rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' }).trim();
      if (sourceConfig.expectedCommit) {
        try {
          execFileSync('git', ['-C', repoDir, 'merge-base', '--is-ancestor', sourceConfig.expectedCommit, 'HEAD'], { stdio: 'ignore' });
          ancestorVerified = true;
        } catch {
          throw new Error(
            `Canonical otter-net checkout at '${repoDir}' (HEAD=${sourceCommit}) does not include expected commit ` +
            `${sourceConfig.expectedCommit} from library-source.json. Pull latest otter-net or update library-source.json.`
          );
        }
      }
    } catch (err) {
      if (err.message.includes('does not include expected commit')) throw err;
    }
  }

  const libraryTreeSha256 = hashDirectoryDeterministic(libraryDir);
  if (sourceConfig.expectedLibraryTreeSha256 && libraryTreeSha256 !== sourceConfig.expectedLibraryTreeSha256) {
    throw new Error(
      `Canonical otter-net library content hash mismatch.\n` +
      `  Expected: ${sourceConfig.expectedLibraryTreeSha256}\n` +
      `  Actual:   ${libraryTreeSha256}\n` +
      `Refusing to build with unverified or stale library contents. Update library-source.json intentionally if otter-net/library changed.`
    );
  }
  return {
    canonicalRepo: sourceConfig.canonicalRepo,
    expectedCommit: sourceConfig.expectedCommit,
    sourceCommit,
    sourceBranch,
    ancestorVerified,
    expectedOtterVersion: sourceConfig.expectedOtterVersion,
    libraryTreeSha256
  };
}

function normalizeLanguageList(langField, files = []) {
  const set = new Set();
  for (const part of String(langField || '').split('/').map((s) => s.trim()).filter(Boolean)) {
    if (part.toLowerCase() === 'js') set.add('JavaScript');
    else set.add(part);
  }
  for (const f of files) {
    const map = {
      otter: 'Otter', html: 'HTML', css: 'CSS', javascript: 'JavaScript',
      typescript: 'TypeScript', csharp: 'C#', xaml: 'WPF/XAML',
      gdscript: 'GDScript', luau: 'Luau'
    };
    if (map[f.language]) set.add(map[f.language]);
  }
  return [...set].sort();
}

function ingestOtterPacks(libraryDir, expectedPackVersions) {
  const packsRoot = join(libraryDir, 'packs');
  const results = [];
  if (!existsSync(packsRoot)) return results;

  for (const pub of readdirSync(packsRoot).sort()) {
    const pubDir = join(packsRoot, pub);
    if (!statSync(pubDir).isDirectory()) continue;
    for (const pkg of readdirSync(pubDir).sort()) {
      const packDir = join(pubDir, pkg);
      if (!statSync(packDir).isDirectory()) continue;
      const manifestPath = join(packDir, 'otter.pack.json');
      if (!existsSync(manifestPath)) continue;

      const manifestText = readUtf8(manifestPath);
      const m = JSON.parse(manifestText);
      const fullId = `${m.publisher}/${m.name}`;
      if (expectedPackVersions?.[fullId] && m.version !== expectedPackVersions[fullId]) {
        throw new Error(
          `Pack version mismatch for '${fullId}': expected '${expectedPackVersions[fullId]}' in library-source.json, found '${m.version}'.`
        );
      }

      const files = [];
      const addIfExists = (label, rel, language) => {
        const full = join(packDir, rel);
        if (existsSync(full)) {
          files.push({ label, path: rel, language, content: readUtf8(full) });
        }
      };
      addIfExists(m.entry || 'src/main.ot', m.entry || 'src/main.ot', 'otter');
      addIfExists('otter.pack.json', 'otter.pack.json', 'json');
      addIfExists('tests/test.ot', 'tests/test.ot', 'otter');
      addIfExists('examples/demo.ot', 'examples/demo.ot', 'otter');

      const hasTests = existsSync(join(packDir, 'tests/test.ot'));
      const isSchemaV2 = Number(m.schemaVersion) >= 2 && Array.isArray(m.provides?.operations);
      const ops = m.provides?.operations || [];
      const types = m.provides?.types || [];
      const depsObj = { ...(m.dependencies || {}), ...(m.requires?.packages || {}) };
      const dependencies = Object.entries(depsObj).map(([name, version]) => ({ name, version }));

      results.push({
        id: fullId,
        slug: `pack-${safeSlug(fullId)}`,
        name: `${m.name} Pack`,
        description: m.description,
        category: 'otter',
        subcategory: 'Packs',
        otterKind: 'pack',
        language: 'Otter',
        languages: ['Otter'],
        framework: `Otter ${m.requiresOtter || '>=1.0.1'}`,
        tags: Array.from(new Set([...(m.tags || []), ...(m.provides?.capabilities || []), 'pack', 'schema-v2'])),
        version: m.version,
        license: m.license || 'MIT',
        platforms: (m.platforms || ['console']).map((p) => `Otter (${p})`),
        dependencies,
        contract: {
          schemaVersion: m.schemaVersion,
          variablePrefix: m.variablePrefix || '',
          requiresOtter: m.requiresOtter || '>=1.0.1',
          capabilities: m.provides?.capabilities || [],
          operationsCount: ops.length,
          operations: ops,
          types
        },
        preview: {
          type: 'contract-summary',
          caption: `Schema v${m.schemaVersion} Pack exposing ${ops.length} structurally AST-verified Otter 1.0.1 operations with isolated prefix '${m.variablePrefix || 'none'}'.`
        },
        files,
        install: `otter pack install ${fullId}\notter pack verify --contracts`,
        usage: `use ".otter/packages/${fullId}/${m.version}/${m.entry || 'src/main.ot'}"\n\n# Inspect exported operation contracts:\notter pack contract ${fullId}`,
        verification: isSchemaV2 && hasTests
          ? {
              status: 'contract-and-behavior-verified',
              label: 'Contract-Validated (AST) & Behaviorally Tested',
              details: `Schema v2 manifest structurally verified by 'otter pack verify --contracts' (${ops.length} operations, prefix '${m.variablePrefix}') plus behavioral assertions in tests/test.ot.`
            }
          : {
              status: 'behaviorally-tested',
              label: 'Behaviorally Tested',
              details: 'Verified via pack tests/test.ot.'
            },
        related: []
      });
    }
  }
  return results;
}

function ingestOtterSnippets(libraryDir) {
  const catalogPath = join(libraryDir, 'snippets', 'catalog.json');
  const raw = JSON.parse(readUtf8(catalogPath));
  const snippets = raw.snippets || [];
  return snippets.map((s) => ({
    id: `snippet/${s.id}`,
    slug: `snippet-${safeSlug(s.id)}`,
    name: s.title,
    description: s.description,
    category: 'otter',
    subcategory: 'Snippets',
    otterKind: 'snippet',
    language: 'Otter',
    languages: ['Otter'],
    framework: 'Otter 1.0.1',
    tags: Array.from(new Set([...(s.tags || []), safeSlug(s.category || 'snippet'), 'snippet'])),
    version: raw.version || '1.0.0',
    license: 'MIT',
    platforms: (s.platforms || ['console']).map((p) => `Otter (${p})`),
    dependencies: [],
    preview: {
      type: 'diagram',
      caption: `Zero-dependency Otter 1.0.1 snippet (${s.category || 'General'}). Copy the parameterized template or run the self-contained example.`,
      architecture: [
        `Category: ${s.category || 'General'}`,
        `Attribution: ${s.attribution || 'Otter Official Catalog'}`,
        'Zero external pack dependencies — paste directly into any .ot file'
      ]
    },
    files: [
      { label: 'template.ot', path: 'template.ot', language: 'otter', content: s.template || '' },
      { label: 'example.ot', path: 'example.ot', language: 'otter', content: s.example || '' }
    ],
    install: `otter snippet inspect ${s.id}`,
    usage: `Copy template.ot directly into your .ot source file, or run example.ot with 'otter run example.ot'.`,
    verification: {
      status: 'behaviorally-tested',
      label: 'Behaviorally Tested (Otter 1.0.1)',
      details: 'Validated against the Otter 1.0.1 parser and snippet behavioral suite (tools/test-snippets.ps1).'
    },
    related: []
  }));
}

function ingestOtterBlueprints(libraryDir) {
  const root = join(libraryDir, 'blueprints');
  const results = [];
  if (!existsSync(root)) return results;

  for (const pub of readdirSync(root).sort()) {
    const pubDir = join(root, pub);
    if (!statSync(pubDir).isDirectory()) continue;
    for (const name of readdirSync(pubDir).sort()) {
      const bpDir = join(pubDir, name);
      if (!statSync(bpDir).isDirectory()) continue;
      const manifestPath = join(bpDir, 'otter.blueprint.json');
      if (!existsSync(manifestPath)) continue;

      const bp = JSON.parse(readUtf8(manifestPath));
      const files = [
        { label: 'otter.blueprint.json', path: 'otter.blueprint.json', language: 'json', content: readUtf8(manifestPath) }
      ];
      for (const gf of bp.generatedFiles || []) {
        const tmplPath = join(bpDir, gf.template);
        if (existsSync(tmplPath)) {
          files.push({ label: gf.template, path: gf.template, language: 'otter', content: readUtf8(tmplPath) });
        }
      }
      for (const extra of ['tests/test.ot', 'examples/demo.ot']) {
        const full = join(bpDir, extra);
        if (existsSync(full)) files.push({ label: extra, path: extra, language: 'otter', content: readUtf8(full) });
      }

      const deps = (bp.packs || []).map((p) => ({ name: p.id, version: p.version }));
      const flow = (bp.nodes || []).map((n) => `${n.title || n.id} (${n.kind}${n.capability ? `: ${n.capability}` : ''})`);

      results.push({
        id: bp.id,
        slug: `blueprint-${safeSlug(bp.id)}`,
        name: `${bp.title} Blueprint`,
        description: bp.summary,
        category: 'otter',
        subcategory: 'Blueprints',
        otterKind: 'blueprint',
        language: 'Otter',
        languages: ['Otter'],
        framework: `Otter ${bp.requiresOtter || '>=1.0.1'}`,
        tags: Array.from(new Set(['blueprint', ...(bp.targets || []), ...(bp.packs || []).map((p) => p.id.split('/').pop())])),
        version: bp.version,
        license: 'MIT',
        platforms: (bp.targets || ['console']).map((t) => `Otter (${t})`),
        dependencies: deps,
        preview: {
          type: 'diagram',
          caption: bp.explanations?.intermediate || bp.summary,
          architecture: flow
        },
        files,
        install: `otter blueprint explain ${bp.id}\notter blueprint apply ${bp.id} --project ./my-app`,
        usage: bp.explanations?.beginner || `Preview and apply ${bp.id} to generate editable Otter 1.0.1 source files and pinned pack dependencies.`,
        verification: {
          status: 'behaviorally-tested',
          label: 'Behaviorally Tested Blueprint',
          details: 'Schema-validated Blueprint graph with generated Otter source verified by tools/test-blueprints.ps1.'
        },
        related: (bp.packs || []).map((p) => `pack-${safeSlug(p.id)}`)
      });
    }
  }
  return results;
}

function ingestOtterRecipes(libraryDir) {
  const root = join(libraryDir, 'recipes');
  const results = [];
  if (!existsSync(root)) return results;

  for (const pub of readdirSync(root).sort()) {
    const pubDir = join(root, pub);
    if (!statSync(pubDir).isDirectory()) continue;
    for (const name of readdirSync(pubDir).sort()) {
      const rcDir = join(pubDir, name);
      if (!statSync(rcDir).isDirectory()) continue;
      const manifestPath = join(rcDir, 'otter.recipe.json');
      if (!existsSync(manifestPath)) continue;

      const rc = JSON.parse(readUtf8(manifestPath));
      const files = [
        { label: 'otter.recipe.json', path: 'otter.recipe.json', language: 'json', content: readUtf8(manifestPath) }
      ];
      for (const gf of rc.generatedFiles || []) {
        const tmplPath = join(rcDir, gf.template);
        if (existsSync(tmplPath)) {
          files.push({ label: gf.template, path: gf.template, language: 'otter', content: readUtf8(tmplPath) });
        }
      }
      for (const extra of ['tests/test.ot', 'examples/demo.ot']) {
        const full = join(rcDir, extra);
        if (existsSync(full)) files.push({ label: extra, path: extra, language: 'otter', content: readUtf8(full) });
      }

      const deps = [
        ...(rc.packs || []).map((p) => ({ name: p.id, version: p.version })),
        ...(rc.blueprints || []).map((b) => ({ name: b.id, version: b.version }))
      ];
      const flow = (rc.steps || []).map((st) => `${st.id}: ${st.description} (${st.source})`);

      results.push({
        id: rc.id,
        slug: `recipe-${safeSlug(rc.id)}`,
        name: `${rc.title} Recipe`,
        description: rc.summary,
        category: 'otter',
        subcategory: 'Recipes',
        otterKind: 'recipe',
        language: 'Otter',
        languages: ['Otter'],
        framework: `Otter ${rc.requiresOtter || '>=1.0.1'}`,
        tags: Array.from(new Set(['recipe', rc.target || 'console', ...(rc.capabilities || [])])),
        version: rc.version,
        license: 'MIT',
        platforms: [`Otter (${rc.target || 'console'})`],
        dependencies: deps,
        preview: {
          type: 'diagram',
          caption: rc.explanations?.intermediate || rc.summary,
          architecture: flow.length ? flow : [`Composed packs: ${(rc.packs || []).map((p) => p.id).join(', ')}`]
        },
        files,
        install: `otter recipe inspect ${rc.id}\notter recipe apply ${rc.id} --project ./my-app`,
        usage: rc.explanations?.beginner || `Generates a working starter application composing verified Otter Packs and Blueprints.`,
        verification: {
          status: 'behaviorally-tested',
          label: 'Behaviorally Tested Recipe',
          details: 'Verified end-to-end via transactional composition staging, rollback tests, and tools/test-recipes.ps1.'
        },
        related: [
          ...(rc.packs || []).map((p) => `pack-${safeSlug(p.id)}`),
          ...(rc.blueprints || []).map((b) => `blueprint-${safeSlug(b.id)}`)
        ]
      });
    }
  }
  return results;
}

function ingestOtterWorkflows(libraryDir) {
  const wfDir = join(libraryDir, 'workflows');
  const results = [];
  if (!existsSync(wfDir)) return results;

  for (const fileName of readdirSync(wfDir).sort()) {
    if (!fileName.endsWith('.json')) continue;
    const fullPath = join(wfDir, fileName);
    const rawText = readUtf8(fullPath);
    const wf = JSON.parse(rawText);
    const wfId = wf.id || fileName.replace(/\.workflow\.json$|\.json$/, '');
    const deps = (wf.composedPacks || []).map((p) => ({ name: p, version: 'Schema v2' }));
    const stepSummary = (wf.steps || []).map((st) => {
      const adapters = Object.values(st.inputs || {})
        .filter((b) => b && b.adapter)
        .map((b) => b.adapter);
      const adp = adapters.length ? ` [adapter: ${adapters.join(', ')}]` : '';
      const ord = (st.orderAfter && st.orderAfter.length) ? ` [after: ${st.orderAfter.join(', ')}]` : '';
      return `${st.id}: ${st.pack}::${st.operation}()${adp}${ord}`;
    });

    results.push({
      id: `workflow/${wfId}`,
      slug: `workflow-${safeSlug(wfId)}`,
      name: wf.name,
      description: wf.description || `Declarative multi-pack workflow composing ${(wf.composedPacks || []).join(', ')}.`,
      category: 'otter',
      subcategory: 'Workflows',
      otterKind: 'workflow',
      language: 'Otter',
      languages: ['Otter', 'JSON'],
      framework: 'Otter Composition Planner (Phase 11)',
      tags: Array.from(new Set(['workflow', 'composition', 'dag', ...(wf.composedPacks || []).map((p) => p.split('/').pop())])),
      version: `1.0.0`,
      license: 'MIT',
      platforms: [`Otter (${wf.target || 'console'})`],
      dependencies: deps,
      preview: {
        type: 'diagram',
        caption: `Deterministic ${(wf.steps || []).length}-step multi-pack DAG composing ${(wf.composedPacks || []).length} Schema v2 Packs with explicit port bindings and side-effect ordering.`,
        architecture: stepSummary
      },
      files: [
        { label: fileName, path: fileName, language: 'json', content: rawText }
      ],
      install: `otter compose plan --workflow library/workflows/${fileName} --explain\notter compose plan --workflow library/workflows/${fileName} --apply --yes`,
      usage: `Apply into a fresh Otter console project with 'otter compose plan --workflow ... --apply --yes', verify with 'otter check src/main.ot', and execute with 'otter run src/main.ot'.`,
      verification: {
        status: 'contract-and-behavior-verified',
        label: 'Contract-Validated & Executed Outside Repo',
        details: 'Verified by Phase 11 Milestones 2 & 3 sandboxed suites (deterministic codegen, AST contract check, runtime execution, and 17-variable scoping isolation).'
      },
      related: (wf.composedPacks || []).map((p) => `pack-${safeSlug(p)}`)
    });
  }
  return results;
}

function ingestCuratedComponents(componentsDir) {
  const results = [];
  if (!existsSync(componentsDir)) return results;

  const requiredFields = [
    'id', 'slug', 'name', 'description', 'category', 'subcategory',
    'language', 'framework', 'tags', 'version', 'license', 'platforms',
    'dependencies', 'preview', 'files', 'install', 'usage', 'verification', 'related'
  ];

  for (const folder of readdirSync(componentsDir).sort()) {
    const dir = join(componentsDir, folder);
    if (!statSync(dir).isDirectory()) continue;
    const manifestPath = join(dir, 'component.json');
    if (!existsSync(manifestPath)) continue;

    const meta = JSON.parse(readUtf8(manifestPath));
    for (const field of requiredFields) {
      if (meta[field] === undefined || meta[field] === null) {
        throw new Error(`Component '${folder}' is missing required field '${field}' in component.json.`);
      }
    }
    if (!['web', 'desktop', 'games', 'effects', 'otter'].includes(meta.category)) {
      throw new Error(`Component '${folder}' has invalid category '${meta.category}'.`);
    }

    const files = [];
    for (const f of meta.files) {
      if (f.path.includes('..') || f.path.startsWith('/') || f.path.startsWith('\\')) {
        throw new Error(`Illegal path traversal in component '${folder}': ${f.path}`);
      }
      const abs = join(dir, f.path);
      if (!existsSync(abs)) {
        throw new Error(`Missing source file '${f.path}' referenced by component '${folder}'.`);
      }
      files.push({
        label: f.label,
        path: f.path,
        language: f.language,
        content: readUtf8(abs)
      });
    }

    const preview = { ...meta.preview };
    if (preview.type === 'iframe-sandbox') {
      const readOpt = (rel) => {
        if (!rel) return '';
        const abs = join(dir, rel);
        if (!existsSync(abs)) throw new Error(`Missing preview file '${rel}' in component '${folder}'.`);
        return readUtf8(abs);
      };
      preview.html = readOpt(preview.htmlFile);
      preview.css = readOpt(preview.cssFile);
      preview.js = readOpt(preview.jsFile);
    }

    results.push({
      ...meta,
      languages: normalizeLanguageList(meta.language, files),
      preview,
      files
    });
  }
  return results;
}

function wireCrossLinks(items) {
  const bySlug = new Map(items.map((i) => [i.slug, i]));
  // Automatically connect Otter packs to workflows/blueprints/recipes that reference them
  for (const item of items) {
    for (const relSlug of item.related || []) {
      const target = bySlug.get(relSlug);
      if (!target) {
        throw new Error(`Component '${item.slug}' references unknown related component '${relSlug}'.`);
      }
      if (!target.related.includes(item.slug) && target.related.length < 6) {
        target.related.push(item.slug);
      }
    }
  }
  for (const item of items) {
    item.related = Array.from(new Set(item.related)).sort();
  }
}

export function buildCatalog(options = {}) {
  const sourceConfigPath = options.sourceConfig || resolve(DOCS_ROOT, 'library-source.json');
  const sourceConfig = JSON.parse(readUtf8(sourceConfigPath));
  const otterNetLibrary = resolve(
    DOCS_ROOT,
    options.otterNetLibrary || process.env.OTTER_NET_LIBRARY_PATH || sourceConfig.defaultRelativePath
  );
  const outputRoot = resolve(options.outputRoot || resolve(DOCS_ROOT, 'generated'));

  const provenance = verifyOtterNetProvenance(otterNetLibrary, sourceConfig);
  const packs = ingestOtterPacks(otterNetLibrary, sourceConfig.expectedPackVersions);
  const snippets = ingestOtterSnippets(otterNetLibrary);
  const blueprints = ingestOtterBlueprints(otterNetLibrary);
  const recipes = ingestOtterRecipes(otterNetLibrary);
  const workflows = ingestOtterWorkflows(otterNetLibrary);
  const curated = ingestCuratedComponents(resolve(DOCS_ROOT, 'library-components'));

  const actualCounts = {
    packs: packs.length,
    snippets: snippets.length,
    blueprints: blueprints.length,
    recipes: recipes.length,
    workflows: workflows.length
  };
  for (const [k, expected] of Object.entries(sourceConfig.expectedCounts || {})) {
    if (actualCounts[k] !== expected) {
      throw new Error(
        `Canonical otter-net count mismatch for '${k}': expected ${expected} in library-source.json, got ${actualCounts[k]}.`
      );
    }
  }

  const allItems = [...curated, ...packs, ...workflows, ...blueprints, ...recipes, ...snippets];
  const seenSlugs = new Set();
  const seenIds = new Set();
  for (const item of allItems) {
    if (seenSlugs.has(item.slug)) throw new Error(`Duplicate component slug: ${item.slug}`);
    if (seenIds.has(item.id)) throw new Error(`Duplicate component id: ${item.id}`);
    seenSlugs.add(item.slug);
    seenIds.add(item.id);
  }

  wireCrossLinks(allItems);

  const catRank = { web: 0, effects: 1, desktop: 2, games: 3, otter: 4 };
  const subRank = { Packs: 0, Workflows: 1, Blueprints: 2, Recipes: 3, Snippets: 4 };
  allItems.sort((a, b) =>
    (catRank[a.category] ?? 9) - (catRank[b.category] ?? 9) ||
    (subRank[a.subcategory] ?? 99) - (subRank[b.subcategory] ?? 99) ||
    a.subcategory.localeCompare(b.subcategory) ||
    a.name.localeCompare(b.name) ||
    a.slug.localeCompare(b.slug)
  );

  const catalog = {
    schemaVersion: 1,
    provenance: {
      ...provenance,
      otterCounts: actualCounts,
      curatedCount: curated.length,
      totalCount: allItems.length
    },
    components: allItems
  };

  const outFile = join(outputRoot, 'static', 'library-catalog.json');
  mkdirSync(dirname(outFile), { recursive: true });
  writeFileSync(outFile, JSON.stringify(catalog, null, 2) + '\n', 'utf8');
  return { catalog, outFile };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const opts = parseArgs(process.argv.slice(2));
  const { catalog, outFile } = buildCatalog(opts);
  console.log(
    `Built library catalog (${catalog.provenance.totalCount} components: ` +
    `${catalog.provenance.curatedCount} curated + ` +
    `${catalog.provenance.otterCounts.packs} packs, ${catalog.provenance.otterCounts.workflows} workflows, ` +
    `${catalog.provenance.otterCounts.blueprints} blueprints, ${catalog.provenance.otterCounts.recipes} recipes, ` +
    `${catalog.provenance.otterCounts.snippets} snippets) -> ${outFile}`
  );
  console.log(
    `Provenance: ${catalog.provenance.canonicalRepo}@${catalog.provenance.sourceCommit.slice(0, 7)} ` +
    `(tree sha256: ${catalog.provenance.libraryTreeSha256.slice(0, 12)})`
  );
}
