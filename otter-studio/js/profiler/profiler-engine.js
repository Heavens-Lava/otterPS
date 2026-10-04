// profiler-engine.js - Performance Analysis, Trace Export & DevTools Engine for Otter Studio

export function formatBytes(bytes) {
  if (bytes === null || bytes === undefined || isNaN(bytes)) return '0 B';
  const sign = bytes < 0 ? '-' : '';
  const abs = Math.abs(bytes);
  if (abs >= 1073741824) return `${sign}${(abs / 1073741824).toFixed(1)} GB`;
  if (abs >= 1048576) return `${sign}${(abs / 1048576).toFixed(1)} MB`;
  if (abs >= 1024) return `${sign}${(abs / 1024).toFixed(1)} KB`;
  return `${sign}${Math.round(abs)} B`;
}

export function formatMs(ms) {
  if (ms === null || ms === undefined || isNaN(ms)) return '0.0 ms';
  return `${Number(ms).toFixed(2)} ms`;
}

export function normalizeProfile(raw) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('Invalid profile payload: expected object');
  }

  const p = (raw.profile && typeof raw.profile === 'object') ? raw.profile : ((raw.summary && typeof raw.summary === 'object') ? raw.summary : raw);
  const totalMs = Number(p.TotalMs || p.totalMs || 0);
  const totalAlloc = Number(p.TotalAllocatedBytes || p.totalAllocatedBytes || 0);
  const totalCpuMs = Number(p.TotalCpuMs || p.totalCpuMs || 0);

  const rawFunctions = Array.isArray(raw.functions) ? raw.functions : (Array.isArray(p.Functions || p.functions) ? (p.Functions || p.functions) : []);
  const functions = rawFunctions.map(f => {
    const calls = Number(f.Calls || f.calls || 0);
    const fTotalMs = Number(f.TotalMs || f.totalMs || 0);
    const fSelfMs = Number(f.SelfMs || f.selfMs || 0);
    const fTotalCpuMs = Number(f.TotalCpuMs || f.totalCpuMs || 0);
    const fSelfCpuMs = Number(f.SelfCpuMs || f.selfCpuMs || 0);
    const fTotalAlloc = Number(f.TotalAllocatedBytes || f.totalAllocatedBytes || 0);
    const fSelfAlloc = Number(f.SelfAllocatedBytes || f.selfAllocatedBytes || 0);

    return {
      name: String(f.Function || f.name || 'anonymous'),
      calls,
      totalMs: fTotalMs,
      selfMs: fSelfMs,
      totalCpuMs: fTotalCpuMs,
      selfCpuMs: fSelfCpuMs,
      totalAllocatedBytes: fTotalAlloc,
      selfAllocatedBytes: fSelfAlloc,
      totalMsPct: totalMs > 0 ? Number(((fTotalMs / totalMs) * 100).toFixed(1)) : 0,
      selfMsPct: totalMs > 0 ? Number(((fSelfMs / totalMs) * 100).toFixed(1)) : 0,
      allocPct: totalAlloc > 0 ? Number(((fTotalAlloc / totalAlloc) * 100).toFixed(1)) : 0,
      avgSelfMsPerCall: calls > 0 ? Number((fSelfMs / calls).toFixed(3)) : 0,
      avgBytesPerCall: calls > 0 ? Math.round(fSelfAlloc / calls) : 0,
      allocatedFormatted: formatBytes(fTotalAlloc)
    };
  });

  const rawLines = Array.isArray(raw.lines) ? raw.lines : (Array.isArray(p.Lines || p.lines) ? (p.Lines || p.lines) : []);
  const lines = rawLines.map(l => {
    const hits = Number(l.Hits || l.hits || 0);
    const lSelfMs = Number(l.SelfMs || l.selfMs || 0);
    const lCpuMs = Number(l.CpuMs || l.cpuMs || 0);
    const lAlloc = Number(l.AllocatedBytes || l.allocatedBytes || 0);

    return {
      line: Number(l.Line || l.line || 0),
      hits,
      selfMs: lSelfMs,
      cpuMs: lCpuMs,
      allocatedBytes: lAlloc,
      selfMsPct: totalMs > 0 ? Number(((lSelfMs / totalMs) * 100).toFixed(1)) : 0,
      allocPct: totalAlloc > 0 ? Number(((lAlloc / totalAlloc) * 100).toFixed(1)) : 0,
      allocatedFormatted: formatBytes(lAlloc),
      source: String(l.Source || l.source || '').trim()
    };
  });

  // Hot paths: top 5 by self time
  const hotLines = [...lines].sort((a, b) => b.selfMs - a.selfMs).slice(0, 5);
  const hotFunctions = [...functions].sort((a, b) => b.selfMs - a.selfMs).slice(0, 5);

  return {
    ok: raw.ok !== false,
    exitCode: Number(raw.exitCode || 0),
    error: raw.error || null,
    output: Array.isArray(raw.output) ? raw.output : [],
    summary: {
      statements: Number(p.Statements || p.statements || 0),
      totalMs,
      totalCpuMs,
      userCpuMs: Number(p.UserCpuMs || p.userCpuMs || 0),
      kernelCpuMs: Number(p.KernelCpuMs || p.kernelCpuMs || 0),
      cpuUtilization: Number(p.CpuUtilization || p.cpuUtilization || 0),
      peakManagedBytes: Number(p.PeakManagedBytes || p.peakManagedBytes || 0),
      peakManagedFormatted: p.PeakManagedFormatted || formatBytes(p.PeakManagedBytes || 0),
      managedDeltaBytes: Number(p.ManagedDeltaBytes || p.managedDeltaBytes || 0),
      managedDeltaFormatted: p.ManagedDeltaFormatted || formatBytes(p.ManagedDeltaBytes || 0),
      totalAllocatedBytes: totalAlloc,
      totalAllocatedFormatted: p.TotalAllocatedFormatted || formatBytes(totalAlloc),
      workingSetBytes: Number(p.WorkingSetBytes || p.workingSetBytes || 0),
      peakWorkingSetBytes: Number(p.PeakWorkingSetBytes || p.peakWorkingSetBytes || 0),
      peakWorkingSetFormatted: p.PeakWorkingSetFormatted || formatBytes(p.PeakWorkingSetBytes || 0),
      workingSetDeltaBytes: Number(p.WorkingSetDeltaBytes || p.workingSetDeltaBytes || 0),
      gen0Collections: Number(p.Gen0Collections || p.gen0Collections || 0),
      gen1Collections: Number(p.Gen1Collections || p.gen1Collections || 0),
      gen2Collections: Number(p.Gen2Collections || p.gen2Collections || 0),
      mainMs: Number(p.MainMs || p.mainMs || 0),
      mainCpuMs: Number(p.MainCpuMs || p.mainCpuMs || 0)
    },
    functions,
    lines,
    hotLines,
    hotFunctions
  };
}

