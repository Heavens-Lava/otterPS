import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const architectureDir = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(architectureDir, '..', '..');
const exportDir = path.join(architectureDir, 'exported');

const PLATFORM_CHECKLIST = path.join(repoRoot, 'OTTER_PROGRAMMING_LANGUAGE_COMPLETE_PLATFORM_CHECKLIST.md');
const STUDIO_CHECKLIST = path.join(repoRoot, 'OTTER_STUDIO_PROFESSIONAL_IDE_MASTER_CHECKLIST.md');

function readChecklist(filePath, expectedTitle) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing architecture source: ${path.basename(filePath)}`);
  }
  const text = fs.readFileSync(filePath, 'utf8');
  if (!text.includes(expectedTitle)) {
    throw new Error(`${path.basename(filePath)} does not contain its expected title.`);
  }
  return {
    text,
    total: (text.match(/^\s*-\s+\[[ xX]\]/gm) || []).length,
    complete: (text.match(/^\s*-\s+\[[xX]\]/gm) || []).length
  };
}

const platformChecklist = readChecklist(PLATFORM_CHECKLIST, 'Complete Application Platform Master Checklist');
const studioChecklist = readChecklist(STUDIO_CHECKLIST, 'Professional IDE Master Requirements');

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function escapeLabel(value) {
  return escapeXml(value).replaceAll('\n', '&lt;br&gt;');
}

function diagram(name, width = 1800, height = 1120) {
  let nextId = 2;
  const cells = [];

  function vertex(label, x, y, w, h, options = {}) {
    const id = String(nextId++);
    const style = [
      'rounded=1',
      'whiteSpace=wrap',
      'html=1',
      'fontFamily=Segoe UI',
      'fontSize=15',
      'align=center',
      'verticalAlign=middle',
      'strokeWidth=2',
      `fillColor=${options.fill || '#ffffff'}`,
      `strokeColor=${options.stroke || '#64748b'}`,
      `fontColor=${options.font || '#0f172a'}`,
      options.dashed ? 'dashed=1' : '',
      options.shadow ? 'shadow=1' : '',
      options.extra || ''
    ].filter(Boolean).join(';') + ';';
    cells.push(
      `<mxCell id="${id}" value="${escapeLabel(label)}" style="${style}" vertex="1" parent="1">` +
      `<mxGeometry x="${x}" y="${y}" width="${w}" height="${h}" as="geometry"/>` +
      '</mxCell>'
    );
    return id;
  }

  function label(text, x, y, w, h, options = {}) {
    return vertex(text, x, y, w, h, {
      fill: options.fill || 'none',
      stroke: options.stroke || 'none',
      font: options.font || '#0f172a',
      extra: `fontSize=${options.size || 18};fontStyle=${options.bold === false ? 0 : 1};align=${options.align || 'left'};${options.extra || ''}`
    });
  }

  function edge(source, target, text = '', options = {}) {
    const id = String(nextId++);
    const style = [
      'edgeStyle=orthogonalEdgeStyle',
      'rounded=1',
      'orthogonalLoop=1',
      'jettySize=auto',
      'html=1',
      'endArrow=block',
      'endFill=1',
      'strokeWidth=2',
      `strokeColor=${options.color || '#64748b'}`,
      options.dashed ? 'dashed=1' : '',
      options.bidirectional ? 'startArrow=block;startFill=1' : ''
    ].filter(Boolean).join(';') + ';';
    cells.push(
      `<mxCell id="${id}" value="${escapeXml(text)}" style="${style}" edge="1" parent="1" source="${source}" target="${target}">` +
      '<mxGeometry relative="1" as="geometry"/>' +
      '</mxCell>'
    );
    return id;
  }

  function xml() {
    return `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<mxfile host="Electron" agent="Otter architecture builder" version="31.4.5">\n` +
      `  <diagram id="${escapeXml(name.toLowerCase().replace(/[^a-z0-9]+/g, '-'))}" name="${escapeXml(name)}">\n` +
      `    <mxGraphModel dx="1800" dy="1120" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${width}" pageHeight="${height}" background="#f8fafc" math="0" shadow="0">\n` +
      '      <root>\n' +
      '        <mxCell id="0"/>\n' +
      '        <mxCell id="1" parent="0"/>\n' +
      cells.map(cell => `        ${cell}`).join('\n') + '\n' +
      '      </root>\n' +
      '    </mxGraphModel>\n' +
      '  </diagram>\n' +
      '</mxfile>\n';
  }

  return { vertex, label, edge, xml };
}

