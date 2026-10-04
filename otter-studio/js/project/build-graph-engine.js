// build-graph-engine.js - Complete Build Graph & Incremental Build Engine for Otter Studio
// Implements: Build graph DAG, Incremental builds, Dependency tracking,
// Debug/release configs, Parallel builds, Build cache, Startup project,
// and Persisting launch settings.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// ============================================================================
// 1. BUILD GRAPH (DAG) & TOPOLOGICAL EXECUTION
// ============================================================================
export class BuildTask {
  constructor(id, action, dependencies = []) {
    this.id = id;
    this.action = action; // async function(context)
    this.dependencies = dependencies; // task IDs that must complete first
  }
}

export class BuildGraph {
  constructor() {
    this.tasks = new Map();
  }

  addTask(id, action, dependencies = []) {
    this.tasks.set(id, new BuildTask(id, action, dependencies));
    return this;
  }

  getTask(id) {
    return this.tasks.get(id);
  }

  // Topological sort with cycle detection (Kahn's algorithm)
  getExecutionOrder() {
    const inDegree = new Map();
    const adjList = new Map();

    for (const id of this.tasks.keys()) {
      inDegree.set(id, 0);
      adjList.set(id, []);
    }

    for (const [id, task] of this.tasks.entries()) {
      for (const dep of task.dependencies) {
        if (!this.tasks.has(dep)) {
          throw new Error(`Build graph error: Task "${id}" depends on unknown task "${dep}"`);
        }
        adjList.get(dep).push(id);
        inDegree.set(id, inDegree.get(id) + 1);
      }
    }

    const queue = [];
    for (const [id, deg] of inDegree.entries()) {
      if (deg === 0) queue.push(id);
    }

    const order = [];
    while (queue.length > 0) {
      const u = queue.shift();
      order.push(u);
      for (const v of adjList.get(u)) {
        inDegree.set(v, inDegree.get(v) - 1);
        if (inDegree.get(v) === 0) queue.push(v);
      }
    }

    if (order.length !== this.tasks.size) {
      throw new Error('Build graph error: Circular dependency detected in build tasks');
    }

    return order;
  }
}

// ============================================================================
// 3. DEPENDENCY TRACKING
// ============================================================================
export class DependencyTracker {
  constructor() {
    this.deps = new Map(); // file -> Set of imported files
    this.reverseDeps = new Map(); // imported file -> Set of files that depend on it
  }

  addDependency(sourceFile, importedFile) {
    const src = path.normalize(sourceFile).replace(/\\/g, '/');
    const imp = path.normalize(importedFile).replace(/\\/g, '/');

    if (!this.deps.has(src)) this.deps.set(src, new Set());
    this.deps.get(src).add(imp);

    if (!this.reverseDeps.has(imp)) this.reverseDeps.set(imp, new Set());
    this.reverseDeps.get(imp).add(src);
  }

  getAffectedFiles(changedFile) {
    const changed = path.normalize(changedFile).replace(/\\/g, '/');
    const affected = new Set([changed]);
    const queue = [changed];

    while (queue.length > 0) {
      const current = queue.shift();
      const dependents = this.reverseDeps.get(current);
      if (dependents) {
        for (const dep of dependents) {
          if (!affected.has(dep)) {
            affected.add(dep);
            queue.push(dep);
          }
        }
      }
    }

    return Array.from(affected);
  }
}

// ============================================================================
// 2. & 6. INCREMENTAL BUILDS & BUILD CACHE
// ============================================================================
export class IncrementalBuildManager {
  constructor(cacheDir = '.otter/cache/build') {
    this.cacheDir = cacheDir;
    this.cacheManifestPath = path.join(cacheDir, 'manifest.json');
    this.manifest = this.loadManifest();
  }

  loadManifest() {
    if (fs.existsSync(this.cacheManifestPath)) {
      try {
        return JSON.parse(fs.readFileSync(this.cacheManifestPath, 'utf8'));
      } catch {
        return {};
      }
    }
    return {};
  }

  saveManifest() {
    fs.mkdirSync(this.cacheDir, { recursive: true });
    fs.writeFileSync(this.cacheManifestPath, JSON.stringify(this.manifest, null, 2), 'utf8');
  }

  computeHash(contentOrPath) {
    let content = contentOrPath;
    if (fs.existsSync(contentOrPath) && fs.statSync(contentOrPath).isFile()) {
      content = fs.readFileSync(contentOrPath);
    }
    return crypto.createHash('sha256').update(content).digest('hex');
  }

  isUpToDate(targetKey, inputFiles = []) {
    const record = this.manifest[targetKey];
    if (!record) return false;

    for (const file of inputFiles) {
      if (!fs.existsSync(file)) return false;
      const currentHash = this.computeHash(file);
      if (record.inputs[file] !== currentHash) return false;
    }
    return true;
  }