export function analyzeFrameTiming(profile, options = {}) {
  const targetFps = options.targetFps || 60;
  const targetFrameBudgetMs = 1000 / targetFps; // e.g. 16.666 ms
  const totalMs = profile.summary ? profile.summary.totalMs : (profile.totalMs || 0);

  // If a loop or animation ran, compute estimated frame consumption
  const budgetUtilizationPct = totalMs > 0 ? Number(((totalMs / targetFrameBudgetMs) * 100).toFixed(1)) : 0;
  const estimatedMaxFps = totalMs > 0 ? Number(Math.min(targetFps, 1000 / totalMs).toFixed(1)) : targetFps;

  let status = 'well-within-budget';
  if (budgetUtilizationPct > 100) {
    status = 'over-budget';
  } else if (budgetUtilizationPct > 75) {
    status = 'tight';
  }

  return {
    targetFps,
    targetFrameBudgetMs: Number(targetFrameBudgetMs.toFixed(2)),
    measuredDurationMs: totalMs,
    budgetUtilizationPct,
    estimatedMaxFps,
    status,
    is60FpsCapable: totalMs <= targetFrameBudgetMs
  };
}

export function exportProfileTrace(normalized, metadata = {}) {
  return JSON.stringify({
    schema: 'otter-profile-v1',
    exportedAt: new Date().toISOString(),
    metadata: {
      sourceFile: metadata.sourceFile || 'scratch.ot',
      project: metadata.project || 'Otter Application',
      runtime: 'Windows PowerShell 5.1 / Otter PS Interpreter',
      ...metadata
    },
    profile: normalized
  }, null, 2);
}

export function importProfileTrace(jsonString) {
  const parsed = typeof jsonString === 'string' ? JSON.parse(jsonString) : jsonString;
  if (!parsed || parsed.schema !== 'otter-profile-v1' || !parsed.profile) {
    throw new Error('Invalid Otter profile trace: missing schema otter-profile-v1');
  }
  return {
    metadata: parsed.metadata || {},
    exportedAt: parsed.exportedAt,
    profile: normalizeProfile(parsed.profile)
  };
}

export function compareProfiles(baseline, current) {
  const b = baseline.summary || baseline;
  const c = current.summary || current;

  const totalMsDelta = Number((c.totalMs - b.totalMs).toFixed(2));
  const totalMsPctChange = b.totalMs > 0 ? Number(((totalMsDelta / b.totalMs) * 100).toFixed(1)) : 0;

  const cpuDelta = Number((c.totalCpuMs - b.totalCpuMs).toFixed(2));
  const allocDelta = (c.totalAllocatedBytes || 0) - (b.totalAllocatedBytes || 0);
  const statementsDelta = (c.statements || 0) - (b.statements || 0);

  // Function deltas
  const bFuncs = new Map((baseline.functions || []).map(f => [f.name, f]));
  const cFuncs = new Map((current.functions || []).map(f => [f.name, f]));

  const allFuncNames = new Set([...bFuncs.keys(), ...cFuncs.keys()]);
  const functionDeltas = [];

  for (const name of allFuncNames) {
    const bf = bFuncs.get(name) || { calls: 0, selfMs: 0, totalMs: 0, totalAllocatedBytes: 0 };
    const cf = cFuncs.get(name) || { calls: 0, selfMs: 0, totalMs: 0, totalAllocatedBytes: 0 };

    const selfMsDelta = Number((cf.selfMs - bf.selfMs).toFixed(2));
    const callsDelta = cf.calls - bf.calls;

    functionDeltas.push({
      name,
      baselineCalls: bf.calls,
      currentCalls: cf.calls,
      callsDelta,
      baselineSelfMs: bf.selfMs,
      currentSelfMs: cf.selfMs,
      selfMsDelta,
      baselineAllocBytes: bf.totalAllocatedBytes,
      currentAllocBytes: cf.totalAllocatedBytes,
      allocBytesDelta: cf.totalAllocatedBytes - bf.totalAllocatedBytes
    });
  }

  let status = 'neutral';
  if (totalMsPctChange <= -5) status = 'improved';
  else if (totalMsPctChange >= 5) status = 'regressed';

  return {
    status,
    totalMsDelta,
    totalMsPctChange,
    cpuDelta,
    allocDelta,
    allocDeltaFormatted: formatBytes(allocDelta),
    statementsDelta,
    functionDeltas
  };
}
