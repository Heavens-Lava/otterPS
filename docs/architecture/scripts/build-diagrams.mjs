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
  const d = diagram('Otter Platform Master Architecture');
  d.label('OTTER PLATFORM MASTER ARCHITECTURE', 40, 25, 1120, 48, { size: 28 });
  d.label('Readable language · shared frontend · provider-backed applications', 40, 70, 1120, 32, { size: 16, bold: false, font: '#475569' });

  const governance = d.vertex(
    `Architecture & certification sources\nPlatform checklist: ${platformChecklist.complete}/${platformChecklist.total} complete\nStudio checklist: ${studioChecklist.complete}/${studioChecklist.total} complete`,
    1240, 25, 500, 85,
    { fill: '#fff7ed', stroke: '#f59e0b', font: '#7c2d12' }
  );

  d.label('AUTHORING & DEVELOPER EXPERIENCE', 40, 135, 600, 30, { size: 17, font: '#1d4ed8' });
  const studio = d.vertex('Otter Studio\nEditor · Designer · Terminal · Debugger', 50, 180, 300, 90, { fill: '#eff6ff', stroke: '#2563eb', shadow: true });
  const vscode = d.vertex('VS Code Extension\nHighlighting · Language Service', 390, 180, 300, 90, { fill: '#eff6ff', stroke: '#2563eb' });
  const cli = d.vertex('CLI & REPL\notter run · check · web · desktop · serve', 730, 180, 340, 90, { fill: '#eff6ff', stroke: '#2563eb' });

  d.label('SHARED LANGUAGE CORE', 40, 315, 600, 30, { size: 17, font: '#7e22ce' });
  const source = d.vertex('Otter source\nmain.ot + modules', 40, 360, 200, 90, { fill: '#dbeafe', stroke: '#0284c7', shadow: true });
  const moduleResolver = d.vertex('Module Resolver\nsource graph + source map', 275, 360, 250, 90, { fill: '#faf5ff', stroke: '#9333ea' });
  const lexer = d.vertex('Lexer\nsource → tokens', 560, 360, 220, 90, { fill: '#faf5ff', stroke: '#9333ea' });
  const parser = d.vertex('Parser + Contract\ntokens → typed AST', 815, 350, 280, 110, { fill: '#f3e8ff', stroke: '#7e22ce', shadow: true });
  const semantics = d.vertex('Semantic Services\nsymbols · diagnostics · scopes', 1130, 360, 300, 90, { fill: '#faf5ff', stroke: '#9333ea' });
  const tests = d.vertex('Conformance & Tests\nparser · runtime · targets · dogfood', 1470, 360, 290, 90, { fill: '#f0fdf4', stroke: '#16a34a' });

  d.label('EXECUTION, COMPILATION & CAPABILITIES', 40, 505, 720, 30, { size: 17, font: '#047857' });
  const interpreter = d.vertex('Interpreter\nexecutes the AST', 80, 555, 270, 90, { fill: '#ecfdf5', stroke: '#059669' });
  const jsCompiler = d.vertex('JavaScript Compiler\nAST → HTML/CSS/JS', 400, 555, 290, 90, { fill: '#ecfdf5', stroke: '#059669' });
  const runtime = d.vertex('Runtime + Library\nvalues · files · JSON · time · processes', 740, 545, 350, 110, { fill: '#d1fae5', stroke: '#047857', shadow: true });
  const providers = d.vertex('Provider Layer\nUI · filesystem · process · HTTP · host bridges', 1140, 545, 380, 110, { fill: '#ecfdf5', stroke: '#059669' });
  const build = d.vertex('Build & Packaging\nartifacts · installer · releases', 1570, 545, 190, 110, { fill: '#fff7ed', stroke: '#f59e0b' });

  d.label('APPLICATION TARGETS', 40, 705, 500, 30, { size: 17, font: '#b45309' });
  const consoleTarget = d.vertex('Console & Automation\nV1 target', 50, 750, 260, 100, { fill: '#fffbeb', stroke: '#d97706' });
  const webTarget = d.vertex('Web Applications\nBrowser runtime', 350, 750, 260, 100, { fill: '#fffbeb', stroke: '#d97706' });
  const desktopTarget = d.vertex('Desktop Applications\nNative host + bridge', 650, 750, 270, 100, { fill: '#fffbeb', stroke: '#d97706' });
  const serverTarget = d.vertex('Server / API\nHTTP routes + JSON', 960, 750, 260, 100, { fill: '#fffbeb', stroke: '#d97706' });
  const futureTarget = d.vertex('Future Targets\nGame · Mobile · 3D · Compute', 1260, 750, 300, 100, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });

  d.label('HOST CERTIFICATION', 40, 900, 500, 30, { size: 17, font: '#475569' });
  const windows = d.vertex('Windows\nPrimary V1 host', 260, 945, 300, 80, { fill: '#eff6ff', stroke: '#2563eb' });
  const mac = d.vertex('macOS\nPlanned certification', 700, 945, 300, 80, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });
  const linux = d.vertex('Linux\nPlanned certification', 1140, 945, 300, 80, { fill: '#f8fafc', stroke: '#94a3b8', dashed: true });

  d.edge(studio, source, '', { color: '#2563eb' });
  d.edge(cli, source);
  d.edge(source, moduleResolver);
  d.edge(moduleResolver, lexer);
  d.edge(lexer, parser);
  d.edge(parser, semantics);
  d.edge(parser, interpreter);
  d.edge(parser, jsCompiler);
  d.edge(interpreter, runtime);
  d.edge(jsCompiler, runtime);
  d.edge(runtime, providers);
  d.edge(providers, consoleTarget);
  d.edge(providers, desktopTarget);
  d.edge(providers, serverTarget);
  d.edge(jsCompiler, webTarget);
  d.edge(build, webTarget);
  d.edge(build, desktopTarget);
  d.edge(governance, tests, 'release gates', { dashed: true, color: '#f59e0b' });
  d.edge(consoleTarget, windows);
  d.edge(desktopTarget, windows);

  d.label('Blue: authoring / current host    Purple: language core    Green: runtime/compiler    Gold: application targets    Dashed: planned or governance', 80, 1060, 1600, 30, { size: 14, bold: false, align: 'center', font: '#475569' });
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

const outputs = new Map([
  ['otter-master.drawio', buildMasterArchitecture()],
  ['compiler-pipeline.drawio', buildCompilerPipeline()]
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