  recordBuild(targetKey, inputFiles = [], outputFiles = []) {
    const inputs = {};
    for (const f of inputFiles) {
      if (fs.existsSync(f)) {
        inputs[f] = this.computeHash(f);
      }
    }
    this.manifest[targetKey] = {
      inputs,
      outputs: outputFiles,
      timestamp: new Date().toISOString()
    };
    this.saveManifest();
  }

  invalidate(targetKey) {
    delete this.manifest[targetKey];
    this.saveManifest();
  }
}

// ============================================================================
// 4. DEBUG / RELEASE CONFIGS
// ============================================================================
export const BUILD_CONFIGS = {
  debug: {
    name: 'Debug',
    minify: false,
    sourceMaps: true,
    optimizeAssets: false,
    stripComments: false,
    assertions: true,
    diagnostics: 'verbose'
  },
  release: {
    name: 'Release',
    minify: true,
    sourceMaps: false,
    optimizeAssets: true,
    stripComments: true,
    assertions: false,
    diagnostics: 'standard'
  }
};

export function getBuildConfig(configName = 'debug') {
  const key = String(configName).toLowerCase();
  return BUILD_CONFIGS[key] || BUILD_CONFIGS.debug;
}

// ============================================================================
// 5. PARALLEL BUILD EXECUTOR
// ============================================================================
export class ParallelBuildExecutor {
  constructor(maxConcurrency = 4) {
    this.maxConcurrency = maxConcurrency;
  }

  async executeGraph(graph, context = {}) {
    const executionOrder = graph.getExecutionOrder();
    const completedTasks = new Set();
    const taskResults = new Map();
    const executing = new Map();

    const canRun = (taskId) => {
      const task = graph.getTask(taskId);
      return task.dependencies.every(d => completedTasks.has(d));
    };

    while (completedTasks.size < graph.tasks.size) {
      // Find eligible tasks that aren't executing yet
      for (const taskId of executionOrder) {
        if (!completedTasks.has(taskId) && !executing.has(taskId) && canRun(taskId)) {
          if (executing.size >= this.maxConcurrency) break;

          const task = graph.getTask(taskId);
          const promise = Promise.resolve(task.action(context)).then(result => {
            executing.delete(taskId);
            completedTasks.add(taskId);
            taskResults.set(taskId, result);
          });
          executing.set(taskId, promise);
        }
      }

      if (executing.size === 0 && completedTasks.size < graph.tasks.size) {
        throw new Error('Build execution deadlock: No tasks eligible to run');
      }

      // Await first completing task
      await Promise.race(executing.values());
    }

    return {
      completed: Array.from(completedTasks),
      results: taskResults
    };
  }
}

// ============================================================================
// 7. STARTUP PROJECT SELECTION
// ============================================================================
export class StartupProjectManager {
  constructor(solutionPath = 'workspace.solution.json') {
    this.solutionPath = solutionPath;
    this.startupProject = null;
  }

  load() {
    if (fs.existsSync(this.solutionPath)) {
      try {
        const data = JSON.parse(fs.readFileSync(this.solutionPath, 'utf8'));
        this.startupProject = data.startupProject || null;
      } catch {}
    }
    return this.startupProject;
  }

  setStartupProject(projectName) {
    this.startupProject = projectName;
    let data = {};
    if (fs.existsSync(this.solutionPath)) {
      try {
        data = JSON.parse(fs.readFileSync(this.solutionPath, 'utf8'));
      } catch {}
    }
    data.startupProject = projectName;
    fs.writeFileSync(this.solutionPath, JSON.stringify(data, null, 2), 'utf8');
    return this.startupProject;
  }
}

// ============================================================================
// 8. PERSIST LAUNCH SETTINGS (.otter/launch.json)
// ============================================================================
export class LaunchSettingsManager {
  constructor(settingsPath = '.otter/launch.json') {
    this.settingsPath = settingsPath;
    this.profiles = new Map();
    this.load();
  }

  load() {
    if (fs.existsSync(this.settingsPath)) {
      try {
        const raw = fs.readFileSync(this.settingsPath, 'utf8');
        const data = JSON.parse(raw);
        if (data.profiles && typeof data.profiles === 'object') {
          for (const [key, val] of Object.entries(data.profiles)) {
            this.profiles.set(key, val);
          }
        }
      } catch {}
    }
  }

  save() {
    const dir = path.dirname(this.settingsPath);
    if (dir && dir !== '.') fs.mkdirSync(dir, { recursive: true });

    const obj = {
      version: '1.0',
      profiles: Object.fromEntries(this.profiles.entries())
    };
    fs.writeFileSync(this.settingsPath, JSON.stringify(obj, null, 2), 'utf8');
  }

  setProfile(name, config) {
    this.profiles.set(name, config);
    this.save();
    return config;
  }

  getProfile(name) {
    return this.profiles.get(name) || null;
  }

  listProfiles() {
    return Array.from(this.profiles.entries()).map(([name, config]) => ({ name, ...config }));
  }

  deleteProfile(name) {
    const res = this.profiles.delete(name);
    this.save();
    return res;
  }
}