function buildMasterArchitecture() {
  const d = diagram('Otter Platform Master Architecture', 1800, 1080);

  // Large architectural bands establish hierarchy before the individual
  // nodes are added. Keeping cross-band connectors to a minimum makes this
  // useful as a platform map rather than a wiring schematic.
  d.vertex('', 25, 145, 1750, 145, { fill: '#f8fafc', stroke: '#cbd5e1', extra: 'arcSize=18;' });
  d.vertex('', 25, 310, 1750, 205, { fill: '#faf5ff', stroke: '#d8b4fe', extra: 'arcSize=18;' });
  d.vertex('', 25, 535, 1750, 235, { fill: '#f8fafc', stroke: '#cbd5e1', extra: 'arcSize=18;' });
  d.vertex('', 25, 790, 1750, 245, { fill: '#fffbeb', stroke: '#fed7aa', extra: 'arcSize=18;' });

  d.vertex(
    '<div style="text-align:left"><b style="font-size:28px">OTTER PLATFORM MASTER ARCHITECTURE</b><br><span style="font-size:16px;color:#cbd5e1">Readable language · shared frontend · provider-backed applications</span></div>',
    25, 20, 1750, 105,
    { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' }
  );
  d.vertex(
    `<div><b>LIVE CERTIFICATION</b><br><span style="font-size:18px">${platformChecklist.complete}/${platformChecklist.total}</span> platform &nbsp;·&nbsp; <span style="font-size:18px">${studioChecklist.complete}/${studioChecklist.total}</span> Studio</div>`,
    1285, 37, 450, 70,
    { fill: '#172554', stroke: '#60a5fa', font: '#ffffff', extra: 'strokeWidth=1;' }
  );

  d.label('01  AUTHORING & DEVELOPER EXPERIENCE', 50, 157, 620, 28, { size: 16, font: '#1d4ed8' });
  d.label('Clients consume the same Otter source, frontend, and semantic services.', 1050, 157, 680, 28, { size: 13, bold: false, align: 'right', font: '#64748b' });
  d.vertex('<b>Otter Studio</b><br><span style="font-size:13px;color:#475569">Editor · Designer · Terminal · Debugger</span>', 65, 200, 310, 65, { fill: '#eff6ff', stroke: '#2563eb', shadow: true });
  d.vertex('<b>VS Code Extension</b><br><span style="font-size:13px;color:#475569">Highlighting · Language Service</span>', 410, 200, 310, 65, { fill: '#eff6ff', stroke: '#2563eb' });
  d.vertex('<b>CLI & REPL</b><br><span style="font-size:13px;color:#475569">run · check · web · desktop · serve</span>', 755, 200, 330, 65, { fill: '#eff6ff', stroke: '#2563eb' });
  d.vertex('<b>Architecture Sources</b><br><span style="font-size:13px;color:#7c2d12">Platform + Studio checklists · release gates</span>', 1190, 200, 520, 65, { fill: '#fff7ed', stroke: '#f59e0b' });

  d.label('02  SHARED LANGUAGE CORE', 50, 322, 500, 28, { size: 16, font: '#7e22ce' });
  d.label('One deterministic frontend serves every execution target and editor client.', 1000, 322, 730, 28, { size: 13, bold: false, align: 'right', font: '#64748b' });
  const source = d.vertex('<b>Otter Source</b><br><span style="font-size:13px">main.ot + modules</span>', 55, 385, 190, 80, { fill: '#dbeafe', stroke: '#0284c7', shadow: true });
  const moduleResolver = d.vertex('<b>Module Resolver</b><br><span style="font-size:13px">source graph + map</span>', 285, 385, 225, 80, { fill: '#ffffff', stroke: '#9333ea' });
  const lexer = d.vertex('<b>Lexer</b><br><span style="font-size:13px">source → Token[]</span>', 550, 385, 190, 80, { fill: '#ffffff', stroke: '#9333ea' });
  const parser = d.vertex('<b>Parser + Contract</b><br><span style="font-size:13px">tokens → typed AST</span>', 780, 375, 250, 100, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const semantics = d.vertex('<b>Semantic Services</b><br><span style="font-size:13px">symbols · diagnostics · scopes</span>', 1070, 385, 285, 80, { fill: '#ffffff', stroke: '#9333ea' });
  const tests = d.vertex('<b>Conformance & Tests</b><br><span style="font-size:13px">frontend · runtime · targets · dogfood</span>', 1395, 385, 325, 80, { fill: '#f0fdf4', stroke: '#16a34a' });

  d.label('03  EXECUTION & COMPILATION', 50, 547, 520, 28, { size: 16, font: '#047857' });
  d.vertex('', 55, 590, 815, 145, { fill: '#ecfdf5', stroke: '#a7f3d0', extra: 'arcSize=18;' });
  d.vertex('', 905, 590, 815, 145, { fill: '#fff7ed', stroke: '#fed7aa', extra: 'arcSize=18;' });
  d.label('DIRECT EXECUTION', 75, 600, 240, 25, { size: 13, font: '#047857' });
  d.label('COMPILED APPLICATION', 925, 600, 280, 25, { size: 13, font: '#b45309' });
  const interpreter = d.vertex('<b>Interpreter</b><br><span style="font-size:12px">executes ProgramNode</span>', 80, 640, 215, 65, { fill: '#ffffff', stroke: '#059669' });
  const runtime = d.vertex('<b>Runtime + Library</b><br><span style="font-size:12px">values · files · JSON · processes</span>', 330, 630, 275, 85, { fill: '#d1fae5', stroke: '#047857', shadow: true });
  const providers = d.vertex('<b>Native Providers</b><br><span style="font-size:12px">UI · filesystem · process · HTTP</span>', 640, 640, 205, 65, { fill: '#ffffff', stroke: '#059669' });
  const jsCompiler = d.vertex('<b>JavaScript Compiler</b><br><span style="font-size:12px">AST → generated program</span>', 930, 640, 225, 65, { fill: '#ffffff', stroke: '#d97706' });
  const artifact = d.vertex('<b>Application Artifact</b><br><span style="font-size:12px">HTML · CSS · JavaScript</span>', 1190, 640, 225, 65, { fill: '#ffffff', stroke: '#d97706' });
  const bridge = d.vertex('<b>Target Runtime / Bridge</b><br><span style="font-size:12px">browser APIs · authenticated host</span>', 1450, 630, 245, 85, { fill: '#ffedd5', stroke: '#ea580c', shadow: true });

  d.label('04  APPLICATION TARGETS & HOSTS', 50, 802, 600, 28, { size: 16, font: '#b45309' });
  const consoleTarget = d.vertex('<b>Console & Automation</b><br><span style="font-size:12px">direct runtime</span>', 55, 855, 280, 75, { fill: '#ffffff', stroke: '#d97706' });
  const webTarget = d.vertex('<b>Web Applications</b><br><span style="font-size:12px">browser runtime</span>', 370, 855, 280, 75, { fill: '#ffffff', stroke: '#d97706' });
  const desktopTarget = d.vertex('<b>Desktop Applications</b><br><span style="font-size:12px">native host + bridge</span>', 685, 855, 280, 75, { fill: '#ffffff', stroke: '#d97706' });
  const serverTarget = d.vertex('<b>Server / API</b><br><span style="font-size:12px">HTTP routes + JSON</span>', 1000, 855, 280, 75, { fill: '#ffffff', stroke: '#d97706' });
  const futureTarget = d.vertex('<b>Future Targets</b><br><span style="font-size:12px">Game · Mobile · 3D · Compute</span>', 1315, 855, 405, 75, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  d.vertex('<b>WINDOWS</b> · Primary V1 host', 110, 960, 360, 42, { fill: '#eff6ff', stroke: '#2563eb', font: '#1e3a8a', extra: 'fontSize=13;' });
  d.vertex('<b>macOS</b> · Planned certification', 650, 960, 360, 42, { fill: '#ffffff', stroke: '#94a3b8', font: '#475569', dashed: true, extra: 'fontSize=13;' });
  d.vertex('<b>Linux</b> · Planned certification', 1190, 960, 360, 42, { fill: '#ffffff', stroke: '#94a3b8', font: '#475569', dashed: true, extra: 'fontSize=13;' });

  d.edge(source, moduleResolver);
  d.edge(moduleResolver, lexer);
  d.edge(lexer, parser);
  d.edge(parser, semantics);
  d.edge(semantics, tests, '', { color: '#16a34a' });
  d.edge(interpreter, runtime);
  d.edge(runtime, providers);
  d.edge(jsCompiler, artifact);
  d.edge(artifact, bridge);

  d.label('CURRENT', 60, 930, 120, 24, { size: 11, font: '#16a34a' });
  d.label('PLANNED / REQUIRES CERTIFICATION', 1380, 930, 330, 24, { size: 11, font: '#64748b', align: 'right' });
  return d.xml();
}

function buildCompilerPipeline() {
  const d = diagram('Source to Application Pipeline', 1800, 1050);
  d.label('SOURCE-TO-APPLICATION PIPELINE', 40, 25, 1100, 48, { size: 28 });
  d.label('One Otter frontend, two production paths, provider-owned capabilities', 40, 70, 1100, 32, { size: 16, bold: false, font: '#475569' });

  const source = d.vertex('main.ot', 60, 180, 180, 85, { fill: '#dbeafe', stroke: '#0284c7', shadow: true });
  const modules = d.vertex('Module Resolver\nuse graph + source map', 300, 170, 260, 105, { fill: '#faf5ff', stroke: '#9333ea' });
  const lexer = d.vertex('Lexer\nToken[]', 620, 180, 210, 85, { fill: '#faf5ff', stroke: '#9333ea' });
  const parser = d.vertex('Parser\nProgramNode AST', 890, 170, 260, 105, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const validation = d.vertex('Diagnostics + Symbols\nsource-aware analysis', 1220, 170, 280, 105, { fill: '#eff6ff', stroke: '#2563eb' });

  d.edge(source, modules);
  d.edge(modules, lexer);
  d.edge(lexer, parser);
  d.edge(parser, validation);

  d.label('DIRECT EXECUTION PATH', 120, 355, 500, 30, { size: 17, font: '#047857' });
  const interpreter = d.vertex('PowerShell Interpreter\nAST execution', 160, 410, 280, 100, { fill: '#d1fae5', stroke: '#047857' });
  const runtime = d.vertex('Otter Runtime + Library\nvalues · scope · files · JSON · processes', 520, 400, 360, 120, { fill: '#d1fae5', stroke: '#047857', shadow: true });
  const nativeProviders = d.vertex('Native Providers\nconsole · WPF UI · filesystem · process · HTTP', 960, 400, 380, 120, { fill: '#ecfdf5', stroke: '#059669' });

  d.edge(parser, interpreter);
  d.edge(interpreter, runtime);
  d.edge(runtime, nativeProviders);

  d.label('COMPILED APPLICATION PATH', 120, 600, 560, 30, { size: 17, font: '#b45309' });
  const compiler = d.vertex('JavaScript Compiler\nAST → generated program', 160, 655, 300, 105, { fill: '#fffbeb', stroke: '#d97706' });
  const artifact = d.vertex('Application Artifact\nHTML · CSS · JavaScript', 540, 655, 300, 105, { fill: '#fffbeb', stroke: '#d97706' });
  const bridge = d.vertex('Target Runtime / Bridge\nbrowser APIs or authenticated desktop bridge', 920, 645, 390, 125, { fill: '#fff7ed', stroke: '#ea580c', shadow: true });

  d.edge(parser, compiler);
  d.edge(compiler, artifact);
  d.edge(artifact, bridge);

  d.label('DELIVERED APPLICATIONS', 1370, 355, 360, 30, { size: 17, font: '#1d4ed8' });
  const consoleApp = d.vertex('Console / Automation', 1410, 410, 280, 75, { fill: '#eff6ff', stroke: '#2563eb' });
  const desktopApp = d.vertex('Desktop Application', 1410, 515, 280, 75, { fill: '#eff6ff', stroke: '#2563eb' });
  const webApp = d.vertex('Web Application', 1410, 650, 280, 75, { fill: '#eff6ff', stroke: '#2563eb' });
  const apiApp = d.vertex('Server / API', 1410, 755, 280, 75, { fill: '#eff6ff', stroke: '#2563eb' });

  d.edge(nativeProviders, consoleApp);
  d.edge(nativeProviders, desktopApp);
  d.edge(nativeProviders, apiApp);
  d.edge(bridge, webApp);
  d.edge(bridge, desktopApp);

  const gate = d.vertex('Certification gate\nimplementation → tests → dogfood → production entry point → host certification', 300, 880, 1200, 85, { fill: '#f0fdf4', stroke: '#16a34a' });
  return d.xml();
}

function buildStudioArchitecture() {
  const d = diagram('Otter Studio Internal Architecture', 1800, 1080);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">OTTER STUDIO INTERNAL ARCHITECTURE</b><br><span style="font-size:16px;color:#cbd5e1">A professional workbench built on shared Otter services</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });

  d.vertex('', 25, 145, 1750, 175, { fill: '#eff6ff', stroke: '#bfdbfe' });
  d.label('01  WORKBENCH SURFACE', 50, 157, 430, 28, { size: 16, font: '#1d4ed8' });
  const explorer = d.vertex('<b>Explorer</b><br><span style="font-size:12px">projects · files · assets</span>', 55, 215, 260, 70, { fill: '#ffffff', stroke: '#2563eb' });
  const editor = d.vertex('<b>Source Editor</b><br><span style="font-size:12px">tabs · syntax · diagnostics</span>', 345, 205, 290, 90, { fill: '#dbeafe', stroke: '#2563eb', shadow: true });
  const designer = d.vertex('<b>UI Designer</b><br><span style="font-size:12px">canvas · hierarchy · toolbox</span>', 665, 205, 290, 90, { fill: '#dbeafe', stroke: '#2563eb', shadow: true });
  const inspector = d.vertex('<b>Inspector</b><br><span style="font-size:12px">properties · events · variables</span>', 985, 215, 280, 70, { fill: '#ffffff', stroke: '#2563eb' });
  const panels = d.vertex('<b>Output Workbench</b><br><span style="font-size:12px">problems · output · terminal · tests</span>', 1295, 215, 425, 70, { fill: '#ffffff', stroke: '#2563eb' });

  d.vertex('', 25, 340, 1750, 180, { fill: '#faf5ff', stroke: '#d8b4fe' });
  d.label('02  COORDINATION & SHARED SERVICES', 50, 352, 600, 28, { size: 16, font: '#7e22ce' });
  const workbench = d.vertex('<b>Workbench Controller</b><br><span style="font-size:12px">commands · document state · panels</span>', 90, 410, 330, 75, { fill: '#ffffff', stroke: '#9333ea' });
  const project = d.vertex('<b>Project / Workspace</b><br><span style="font-size:12px">tree · paths · configuration</span>', 460, 410, 300, 75, { fill: '#ffffff', stroke: '#9333ea' });
  const language = d.vertex('<b>Otter Language Service</b><br><span style="font-size:12px">symbols · diagnostics · navigation</span>', 800, 400, 340, 95, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const model = d.vertex('<b>UI Model Service</b><br><span style="font-size:12px">canonical tree · mutations · source sync</span>', 1180, 400, 340, 95, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const commands = d.vertex('<b>Command Bus</b><br><span style="font-size:12px">run · build · save · debug</span>', 1560, 410, 170, 75, { fill: '#ffffff', stroke: '#9333ea' });

  d.vertex('', 25, 540, 1750, 220, { fill: '#ecfdf5', stroke: '#a7f3d0' });
  d.label('03  ENGINES & INTEGRATIONS', 50, 552, 520, 28, { size: 16, font: '#047857' });
  const frontend = d.vertex('<b>Real Otter Frontend</b><br><span style="font-size:12px">module resolver · lexer · parser · AST</span>', 60, 620, 320, 90, { fill: '#ffffff', stroke: '#059669', shadow: true });
  const roundtrip = d.vertex('<b>Designer Round Trip</b><br><span style="font-size:12px">parse · model · generate · verify</span>', 415, 620, 300, 90, { fill: '#ffffff', stroke: '#059669' });
  const buildRun = d.vertex('<b>Build / Run Service</b><br><span style="font-size:12px">console · web · desktop · server</span>', 750, 620, 300, 90, { fill: '#ffffff', stroke: '#059669' });
  const terminal = d.vertex('<b>Terminal / Process</b><br><span style="font-size:12px">PTY · stdout · stderr · exit code</span>', 1085, 620, 300, 90, { fill: '#ffffff', stroke: '#059669' });
  d.vertex('<b>Debugger + Tests</b><br><span style="font-size:12px">planned professional services</span>', 1420, 620, 300, 90, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });

  d.vertex('', 25, 780, 1750, 250, { fill: '#fff7ed', stroke: '#fed7aa' });
  d.label('04  RUNTIMES, HOSTS & ECOSYSTEM', 50, 792, 620, 28, { size: 16, font: '#b45309' });
  const runtime = d.vertex('<b>Otter Runtime</b><br><span style="font-size:12px">interpreter · standard library</span>', 60, 860, 285, 80, { fill: '#ffffff', stroke: '#d97706' });
  const compiler = d.vertex('<b>JavaScript Compiler</b><br><span style="font-size:12px">web application artifacts</span>', 380, 860, 285, 80, { fill: '#ffffff', stroke: '#d97706' });
  const bridge = d.vertex('<b>Desktop Host Bridge</b><br><span style="font-size:12px">authenticated host capabilities</span>', 700, 850, 315, 100, { fill: '#ffedd5', stroke: '#ea580c', shadow: true });
  const gitPackages = d.vertex('<b>Git · Packages · Extensions</b><br><span style="font-size:12px">planned ecosystem integrations</span>', 1050, 860, 325, 80, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  const hosts = d.vertex('<b>Windows Host</b><br><span style="font-size:12px">browser · native UI · filesystem · processes</span>', 1410, 850, 310, 100, { fill: '#eff6ff', stroke: '#2563eb' });

  d.edge(explorer, project);
  d.edge(editor, language);
  d.edge(designer, model);
  d.edge(inspector, model);
  d.edge(panels, workbench);
  d.edge(workbench, commands);
  d.edge(language, frontend);
  d.edge(model, roundtrip);
  d.edge(commands, buildRun);
  d.edge(commands, terminal);
  d.edge(buildRun, runtime);
  d.edge(buildRun, compiler);
  d.edge(terminal, bridge);
  d.edge(runtime, hosts);
  d.edge(compiler, hosts);
  d.edge(bridge, hosts);
  return d.xml();
}

function buildDesignerRoundTrip() {
  const d = diagram('UI Designer Round-Trip Architecture', 1800, 980);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">UI DESIGNER ROUND-TRIP ARCHITECTURE</b><br><span style="font-size:16px;color:#cbd5e1">Visual edits remain real Otter source, compiled by the real pipeline</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });

  d.label('SOURCE → MODEL → DESIGNER', 55, 160, 600, 30, { size: 16, font: '#7e22ce' });
  const source = d.vertex('<b>.ot UI Source</b><br><span style="font-size:12px">canonical authoring format</span>', 55, 220, 240, 90, { fill: '#dbeafe', stroke: '#0284c7', shadow: true });
  const parser = d.vertex('<b>Real Parser / AST</b><br><span style="font-size:12px">same frontend used by builds</span>', 355, 220, 260, 90, { fill: '#f3e8ff', stroke: '#7e22ce' });
  const uiModel = d.vertex('<b>Otter UI Model</b><br><span style="font-size:12px">resources · properties · hierarchy · events</span>', 675, 210, 310, 110, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const designer = d.vertex('<b>Designer Workbench</b><br><span style="font-size:12px">canvas · toolbox · hierarchy · inspector</span>', 1045, 210, 320, 110, { fill: '#eff6ff', stroke: '#2563eb', shadow: true });
  const preview = d.vertex('<b>DOM + CSS Preview</b><br><span style="font-size:12px">interactive design renderer</span>', 1425, 220, 300, 90, { fill: '#eff6ff', stroke: '#2563eb' });
  d.edge(source, parser);
  d.edge(parser, uiModel);
  d.edge(uiModel, designer, '', { bidirectional: true, color: '#7e22ce' });
  d.edge(designer, preview, '', { bidirectional: true, color: '#2563eb' });

  d.vertex('', 25, 380, 1750, 270, { fill: '#ecfdf5', stroke: '#a7f3d0' });
  d.label('VISUAL EDIT → CANONICAL SOURCE', 55, 395, 650, 30, { size: 16, font: '#047857' });
  const gesture = d.vertex('<b>Drag / Drop / Edit</b><br><span style="font-size:12px">one explicit user operation</span>', 60, 475, 250, 90, { fill: '#ffffff', stroke: '#059669' });
  const mutation = d.vertex('<b>Model Mutation</b><br><span style="font-size:12px">validated deterministic change</span>', 365, 475, 260, 90, { fill: '#ffffff', stroke: '#059669' });
  const generator = d.vertex('<b>Otter Generator</b><br><span style="font-size:12px">stable formatting + ordering</span>', 680, 475, 260, 90, { fill: '#ffffff', stroke: '#059669' });
  const canonical = d.vertex('<b>Canonical .ot</b><br><span style="font-size:12px">readable source saved to disk</span>', 995, 475, 260, 90, { fill: '#d1fae5', stroke: '#047857', shadow: true });
  const compiler = d.vertex('<b>Real Compiler</b><br><span style="font-size:12px">no designer-only renderer path</span>', 1310, 475, 260, 90, { fill: '#ffffff', stroke: '#059669' });
  const rendered = d.vertex('<b>Rendered UI</b><br><span style="font-size:12px">same behavior and structure</span>', 1625, 475, 120, 90, { fill: '#ffffff', stroke: '#059669' });
  d.edge(gesture, mutation);
  d.edge(mutation, generator);
  d.edge(generator, canonical);
  d.edge(canonical, compiler);
  d.edge(compiler, rendered);

  const gate = d.vertex('<b>ROUND-TRIP CERTIFICATION GATE</b><br><span style="font-size:14px">parse → model → generate → parse again → equivalent AST → equivalent rendered UI</span>', 250, 730, 1300, 105, { fill: '#f0fdf4', stroke: '#16a34a', shadow: true });
  d.vertex('<b>Rule:</b> the designer never invents private UI semantics. Unsupported edits remain explicit gaps.', 390, 865, 1020, 55, { fill: '#fff7ed', stroke: '#f59e0b', font: '#7c2d12' });
  return d.xml();
}

function buildRuntimeProviders() {
  const d = diagram('Runtime Capability and Provider Map', 1800, 1050);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">RUNTIME CAPABILITY & PROVIDER MAP</b><br><span style="font-size:16px;color:#cbd5e1">Stable Otter semantics above host-specific implementations</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });

  const semantics = d.vertex('<b>OTTER LANGUAGE SEMANTICS</b><br><span style="font-size:14px">values · scope · errors · objects · collections · dates · command results</span>', 260, 160, 1280, 90, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const contract = d.vertex('<b>CAPABILITY CONTRACTS</b><br><span style="font-size:14px">portable operation shape · validation · Otter-facing diagnostics</span>', 350, 300, 1100, 85, { fill: '#d1fae5', stroke: '#047857', shadow: true });
  d.edge(semantics, contract);

  d.label('PROVIDER IMPLEMENTATIONS', 50, 425, 500, 30, { size: 16, font: '#047857' });
  const file = d.vertex('<b>Filesystem</b><br><span style="font-size:12px">read · write · append · discover · mutate</span>', 45, 485, 270, 90, { fill: '#ffffff', stroke: '#059669' });
  const process = d.vertex('<b>Process / Shell</b><br><span style="font-size:12px">launch · streams · exit code · PTY</span>', 340, 485, 270, 90, { fill: '#ffffff', stroke: '#059669' });
  const http = d.vertex('<b>HTTP / Server</b><br><span style="font-size:12px">client · routes · JSON · status</span>', 635, 485, 270, 90, { fill: '#ffffff', stroke: '#059669' });
  const ui = d.vertex('<b>UI</b><br><span style="font-size:12px">resources · properties · events · layout</span>', 930, 485, 270, 90, { fill: '#ffffff', stroke: '#059669' });
  const system = d.vertex('<b>System Services</b><br><span style="font-size:12px">environment · clipboard · services · tasks</span>', 1225, 485, 270, 90, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  const data = d.vertex('<b>Data Providers</b><br><span style="font-size:12px">database · packages · FFI</span>', 1520, 485, 235, 90, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  for (const provider of [file, process, http, ui, system, data]) d.edge(contract, provider);

  d.vertex('', 25, 635, 1750, 340, { fill: '#f8fafc', stroke: '#cbd5e1' });
  d.label('HOST DELIVERY', 50, 650, 400, 30, { size: 16, font: '#1d4ed8' });
  d.vertex('<b>PowerShell Runtime</b><br><span style="font-size:12px">direct interpreter providers</span>', 70, 720, 300, 85, { fill: '#eff6ff', stroke: '#2563eb' });
  d.vertex('<b>Browser Runtime</b><br><span style="font-size:12px">portable JS + browser APIs</span>', 410, 720, 300, 85, { fill: '#eff6ff', stroke: '#2563eb' });
  d.vertex('<b>Desktop Bridge</b><br><span style="font-size:12px">authenticated native capabilities</span>', 750, 710, 320, 105, { fill: '#dbeafe', stroke: '#2563eb', shadow: true });
  d.vertex('<b>Server Host</b><br><span style="font-size:12px">HTTP listener + backend providers</span>', 1110, 720, 300, 85, { fill: '#eff6ff', stroke: '#2563eb' });
  d.vertex('<b>Future Native Hosts</b><br><span style="font-size:12px">macOS · Linux · mobile · game</span>', 1450, 720, 270, 85, { fill: '#ffffff', stroke: '#94a3b8', dashed: true });
  d.vertex('<b>Current principle</b><br>Unsupported host capability → clear Otter error', 90, 860, 480, 70, { fill: '#f0fdf4', stroke: '#16a34a' });
  d.vertex('<b>Portability gate</b><br>Same source + semantics, provider-specific implementation', 660, 860, 480, 70, { fill: '#fff7ed', stroke: '#f59e0b' });
  d.vertex('<b>Security gate</b><br>Dangerous or expensive behavior stays visible', 1230, 860, 480, 70, { fill: '#fef2f2', stroke: '#dc2626' });
  return d.xml();
}

function buildTargetPlatforms() {
  const d = diagram('Otter Target Architecture Map', 1800, 1030);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">OTTER TARGET ARCHITECTURE</b><br><span style="font-size:16px;color:#cbd5e1">Shared language core, explicit target adapters, honest host certification</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });
  const core = d.vertex('<b>SHARED OTTER CORE</b><br><span style="font-size:14px">module resolver · lexer · parser · AST · semantics · diagnostics · standard values</span>', 240, 155, 1320, 90, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const selector = d.vertex('<b>Build / Run Target Selection</b><br><span style="font-size:12px">explicit CLI and project configuration</span>', 650, 290, 500, 75, { fill: '#fff7ed', stroke: '#f59e0b' });
  d.edge(core, selector);

  const targets = [
    { x: 35, title: 'CONSOLE / AUTOMATION', compiler: 'Interpreter', runtime: 'Runtime + shell/files', artifact: '.ot execution', host: 'Windows V1', planned: false },
    { x: 385, title: 'WEB APPLICATION', compiler: 'JavaScript compiler', runtime: 'Browser runtime', artifact: 'HTML · CSS · JS', host: 'Browser certification', planned: false },
    { x: 735, title: 'DESKTOP APPLICATION', compiler: 'JS compiler / interpreter', runtime: 'Desktop bridge + UI', artifact: 'Packaged desktop app', host: 'Windows V1', planned: false },
    { x: 1085, title: 'SERVER / API', compiler: 'Interpreter', runtime: 'HTTP server runtime', artifact: 'Service process', host: 'Host certification', planned: false },
    { x: 1435, title: 'FUTURE TARGETS', compiler: 'Target backend', runtime: 'Game · Mobile · 3D', artifact: 'Target artifact', host: 'Planned', planned: true }
  ];
  for (const target of targets) {
    const stroke = target.planned ? '#94a3b8' : '#d97706';
    const dashed = target.planned;
    d.vertex(`<b>${target.title}</b>`, target.x, 420, 315, 55, { fill: target.planned ? '#f8fafc' : '#fffbeb', stroke, dashed, font: target.planned ? '#475569' : '#92400e', extra: 'fontSize=13;' });
    d.vertex(`<b>Frontend / Compiler</b><br><span style="font-size:12px">${target.compiler}</span>`, target.x, 495, 315, 75, { fill: '#ffffff', stroke, dashed });
    d.vertex(`<b>Target Runtime</b><br><span style="font-size:12px">${target.runtime}</span>`, target.x, 590, 315, 75, { fill: '#ffffff', stroke, dashed });
    d.vertex(`<b>Artifact</b><br><span style="font-size:12px">${target.artifact}</span>`, target.x, 685, 315, 75, { fill: '#ffffff', stroke, dashed });
    d.vertex(`<b>Host Gate</b><br><span style="font-size:12px">${target.host}</span>`, target.x, 800, 315, 75, { fill: target.planned ? '#ffffff' : '#eff6ff', stroke: target.planned ? '#94a3b8' : '#2563eb', dashed });
  }
  d.vertex('<b>Shared guarantee:</b> target differences belong in compilers, runtimes, and providers—not silent changes to Otter semantics.', 230, 920, 1340, 65, { fill: '#f0fdf4', stroke: '#16a34a' });
  return d.xml();
}

function buildFeatureDependencies() {
  const d = diagram('IDE Feature Dependency Graph', 1800, 1040);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">IDE FEATURE DEPENDENCY GRAPH</b><br><span style="font-size:16px;color:#cbd5e1">What must be trustworthy before higher-level Studio features can be certified</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });

  d.label('FOUNDATION', 55, 160, 300, 30, { size: 16, font: '#7e22ce' });
  const contract = d.vertex('<b>Versioned Contract</b><br><span style="font-size:12px">tokens · AST · diagnostics</span>', 80, 215, 290, 80, { fill: '#f3e8ff', stroke: '#7e22ce' });
  const parser = d.vertex('<b>Parser + Source Map</b><br><span style="font-size:12px">canonical meaning + locations</span>', 420, 205, 320, 100, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const runtime = d.vertex('<b>Runtime Semantics</b><br><span style="font-size:12px">scope · values · capabilities</span>', 790, 215, 300, 80, { fill: '#d1fae5', stroke: '#047857' });
  const uiModel = d.vertex('<b>Canonical UI Model</b><br><span style="font-size:12px">resources · properties · events</span>', 1140, 215, 300, 80, { fill: '#dbeafe', stroke: '#2563eb' });
  const conformance = d.vertex('<b>Conformance Harness</b><br><span style="font-size:12px">real source + real entry points</span>', 1490, 215, 260, 80, { fill: '#f0fdf4', stroke: '#16a34a' });
  d.edge(contract, parser);
  d.edge(parser, runtime);
  d.edge(runtime, conformance);
  d.edge(uiModel, conformance);

  d.vertex('', 25, 350, 1750, 250, { fill: '#eff6ff', stroke: '#bfdbfe' });
  d.label('SHARED SERVICES', 55, 365, 350, 30, { size: 16, font: '#1d4ed8' });
  const diagnostics = d.vertex('<b>Diagnostics</b><br><span style="font-size:12px">errors · source lines · fixes</span>', 65, 440, 260, 80, { fill: '#ffffff', stroke: '#2563eb' });
  const symbols = d.vertex('<b>Symbol Model</b><br><span style="font-size:12px">scope · definitions · references</span>', 360, 430, 285, 100, { fill: '#dbeafe', stroke: '#2563eb', shadow: true });
  const compiler = d.vertex('<b>Compiler / Runner</b><br><span style="font-size:12px">build · execute · target selection</span>', 680, 440, 285, 80, { fill: '#ffffff', stroke: '#2563eb' });
  const renderer = d.vertex('<b>UI Renderer</b><br><span style="font-size:12px">model → preview</span>', 1000, 440, 250, 80, { fill: '#ffffff', stroke: '#2563eb' });
  const generator = d.vertex('<b>Source Generator</b><br><span style="font-size:12px">UI model → canonical .ot</span>', 1285, 440, 275, 80, { fill: '#ffffff', stroke: '#2563eb' });
  const process = d.vertex('<b>Process / PTY</b><br><span style="font-size:12px">streams · exit · signals</span>', 1595, 440, 150, 80, { fill: '#ffffff', stroke: '#2563eb' });
  d.edge(parser, diagnostics);
  d.edge(parser, symbols);
  d.edge(parser, compiler);
  d.edge(uiModel, renderer);
  d.edge(uiModel, generator);
  d.edge(runtime, process);

  d.label('PROFESSIONAL IDE FEATURES', 55, 635, 500, 30, { size: 16, font: '#b45309' });
  const editor = d.vertex('<b>Smart Editor</b><br><span style="font-size:12px">completion · hover · navigation</span>', 65, 700, 275, 85, { fill: '#fffbeb', stroke: '#d97706' });
  const refactor = d.vertex('<b>References + Rename</b><br><span style="font-size:12px">shadowing-safe transformations</span>', 375, 700, 285, 85, { fill: '#fffbeb', stroke: '#d97706' });
  const designer = d.vertex('<b>Visual Designer</b><br><span style="font-size:12px">drag/drop · inspector · round trip</span>', 695, 690, 300, 105, { fill: '#fffbeb', stroke: '#d97706', shadow: true });
  const debuggerNode = d.vertex('<b>Debugger</b><br><span style="font-size:12px">breakpoints · stepping · variables</span>', 1030, 700, 280, 85, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  const testExplorer = d.vertex('<b>Test Explorer</b><br><span style="font-size:12px">discover · run · report</span>', 1345, 700, 260, 85, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  const packaging = d.vertex('<b>Packaging</b><br><span style="font-size:12px">artifacts · installer · publish</span>', 1640, 700, 110, 85, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  d.edge(diagnostics, editor);
  d.edge(symbols, editor);
  d.edge(symbols, refactor);
  d.edge(renderer, designer);
  d.edge(generator, designer);
  d.edge(compiler, debuggerNode);
  d.edge(process, debuggerNode);
  d.edge(compiler, testExplorer);
  d.edge(compiler, packaging);

  d.vertex('<b>CERTIFICATION RULE</b><br><span style="font-size:14px">A feature is not complete because its UI exists. Its dependencies, real source path, failure behavior, and target host must all pass.</span>', 250, 875, 1300, 95, { fill: '#f0fdf4', stroke: '#16a34a', shadow: true });
  return d.xml();
}

function phaseProgress(text, phase) {
  const startPattern = new RegExp(`^## P${phase}\\b`, 'm');
  const start = text.search(startPattern);
  if (start < 0) return { complete: 0, total: 0 };
  const remainder = text.slice(start);
  const next = remainder.slice(1).search(/^## P\d+\b/m);
  const section = next < 0 ? remainder : remainder.slice(0, next + 1);
  return {
    total: (section.match(/^\s*-\s+\[[ xX]\]/gm) || []).length,
    complete: (section.match(/^\s*-\s+\[[xX]\]/gm) || []).length
  };
}

function buildReleaseRoadmap() {
  const d = diagram('Release Roadmap and Certification Map', 1800, 1050);
  d.vertex('<div style="text-align:left"><b style="font-size:28px">RELEASE ROADMAP & CERTIFICATION MAP</b><br><span style="font-size:16px;color:#cbd5e1">P0 → P7, driven by both permanent master checklists</span></div>', 25, 20, 1750, 105, { fill: '#0f172a', stroke: '#0f172a', font: '#ffffff', shadow: true, extra: 'align=left;spacingLeft=28;' });

  const names = [
    'Protect & freeze foundations',
    'Language / runtime parity',
    'Studio journey + Console/System',
    'Designer + Desktop/Web',
    'Professional language ecosystem',
    'Build/Debug + Games',
    'Tests/Packages/Git + 3D',
    'Ship + platform maturity'
  ];
  const descriptions = [
    'Preserve current work · reconcile architecture',
    'Core semantics · providers · conformance',
    'Open/edit/save/run · administration capabilities',
    'Round trip · UI runtime · web/backend completion',
    'Language service · packages · build system',
    'Run/debug lifecycle · game foundations',
    'Testing · source control · extensions · 3D',
    'Installer · docs · cross-platform certification'
  ];
  const cards = [];
  for (let phase = 0; phase < 8; phase += 1) {
    const platform = phaseProgress(platformChecklist.text, phase);
    const studio = phaseProgress(studioChecklist.text, phase);
    const complete = platform.complete + studio.complete;
    const total = platform.total + studio.total;
    const row = phase < 4 ? 0 : 1;
    const column = phase < 4 ? phase : 7 - phase;
    const x = 70 + column * 425;
    const y = row === 0 ? 235 : 590;
    const ratio = total > 0 ? complete / total : 0;
    const fill = ratio === 1 ? '#f0fdf4' : ratio > 0.5 ? '#fffbeb' : '#f8fafc';
    const stroke = ratio === 1 ? '#16a34a' : ratio > 0.5 ? '#d97706' : '#64748b';
    const card = d.vertex(
      `<div style="text-align:left"><b style="font-size:20px">P${phase}</b><br><b>${names[phase]}</b><br><span style="font-size:12px;color:#475569">${descriptions[phase]}</span><br><br><b>${complete}/${total}</b> checklist gates complete</div>`,
      x, y, 365, 190,
      { fill, stroke, shadow: phase <= 2, extra: 'align=left;spacingLeft=18;' }
    );
    cards.push(card);
  }
  d.label('FOUNDATION → PRODUCT', 70, 175, 500, 30, { size: 16, font: '#1d4ed8' });
  d.label('ECOSYSTEM → RELEASE', 70, 530, 500, 30, { size: 16, font: '#b45309' });
  d.edge(cards[0], cards[1]);
  d.edge(cards[1], cards[2]);
  d.edge(cards[2], cards[3]);
  d.edge(cards[3], cards[4]);
  d.edge(cards[4], cards[5]);
  d.edge(cards[5], cards[6]);
  d.edge(cards[6], cards[7]);
  d.vertex('<b>PERMANENT GATE</b><br><span style="font-size:14px">implementation → focused tests → dogfood → production entry point → host certification → checklist [x]</span>', 250, 875, 1300, 90, { fill: '#eff6ff', stroke: '#2563eb', shadow: true });
  d.label('Counts are generated from both master checklist files at build time.', 500, 985, 800, 28, { size: 13, bold: false, align: 'center', font: '#64748b' });
  return d.xml();
}

const outputs = new Map([
  ['otter-master.drawio', buildMasterArchitecture()],
  ['compiler-pipeline.drawio', buildCompilerPipeline()],
  ['studio-architecture.drawio', buildStudioArchitecture()],
  ['designer-roundtrip.drawio', buildDesignerRoundTrip()],
  ['runtime-providers.drawio', buildRuntimeProviders()],
  ['target-platforms.drawio', buildTargetPlatforms()],
  ['feature-dependencies.drawio', buildFeatureDependencies()],
  ['release-roadmap.drawio', buildReleaseRoadmap()]
]);

fs.mkdirSync(architectureDir, { recursive: true });
fs.mkdirSync(exportDir, { recursive: true });

for (const [name, contents] of outputs) {
  const outputPath = path.join(architectureDir, name);
  fs.writeFileSync(outputPath, contents, 'utf8');
  if (!contents.includes('<mxGraphModel') || !contents.includes('</mxfile>')) {
    throw new Error(`${name} did not produce a valid Draw.io document envelope.`);
  }
  console.log(`Built ${path.relative(repoRoot, outputPath)}`);
}

const drawioCandidates = [
  process.env.DRAWIO_PATH,
  'C:\\Program Files\\draw.io\\draw.io.exe',
  'C:\\Program Files (x86)\\draw.io\\draw.io.exe',
  'C:\\Program Files\\diagrams.net\\diagrams.net.exe'
].filter(Boolean);
const drawio = drawioCandidates.find(candidate => fs.existsSync(candidate));

if (!drawio) {
  console.log('Draw.io Desktop CLI was not found; editable .drawio files are ready, SVG export skipped.');
  process.exit(0);
}

for (const name of outputs.keys()) {
  const inputPath = path.join(architectureDir, name);
  for (const format of ['svg', 'png']) {
    const exportedPath = path.join(exportDir, name.replace(/\.drawio$/, `.${format}`));
    const result = spawnSync(drawio, [
      '--export',
      '--crop',
      '--border', '16',
      '--format', format,
      '--output', exportedPath,
      inputPath
    ], { stdio: 'inherit' });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Draw.io ${format} export failed for ${name} with exit code ${result.status}.`);
    console.log(`Exported ${path.relative(repoRoot, exportedPath)}`);
  }
}
