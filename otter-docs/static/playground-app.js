(() => {
  'use strict';

  const EXAMPLES = [
    {
      id: 'hello',
      title: '1. Hello Otter (Variables, Functions & Objects)',
      mode: 'console',
      stdin: '',
      code: [
        '# Otter 1.0.1 — Readable variables, functions, loops, and value-first objects',
        'name is "Otter"',
        'say "Hello," name',
        '',
        'to greet person',
        '    say "Welcome to Otter," person',
        '.',
        '',
        'greet "Ada"',
        'greet "Developer"',
        '',
        'a Project has',
        '    title',
        '    version',
        '    ready',
        '.',
        '',
        'release is a Project with',
        '    "Otter River Slate" title,',
        '    "1.0.1" version,',
        '    true ready',
        '.',
        '',
        'say "Release:" title of release version of release "ready:" ready of release'
      ].join('\n')
    },
    {
      id: 'task-manager',
      title: '2. Task Manager (Interactive CRUD App)',
      mode: 'web',
      stdin: '',
      code: [
        '# Interactive CRUD Task Manager — compiled to River Slate HTML inside WebAssembly',
        'app is a page with',
        '    "Otter Task Manager" title,',
        '    true scroll,',
        '    20 spacing',
        '.',
        '',
        'metricsRow is a row with 10 spacing, true wrap',
        'totalBadge is a badge with "3" text, "outline" variant',
        'totalLbl is a text with "Total" value, "muted" variant',
        'doneBadge is a badge with "1" text, "success" variant',
        'doneLbl is a text with "Completed" value, "muted" variant',
        'openBadge is a badge with "2" text, "warning" variant',
        'openLbl is a text with "Open" value, "muted" variant',
        'put totalLbl, totalBadge, doneLbl, doneBadge, openLbl, openBadge in metricsRow',
        '',
        'completionBar is a progress with 33 value, 100 max',
        '',
        'layoutGrid is a grid with 2 columns, 20 spacing',
        '',
        '# Create / Update Card',
        'editorCard is a card with',
        '    "Create & Update Task" title,',
        '    "Add new tasks, rename the active task, or clear completed items." subtitle',
        '.',
        'taskInput is a text box with',
        '    "Task title" label,',
        '    "Write WASM parity tests" placeholder,',
        '    "Press Add Task to append to your live board." hint',
        '.',
        'prioritySelect is a dropdown with',
        '    "Priority" label,',
        '    "High, Medium, Low" options',
        '.',
        'btnRow is a row with 8 spacing, true wrap',
        'addTaskBtn is a primary button with "Add Task" text',
        'renameBtn is a secondary button with "Rename Task #1" text',
        'deleteBtn is a danger button with "Delete Last" text',
        'put addTaskBtn, renameBtn, deleteBtn in btnRow',
        'crudStatus is a text with "Ready — 3 tasks loaded." value, "muted" variant',
        'put taskInput, prioritySelect, btnRow, crudStatus in editorCard',
        '',
        '# Task Board Card (Read / Toggle / Delete)',
        'boardCard is a card with',
        '    "Active Task Board" title,',
        '    "Toggle checkboxes to recalculate completion progress live." subtitle',
        '.',
        't1Check is a checkbox with "[High] Finalize River Slate tokens" text, true checked',
        't2Check is a checkbox with "[High] Verify WASM Playground parity" text',
        't3Check is a checkbox with "[Medium] Package VS Code VSIX" text',
        'addedTitle is a text with "Added tasks" value, "subheading" variant',
        'addedLog is a text with "No newly added tasks yet." value, "muted" variant',
        'actionRow is a row with 8 spacing, true wrap',
        'completeAllBtn is a outline button with "Complete Next" text',
        'resetTasksBtn is a ghost button with "Reset Board" text',
        'put completeAllBtn, resetTasksBtn in actionRow',
        'put t1Check, t2Check, t3Check, addedTitle, addedLog, actionRow in boardCard',
        '',
        'totalCount is 3',
        'doneCount is 1',
        'openCount is 2',
        'latestTask is ""',
        '',
        'when addTaskBtn is clicked',
        '    entered is text of taskInput',
        '    prio is text of prioritySelect',
        '    if entered is empty',
        '        text of crudStatus is "Enter a task title first."',
        '    otherwise',
        '        totalCount is totalCount plus 1',
        '        openCount is openCount plus 1',
        '        latestTask is "[" plus prio plus "] " plus entered',
        '        text of totalBadge is totalCount',
        '        text of openBadge is openCount',
        '        text of addedLog is "Latest added: " plus latestTask',
        '        text of crudStatus is "Created task: " plus entered',
        '        pct is doneCount times 100 divided by totalCount',
        '        value of completionBar is pct',
        '        text of taskInput is ""',
        '    .',
        '.',
        '',
        'when renameBtn is clicked',
        '    entered is text of taskInput',
        '    if entered is empty',
        '        text of crudStatus is "Type a new title in Task title to rename Task #1."',
        '    otherwise',
        '        text of addedLog is "Updated Task #1 -> " plus entered',
        '        text of crudStatus is "Updated Task #1: " plus entered',
        '    .',
        '.',
        '',
        'when completeAllBtn is clicked',
        '    if openCount is greater than 0',
        '        doneCount is doneCount plus 1',
        '        openCount is openCount minus 1',
        '        text of doneBadge is doneCount',
        '        text of openBadge is openCount',
        '        pct is doneCount times 100 divided by totalCount',
        '        value of completionBar is pct',
        '        text of crudStatus is "Marked next task complete."',
        '    otherwise',
        '        text of crudStatus is "All tasks are already completed!"',
        '    .',
        '.',
        '',
        'when deleteBtn is clicked',
        '    if totalCount is greater than 1',
        '        totalCount is totalCount minus 1',
        '        if openCount is greater than 0',
        '            openCount is openCount minus 1',
        '        otherwise',
        '            doneCount is doneCount minus 1',
        '        .',
        '        text of totalBadge is totalCount',
        '        text of doneBadge is doneCount',
        '        text of openBadge is openCount',
        '        pct is doneCount times 100 divided by totalCount',
        '        value of completionBar is pct',
        '        text of crudStatus is "Deleted last task from board."',
        '    otherwise',
        '        text of crudStatus is "At least one task remains on the board."',
        '    .',
        '.',
        '',
        'when resetTasksBtn is clicked',
        '    totalCount is 3',
        '    doneCount is 1',
        '    openCount is 2',
        '    text of totalBadge is 3',
        '    text of doneBadge is 1',
        '    text of openBadge is 2',
        '    value of completionBar is 33',
        '    text of addedLog is "No newly added tasks yet."',
        '    text of crudStatus is "Board reset to initial 3 tasks."',
        '.',
        '',
        'put editorCard, boardCard in layoutGrid',
        'put metricsRow, completionBar, layoutGrid in app',
        'show app'
      ].join('\n')
    },
    {
      id: 'business-dashboard',
      title: '3. Business Dashboard (Cards, Table & Progress)',
      mode: 'web',
      stdin: '',
      code: [
        '# Responsive Business & Operations Dashboard in River Slate UI',
        'app is a page with',
        '    "Otter Cloud — Operations Dashboard" title,',
        '    true scroll,',
        '    20 spacing',
        '.',
        '',
        '# Top KPI Grid',
        'kpiGrid is a grid with 2 columns, 16 spacing',
        '',
        'revCard is a card with',
        '    "Monthly Recurring Revenue" title,',
        '    "Q4 enterprise & developer subscriptions" subtitle',
        '.',
        'revVal is a text with "$148,400" value, "title" variant',
        'revRow is a row with 8 spacing, true wrap',
        'revBadge is a badge with "+18.4% MoM" text, "success" variant',
        'revGoal is a text with "82% of $180k target" value, "muted" variant',
        'put revBadge, revGoal in revRow',
        'revProg is a progress with 82 value, 100 max',
        'put revVal, revRow, revProg in revCard',
        '',
        'slaCard is a card with',
        '    "Fleet Availability & SLA" title,',
        '    "Real-time multi-region probe telemetry" subtitle',
        '.',
        'slaVal is a text with "99.94% Uptime" value, "title" variant',
        'slaRow is a row with 8 spacing, true wrap',
        'slaBadge is a badge with "Operational" text, "success" variant',
        'sweepCountBadge is a badge with "1" text, "outline" variant',
        'sweepLbl is a text with "Sweeps run" value, "muted" variant',
        'put slaBadge, sweepLbl, sweepCountBadge in slaRow',
        'slaProg is a progress with 94 value, 100 max',
        'put slaVal, slaRow, slaProg in slaCard',
        '',
        'put revCard, slaCard in kpiGrid',
        '',
        '# Structured Service Health Table Card',
        'tableCard is a card with',
        '    "Regional Service Health Table" title,',
        '    "Structured responsive service rows with semantic status badges." subtitle',
        '.',
        'hdrRow is a row with spread, 12 spacing, true wrap',
        'h1 is a text with "SERVICE" value, "subheading" variant',
        'h2 is a text with "REGION" value, "subheading" variant',
        'h3 is a text with "P95 LATENCY" value, "subheading" variant',
        'h4 is a text with "STATUS" value, "subheading" variant',
        'put h1, h2, h3, h4 in hdrRow',
        '',
        'r1 is a row with spread, 12 spacing, true wrap',
        'r1Name is a text with "Orders API" value',
        'r1Reg is a text with "US-West (Oregon)" value, "muted" variant',
        'r1Lat is a text with "21 ms" value, "code" variant',
        'r1Stat is a badge with "Healthy" text, "success" variant',
        'put r1Name, r1Reg, r1Lat, r1Stat in r1',
        '',
        'r2 is a row with spread, 12 spacing, true wrap',
        'r2Name is a text with "Billing Engine" value',
        'r2Reg is a text with "EU-Central (Frankfurt)" value, "muted" variant',
        'r2Lat is a text with "48 ms" value, "code" variant',
        'r2Stat is a badge with "Healthy" text, "success" variant',
        'put r2Name, r2Reg, r2Lat, r2Stat in r2',
        '',
        'r3 is a row with spread, 12 spacing, true wrap',
        'r3Name is a text with "Analytics Ingest" value',
        'r3Reg is a text with "AP-East (Tokyo)" value, "muted" variant',
        'r3Lat is a text with "164 ms" value, "code" variant',
        'r3Stat is a badge with "Elevated" text, "warning" variant',
        'put r3Name, r3Reg, r3Lat, r3Stat in r3',
        '',
        'put hdrRow, r1, r2, r3 in tableCard',
        '',
        '# Interactive Alert Policy Card',
        'policyCard is a card with',
        '    "Alert Threshold & Controls" title,',
        '    "Adjust SLA budget threshold and run a live fleet health sweep." subtitle',
        '.',
        'budgetSlider is a slider with',
        '    "Capacity alert threshold (%)" label,',
        '    50 min,',
        '    100 max,',
        '    85 value,',
        '    true showvalue',
        '.',
        'budgetLabel is a text with "Alert threshold active at 85%" value, "muted" variant',
        'budgetBar is a progress with 85 value, 100 max',
        'ctrlRow is a row with 10 spacing, true wrap',
        'sweepBtn is a primary button with "Run Health Sweep" text',
        'resetDashBtn is a outline button with "Reset Metrics" text',
        'dashFeedback is a text with "All regions reporting normally." value, "muted" variant',
        'put sweepBtn, resetDashBtn, dashFeedback in ctrlRow',
        'put budgetSlider, budgetLabel, budgetBar, ctrlRow in policyCard',
        '',
        'sweeps is 1',
        'when sweepBtn is clicked',
        '    sweeps is sweeps plus 1',
        '    text of sweepCountBadge is sweeps',
        '    text of r3Lat is "52 ms"',
        '    text of r3Stat is "Healthy"',
        '    value of slaProg is 99',
        '    text of dashFeedback is "Sweep complete — Analytics Ingest stabilized (52 ms)."',
        '.',
        '',
        'when resetDashBtn is clicked',
        '    sweeps is 1',
        '    text of sweepCountBadge is 1',
        '    text of r3Lat is "164 ms"',
        '    text of r3Stat is "Elevated"',
        '    value of slaProg is 94',
        '    text of dashFeedback is "Metrics restored to baseline snapshot."',
        '.',
        '',
        'when budgetSlider is changed',
        '    curVal is text of budgetSlider',
        '    text of budgetLabel is "Alert threshold active at " plus curVal plus "%"',
        '    value of budgetBar is curVal',
        '.',
        '',
        'put kpiGrid, tableCard, policyCard in app',
        'show app'
      ].join('\n')
    },
    {
      id: 'rpg-builder',
      title: '4. RPG Character Builder (State & Calculations)',
      mode: 'web',
      stdin: '',
      code: [
        '# Interactive RPG Character Builder — live state, math & River Slate controls',
        'app is a page with',
        '    "Otter RPG Character Builder" title,',
        '    true scroll,',
        '    20 spacing',
        '.',
        '',
        'builderGrid is a grid with 2 columns, 20 spacing',
        '',
        '# Left Card: Character Attributes',
        'attrCard is a card with',
        '    "Hero Attributes" title,',
        '    "Choose name, class, level, and core stats to recalculate combat ratings." subtitle',
        '.',
        'heroNameBox is a text box with',
        '    "Character name" label,',
        '    "Kaelen the Swift" value,',
        '    "Enter your hero name." hint',
        '.',
        'classSelect is a dropdown with',
        '    "Class" label,',
        '    "Warrior, Mage, Ranger, Cleric" options',
        '.',
        'levelSlider is a slider with',
        '    "Level" label,',
        '    1 min,',
        '    20 max,',
        '    5 value,',
        '    true showvalue',
        '.',
        'strSlider is a slider with',
        '    "Strength" label,',
        '    5 min,',
        '    20 max,',
        '    14 value,',
        '    true showvalue',
        '.',
        'intSlider is a slider with',
        '    "Intelligence" label,',
        '    5 min,',
        '    20 max,',
        '    10 value,',
        '    true showvalue',
        '.',
        'agiSlider is a slider with',
        '    "Agility" label,',
        '    5 min,',
        '    20 max,',
        '    12 value,',
        '    true showvalue',
        '.',
        'actRow is a row with 10 spacing, true wrap',
        'calcBtn is a primary button with "Recalculate Build" text',
        'levelUpBtn is a secondary button with "Level Up (+1)" text',
        'resetHeroBtn is a outline button with "Reset Hero" text',
        'put calcBtn, levelUpBtn, resetHeroBtn in actRow',
        'put heroNameBox, classSelect, levelSlider, strSlider, intSlider, agiSlider, actRow in attrCard',
        '',
        '# Right Card: Computed Character Sheet',
        'sheetCard is a card with',
        '    "Live Character Sheet" title,',
        '    "Derived HP, Mana, Attack, Defense, and Raid Readiness." subtitle',
        '.',
        'heroTitle is a text with "Kaelen the Swift — Warrior" value, "heading" variant',
        'statRow1 is a row with 10 spacing, true wrap',
        'hpLbl is a text with "HP" value, "muted" variant',
        'hpBadge is a badge with "210" text, "success" variant',
        'manaLbl is a text with "Mana" value, "muted" variant',
        'manaBadge is a badge with "110" text',
        'put hpLbl, hpBadge, manaLbl, manaBadge in statRow1',
        '',
        'statRow2 is a row with 10 spacing, true wrap',
        'atkLbl is a text with "Attack" value, "muted" variant',
        'atkBadge is a badge with "48" text, "warning" variant',
        'defLbl is a text with "Defense" value, "muted" variant',
        'defBadge is a badge with "36" text, "outline" variant',
        'put atkLbl, atkBadge, defLbl, defBadge in statRow2',
        '',
        'readinessLbl is a text with "Raid Readiness Score" value, "subheading" variant',
        'readinessBar is a progress with 52 value, 100 max',
        'tierBadge is a badge with "Tier: Veteran" text, "success" variant',
        'buildNote is a text with "Adjust sliders or click Level Up to recalculate stats." value, "muted" variant',
        'put heroTitle, statRow1, statRow2, readinessLbl, readinessBar, tierBadge, buildNote in sheetCard',
        '',
        'curLevel is 5',
        'curStr is 14',
        'curInt is 10',
        'curAgi is 12',
        '',
        'to updateSheet',
        '    heroNm is text of heroNameBox',
        '    heroCls is text of classSelect',
        '    if heroNm is empty',
        '        heroNm is "Unnamed Hero"',
        '    .',
        '    text of heroTitle is heroNm plus " — " plus heroCls',
        '    lvlHp is curLevel times 12',
        '    strHp is curStr times 5',
        '    hpVal is 100 plus lvlHp plus strHp',
        '    lvlMana is curLevel times 6',
        '    intMana is curInt times 6',
        '    manaVal is 50 plus lvlMana plus intMana',
        '    strAtk is curStr times 2',
        '    lvlAtk is curLevel times 2',
        '    atkVal is strAtk plus curAgi plus lvlAtk',
        '    defVal is 10 plus curStr plus curAgi plus curLevel',
        '    lvlPow is curLevel times 3',
        '    powerPct is lvlPow plus curStr plus curInt plus curAgi',
        '    if powerPct is greater than 100',
        '        powerPct is 100',
        '    .',
        '    text of hpBadge is hpVal',
        '    text of manaBadge is manaVal',
        '    text of atkBadge is atkVal',
        '    text of defBadge is defVal',
        '    value of readinessBar is powerPct',
        '    if powerPct is at least 80',
        '        text of tierBadge is "Tier: Legendary"',
        '    otherwise if powerPct is at least 55',
        '        text of tierBadge is "Tier: Champion"',
        '    otherwise',
        '        text of tierBadge is "Tier: Adventurer"',
        '    .',
        '    text of buildNote is "Stats recalculated for " plus heroNm plus " (" plus heroCls plus ")."',
        '.',
        '',
        'when levelSlider is changed',
        '    rawLvl is text of levelSlider',
        '    curLevel is rawLvl times 1',
        '    updateSheet',
        '.',
        'when strSlider is changed',
        '    rawStr is text of strSlider',
        '    curStr is rawStr times 1',
        '    updateSheet',
        '.',
        'when intSlider is changed',
        '    rawInt is text of intSlider',
        '    curInt is rawInt times 1',
        '    updateSheet',
        '.',
        'when agiSlider is changed',
        '    rawAgi is text of agiSlider',
        '    curAgi is rawAgi times 1',
        '    updateSheet',
        '.',
        'when calcBtn is clicked',
        '    updateSheet',
        '.',
        'when levelUpBtn is clicked',
        '    if curLevel is less than 20',
        '        curLevel is curLevel plus 1',
        '        value of levelSlider is curLevel',
        '    .',
        '    updateSheet',
        '.',
        'when resetHeroBtn is clicked',
        '    curLevel is 5',
        '    curStr is 14',
        '    curInt is 10',
        '    curAgi is 12',
        '    text of heroNameBox is "Kaelen the Swift"',
        '    value of levelSlider is 5',
        '    value of strSlider is 14',
        '    value of intSlider is 10',
        '    value of agiSlider is 12',
        '    updateSheet',
        '.',
        '',
        'put attrCard, sheetCard in builderGrid',
        'put builderGrid in app',
        'show app'
      ].join('\n')
    },
    {
      id: 'river-slate-showcase',
      title: '5. River Slate Component Showcase (Dark & Light UI)',
      mode: 'web',
      stdin: '',
      code: [
        '# River Slate Design System — Dark Default + Light Opt-In in Value-First Otter',
        'app is a page with',
        '    "Otter UI — River Slate Showcase" title,',
        '    true scroll,',
        '    20 spacing',
        '.',
        '',
        'topGrid is a grid with 2 columns, 20 spacing',
        '',
        '# Dark Card (Default)',
        'darkCard is a card with',
        '    "Dark — River Slate (Default)" title,',
        '    "Button variants, validated fields, sliders, and live event handlers." subtitle',
        '.',
        'btnRow is a row with 8 spacing, true wrap',
        'primaryBtn is a primary button with "Primary" text',
        'secondaryBtn is a secondary button with "Secondary" text',
        'outlineBtn is a outline button with "Outline" text',
        'ghostBtn is a ghost button with "Ghost" text',
        'dangerBtn is a danger button with "Danger" text',
        'disabledBtn is a button with "Disabled" text, true disabled',
        'put primaryBtn, secondaryBtn, outlineBtn, ghostBtn, dangerBtn, disabledBtn in btnRow',
        '',
        'clickStatus is a text with "Click any button to test live River Slate events." value, "muted" variant',
        'clickBadge is a badge with "0" text, "outline" variant',
        'statRow is a row with 8 spacing, true wrap',
        'put clickStatus, clickBadge in statRow',
        '',
        'nameField is a text box with',
        '    "Project name" label,',
        '    "otter-pulse" placeholder,',
        '    "Compiled straight from Otter to zero-dependency HTML." hint',
        '.',
        'errorField is a text box with',
        '    "Subdomain" label,',
        '    "Bad Slug!" value,',
        '    "Use lowercase letters and hyphens only." error',
        '.',
        'cpuSlider is a slider with',
        '    "CPU alert threshold (%)" label,',
        '    10 min,',
        '    100 max,',
        '    72 value,',
        '    true showvalue',
        '.',
        'cpuProgress is a progress with 72 value, 100 max',
        'put btnRow, statRow, nameField, errorField, cpuSlider, cpuProgress in darkCard',
        '',
        '# Embedded Light Card (Opt-In)',
        'lightCard is a card with',
        '    "Light — River Slate (Opt-In)" title,',
        '    "Crafted daylight surfaces with \\"light\\" theme and WCAG AA contrast." subtitle,',
        '    "light" theme',
        '.',
        'lightEmail is a text box with',
        '    "Workspace email" label,',
        '    "team@otterprogramming.com" placeholder,',
        '    "Dedicated light design tokens — never raw inverted colors." hint',
        '.',
        'lightRegion is a dropdown with',
        '    "Deployment region" label,',
        '    "US West (Oregon), US East (Virginia), EU Central (Frankfurt)" options',
        '.',
        'lightToggle is a toggle with "Zero-downtime rolling deploys" text, true checked',
        'lightCheck is a checkbox with "Enable automatic TLS certificates" text, true checked',
        'lightBtns is a row with 8 spacing, true wrap',
        'lSave is a primary button with "Save" text',
        'lReset is a secondary button with "Reset" text',
        'lInspect is a outline button with "Inspect" text',
        'lBadge is a badge with "AA Contrast" text, "success" variant',
        'put lSave, lReset, lInspect, lBadge in lightBtns',
        'lightStatus is a text with "Light card ready." value, "muted" variant',
        'put lightEmail, lightRegion, lightToggle, lightCheck, lightBtns, lightStatus in lightCard',
        '',
        'clicks is 0',
        'when primaryBtn is clicked',
        '    clicks is clicks plus 1',
        '    text of clickBadge is clicks',
        '    text of clickStatus is "Primary action triggered!"',
        '.',
        'when secondaryBtn is clicked',
        '    text of clickStatus is "Secondary action triggered."',
        '.',
        'when outlineBtn is clicked',
        '    text of clickStatus is "Outline preview opened."',
        '.',
        'when ghostBtn is clicked',
        '    text of clickStatus is "Ghost action dismissed."',
        '.',
        'when dangerBtn is clicked',
        '    text of clickStatus is "Danger confirmation requested."',
        '.',
        'when cpuSlider is changed',
        '    v is text of cpuSlider',
        '    value of cpuProgress is v',
        '.',
        'when lSave is clicked',
        '    text of lightStatus is "Light theme settings saved."',
        '.',
        '',
        'put darkCard, lightCard in topGrid',
        'put topGrid in app',
        'show app'
      ].join('\n')
    },
    {
      id: 'otter-pulse',
      title: '6. Otter Pulse Health Score Logic',
      mode: 'console',
      stdin: '',
      code: [
        '# Real clamping & telemetry scoring pattern used in Flagship App #1 (Otter Pulse)',
        'to clamp val low high',
        '    if val is less than low',
        '        return low',
        '    .',
        '    if val is greater than high',
        '        return high',
        '    .',
        '    return val',
        '.',
        '',
        'to scoreProbe latencyMs ok',
        '    if ok is false',
        '        return 0',
        '    .',
        '    penalty is latencyMs divided by 5',
        '    rawScore is 100 minus penalty',
        '    return clamp rawScore 10 100',
        '.',
        '',
        's1 is scoreProbe 21 true',
        's2 is scoreProbe 180 true',
        's3 is scoreProbe 300 false',
        'say "Live Orders API (21ms):" s1 "/ 100"',
        'say "Billing Worker (180ms):" s2 "/ 100"',
        'say "Down Service (503):" s3 "/ 100"'
      ].join('\n')
    },
    {
      id: 'ask-input',
      title: '7. Interactive Input (ask)',
      mode: 'console',
      stdin: 'Ada\n3',
      code: [
        '# Open "Program Input (ask)" below to edit the lines supplied to ask.',
        'ask "Your name: " and call it visitor',
        'ask "How many greetings? " and call it repeatCount',
        '',
        'count from 1 to repeatCount as n',
        '    say n "Hello," visitor',
        '.'
      ].join('\n')
    },
    {
      id: 'sandbox-limit',
      title: '8. Sandbox Safety Demo (Loop Guard)',
      mode: 'console',
      stdin: '',
      code: [
        '# Infinite loops are automatically stopped by the WebAssembly safety budget',
        '# (or immediately if you click Stop).',
        'say "Starting guarded loop..."',
        'ticks is 0',
        'while true',
        '    ticks is ticks plus 1',
        '.'
      ].join('\n')
    }
  ];

  const WORKER_URL = '/static/playground/otter-worker.mjs';
  const MAX_STEPS = 250000;
  const TIMEOUT_MS = 3000;
  const MAX_OUTPUT_BYTES = 65536;

  const KEYWORDS_RE = /\b(otherwise if|for each|is at least|is at most|is greater than|is less than|is not|divided by|length of|random number|random item|set random seed|start timer|elapsed milliseconds|from json|to json|from csv|to csv|and call it|fail with|into|say|ask|if|otherwise|while|repeat|times|count|from|to|as|each|in|return|stop|try|when|clicked|changed|put|show|is|are|has|of|plus|minus|times|add|remove|sort|reverse|replace|with|split|by|join|find|convert|query|where|set|get|key|at|true|false|empty|gone|and|or|not|a|an)\b/g;
  const UI_KINDS_RE = /\b(primary button|secondary button|outline button|ghost button|danger button|text box|text area|progress bar|radio button|page|window|card|grid|row|column|button|dropdown|checkbox|toggle|radio|slider|progress|badge|table|link)\b/g;
  const UI_PROPS_RE = /\b(theme|subtitle|placeholder|showvalue|hideheader|columns|spacing|padding|options|checked|disabled|variant|radius|scroll|label|title|value|error|align|width|height|hint|rows|wrap|text|min|max|step|spread)\b/g;

  function escapeHtml(s) {
    return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  }

  function highlightOtter(source) {
    const lines = String(source || '').split('\n');
    return lines.map((line) => {
      const trimmed = line.trim();
      if (trimmed === '.') {
        return line.replace('.', '<span class="ot-dot">.</span>');
      }
      let inStr = false;
      let commentIdx = -1;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"' && line[i - 1] !== '\\') inStr = !inStr;
        if (!inStr && ch === '#') {
          commentIdx = i;
          break;
        }
      }
      const codePart = commentIdx >= 0 ? line.slice(0, commentIdx) : line;
      const commentPart = commentIdx >= 0 ? line.slice(commentIdx) : '';

      let out = '';
      const strRe = /"(?:[^"\\]|\\.)*"/g;
      let last = 0;
      let m;
      while ((m = strRe.exec(codePart)) !== null) {
        out += highlightSegment(codePart.slice(last, m.index));
        out += `<span class="ot-str">${escapeHtml(m[0])}</span>`;
        last = m.index + m[0].length;
      }
      out += highlightSegment(codePart.slice(last));
      if (commentPart) {
        out += `<span class="ot-com">${escapeHtml(commentPart)}</span>`;
      }
      return out;
    }).join('\n') + '\n';
  }

  function highlightSegment(seg) {
    let escaped = escapeHtml(seg);
    escaped = escaped.replace(UI_KINDS_RE, '<span class="ot-ui">$1</span>');
    escaped = escaped.replace(KEYWORDS_RE, '<span class="ot-kw">$1</span>');
    escaped = escaped.replace(UI_PROPS_RE, '<span class="ot-prop">$1</span>');
    escaped = escaped.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="ot-num">$1</span>');
    return escaped;
  }

  function encodeShareHash(code, stdin) {
    const payload = JSON.stringify({ code, stdin });
    const bytes = new TextEncoder().encode(payload);
    let bin = '';
    bytes.forEach((b) => { bin += String.fromCharCode(b); });
    return '#code=' + encodeURIComponent(btoa(bin));
  }

  function decodeShareHash() {
    const hash = window.location.hash || '';
    if (hash.startsWith('#example=')) {
      const id = decodeURIComponent(hash.slice('#example='.length));
      const found = EXAMPLES.find((ex) => ex.id === id);
      if (found) return { exampleId: found.id, code: found.code, stdin: found.stdin, mode: found.mode };
    }
    if (hash.startsWith('#code=')) {
      try {
        const b64 = decodeURIComponent(hash.slice('#code='.length));
        if (b64.length > 24000) return null;
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        const parsed = JSON.parse(new TextDecoder().decode(bytes));
        if (typeof parsed.code === 'string') {
          return { exampleId: '', code: parsed.code, stdin: typeof parsed.stdin === 'string' ? parsed.stdin : '', mode: 'console' };
        }
      } catch {
        return null;
      }
    }
    return null;
  }

  function mountPlayground() {
    const mount = document.getElementById('playgroundMount');
    if (!mount) return;

    if (typeof WebAssembly === 'undefined' || typeof Worker === 'undefined') {
      mount.innerHTML = '<div class="pg-diag-card"><strong>WebAssembly or Web Workers are unavailable in this browser.</strong> Please use a modern version of Chrome, Edge, Firefox, or Safari, or <a href="/download/">download the Otter CLI</a>.</div>';
      return;
    }

    const initial = decodeShareHash() || { exampleId: EXAMPLES[0].id, code: EXAMPLES[0].code, stdin: EXAMPLES[0].stdin, mode: EXAMPLES[0].mode };
    let currentExampleId = initial.exampleId || EXAMPLES[0].id;
    let activeTab = initial.mode === 'web' ? 'preview' : 'console';

    mount.innerHTML = `
      <div class="pg-app" data-pg-ready="false" data-pg-mode="${activeTab}">
        <div class="pg-toolbar" role="toolbar" aria-label="Playground controls">
          <div class="pg-toolbar-group">
            <label class="pg-label" for="pgExampleSelect">Example</label>
            <select id="pgExampleSelect" class="pg-select" aria-label="Load Otter example">
              ${EXAMPLES.map((ex) => `<option value="${ex.id}"${ex.id === currentExampleId ? ' selected' : ''}>${escapeHtml(ex.title)}</option>`).join('')}
            </select>
          </div>
          <div class="pg-toolbar-group">
            <button id="pgRunBtn" type="button" class="pg-btn pg-btn-primary" disabled aria-keyshortcuts="Control+Enter Meta+Enter">&#9654; Run</button>
            <button id="pgStopBtn" type="button" class="pg-btn pg-btn-danger" disabled>&#9632; Stop</button>
            <button id="pgResetBtn" type="button" class="pg-btn">Reset</button>
            <button id="pgCopyBtn" type="button" class="pg-btn">Copy Code</button>
            <button id="pgShareBtn" type="button" class="pg-btn">Share Link</button>
          </div>
        </div>

        <div class="pg-status-bar" role="status" aria-live="polite">
          <span class="pg-status-pill">
            <span id="pgDot" class="pg-dot pg-dot-loading" aria-hidden="true"></span>
            <span id="pgStatusText">Loading Otter 1.0.1 WebAssembly runtime...</span>
          </span>
          <span id="pgMetricsText">Console + River Slate Web UI · 250k steps · 3s timeout · 100% client-side</span>
        </div>

        <div class="pg-workspace">
          <section class="pg-pane" aria-label="Otter code editor">
            <div class="pg-pane-head">
              <span>program.ot</span>
              <span class="pg-pane-meta">Ctrl/Cmd + Enter to Run · Tab indents</span>
            </div>
            <div class="pg-editor-wrap">
              <pre id="pgGutter" class="pg-gutter" aria-hidden="true">1</pre>
              <div class="pg-code-stage">
                <pre id="pgHighlight" class="pg-highlight" aria-hidden="true"></pre>
                <textarea id="pgEditor" class="pg-textarea" spellcheck="false" autocomplete="off" autocapitalize="off" aria-label="Otter source code editor"></textarea>
              </div>
            </div>
            <details id="pgStdinDetails" class="pg-stdin-drawer">
              <summary>Program Input (<code>ask</code> lines — one answer per line)</summary>
              <textarea id="pgStdin" class="pg-stdin-input" placeholder="Optional input lines for programs using ask..." aria-label="Program standard input lines"></textarea>
            </details>
          </section>

          <section class="pg-pane" aria-label="Output, live preview, and diagnostics">
            <div class="pg-pane-head">
              <div class="pg-output-tabs" role="tablist" aria-label="Output view">
                <button id="pgTabConsole" type="button" role="tab" class="pg-tab-btn" aria-selected="${activeTab === 'console'}" aria-controls="pgConsole">Console</button>
                <button id="pgTabPreview" type="button" role="tab" class="pg-tab-btn" aria-selected="${activeTab === 'preview'}" aria-controls="pgPreviewWrap">Live App Preview</button>
                <button id="pgTabHtml" type="button" role="tab" class="pg-tab-btn" aria-selected="false" aria-controls="pgHtmlView">Compiled HTML</button>
              </div>
              <span id="pgRunMeta" class="pg-pane-meta">Idle</span>
            </div>
            <div class="pg-output-body">
              <pre id="pgConsole" class="pg-console pg-console-empty${activeTab === 'console' ? '' : ' pg-panel-hidden'}" role="tabpanel" aria-live="polite" tabindex="0">Click Run (or press Ctrl/Cmd + Enter) to execute your Otter program.</pre>
              <div id="pgPreviewWrap" class="pg-preview-wrap${activeTab === 'preview' ? '' : ' pg-panel-hidden'}" role="tabpanel">
                <div id="pgPreviewPlaceholder" class="pg-preview-placeholder">Click <strong>Run</strong> to compile this Otter UI program into live River Slate HTML inside WebAssembly.</div>
                <iframe id="pgPreviewFrame" class="pg-preview-frame pg-panel-hidden" sandbox="allow-scripts" title="Live compiled Otter River Slate application preview"></iframe>
              </div>
              <pre id="pgHtmlView" class="pg-html-view pg-panel-hidden" role="tabpanel" tabindex="0">&lt;!-- Compile an Otter UI app to inspect the generated standalone River Slate HTML --&gt;</pre>
              <div id="pgDiagnostics" class="pg-diagnostics" aria-live="polite">
                <div class="pg-diag-heading">Diagnostics</div>
                <div class="pg-diag-ok">No syntax or runtime issues detected.</div>
              </div>
            </div>
          </section>
        </div>

        <div class="pg-footer-note">
          <span>
            <strong>Real Otter compiler &amp; interpreter in your browser:</strong> Runs the canonical C# <code>Otter.Language</code> + <code>Otter.Runtime</code> + <code>Otter.Web</code> (River Slate) WebAssembly engine inside an isolated Web Worker. Zero backend calls — filesystem, shell, database, and network commands remain disabled in the browser sandbox.
          </span>
          <span>
            Ready to build locally? <a href="/download/">Download Otter</a> · <a href="/otter-pulse/">Otter Pulse Tutorial</a> · <a href="/library/">Component Library</a>
          </span>
        </div>
      </div>
    `;

    const appEl = mount.querySelector('.pg-app');
    const selectEl = document.getElementById('pgExampleSelect');
    const runBtn = document.getElementById('pgRunBtn');
    const stopBtn = document.getElementById('pgStopBtn');
    const resetBtn = document.getElementById('pgResetBtn');
    const copyBtn = document.getElementById('pgCopyBtn');
    const shareBtn = document.getElementById('pgShareBtn');
    const dotEl = document.getElementById('pgDot');
    const statusText = document.getElementById('pgStatusText');
    const runMeta = document.getElementById('pgRunMeta');
    const gutterEl = document.getElementById('pgGutter');
    const highlightEl = document.getElementById('pgHighlight');
    const editorEl = document.getElementById('pgEditor');
    const stdinDetails = document.getElementById('pgStdinDetails');
    const stdinEl = document.getElementById('pgStdin');
    const consoleEl = document.getElementById('pgConsole');
    const previewWrap = document.getElementById('pgPreviewWrap');
    const previewPlaceholder = document.getElementById('pgPreviewPlaceholder');
    const previewFrame = document.getElementById('pgPreviewFrame');
    const htmlView = document.getElementById('pgHtmlView');
    const tabConsole = document.getElementById('pgTabConsole');
    const tabPreview = document.getElementById('pgTabPreview');
    const tabHtml = document.getElementById('pgTabHtml');
    const diagEl = document.getElementById('pgDiagnostics');

    editorEl.value = initial.code;
    stdinEl.value = initial.stdin || '';
    if (initial.stdin) stdinDetails.open = true;

    function switchTab(tab) {
      activeTab = tab;
      appEl.dataset.pgMode = tab;
      tabConsole.setAttribute('aria-selected', String(tab === 'console'));
      tabPreview.setAttribute('aria-selected', String(tab === 'preview'));
      tabHtml.setAttribute('aria-selected', String(tab === 'html'));
      consoleEl.classList.toggle('pg-panel-hidden', tab !== 'console');
      previewWrap.classList.toggle('pg-panel-hidden', tab !== 'preview');
      htmlView.classList.toggle('pg-panel-hidden', tab !== 'html');
    }

    tabConsole.addEventListener('click', () => switchTab('console'));
    tabPreview.addEventListener('click', () => switchTab('preview'));
    tabHtml.addEventListener('click', () => switchTab('html'));

    function syncEditorVisuals() {
      const text = editorEl.value;
      const lineCount = Math.max(1, text.split('\n').length);
      let nums = '';
      for (let i = 1; i <= lineCount; i++) nums += i + (i < lineCount ? '\n' : '');
      gutterEl.textContent = nums;
      highlightEl.innerHTML = highlightOtter(text);
      syncScroll();
    }

    function syncScroll() {
      highlightEl.scrollTop = editorEl.scrollTop;
      highlightEl.scrollLeft = editorEl.scrollLeft;
      gutterEl.scrollTop = editorEl.scrollTop;
    }

    function setStatus(state, text) {
      dotEl.className = `pg-dot pg-dot-${state}`;
      statusText.textContent = text;
    }

    function renderDiagnostics(diagnostics) {
      if (!diagnostics || diagnostics.length === 0) {
        diagEl.innerHTML = '<div class="pg-diag-heading">Diagnostics</div><div class="pg-diag-ok">No syntax or runtime issues detected.</div>';
        return;
      }
      const cards = diagnostics.map((d) => {
        const loc = `Line ${d.line || 1}${d.code ? ` · ${escapeHtml(d.code)}` : ''}`;
        const sug = d.suggestion ? `<div class="pg-diag-suggestion">Try: ${escapeHtml(d.suggestion)}</div>` : '';
        return `<div class="pg-diag-card"><div class="pg-diag-loc">${loc}</div><div>${escapeHtml(d.message)}</div>${sug}</div>`;
      }).join('');
      diagEl.innerHTML = `<div class="pg-diag-heading">Diagnostics (${diagnostics.length})</div>${cards}`;
    }

    let worker = null;
    let workerReady = false;
    let runtimeVersion = 'Otter 1.0.1 (WebAssembly)';
    let nextMsgId = 1;
    let activeRunId = null;
    let watchdogTimer = null;
    const pending = new Map();

    function spawnWorker() {
      if (worker) {
        try { worker.terminate(); } catch {}
      }
      pending.clear();
      workerReady = false;
      activeRunId = null;
      appEl.dataset.pgReady = 'false';
      runBtn.disabled = true;
      stopBtn.disabled = true;
      setStatus('loading', 'Loading Otter 1.0.1 WebAssembly runtime...');

      worker = new Worker(WORKER_URL, { type: 'module' });
      worker.onmessage = (event) => {
        const msg = event.data || {};
        const handler = pending.get(msg.id);
        if (!handler) return;
        pending.delete(msg.id);
        if (msg.type === 'error') handler.reject(new Error(msg.error || 'Worker error'));
        else handler.resolve(msg);
      };
      worker.onerror = (event) => {
        const err = new Error(event.message || 'WebAssembly worker failed to load.');
        for (const [, h] of pending) h.reject(err);
        pending.clear();
        setStatus('error', err.message);
      };

      sendWorker({ type: 'init' })
        .then((res) => {
          workerReady = true;
          runtimeVersion = res.version || runtimeVersion;
          appEl.dataset.pgReady = 'true';
          runBtn.disabled = false;
          setStatus('ready', `Ready · ${runtimeVersion}`);
        })
        .catch((err) => {
          setStatus('error', `Failed to initialize WebAssembly runtime: ${err.message}`);
        });
    }

    function sendWorker(msg) {
      return new Promise((resolve, reject) => {
        const id = nextMsgId++;
        pending.set(id, { resolve, reject });
        worker.postMessage({ ...msg, id });
      });
    }

    async function executeProgram() {
      if (!workerReady || activeRunId !== null) return;
      const source = editorEl.value;
      const stdin = stdinEl.value;
      const runToken = nextMsgId;
      activeRunId = runToken;
      runBtn.disabled = true;
      stopBtn.disabled = false;
      setStatus('running', 'Compiling & running Otter program in WebAssembly...');
      runMeta.textContent = 'Running...';

      clearTimeout(watchdogTimer);
      watchdogTimer = setTimeout(() => {
        if (activeRunId === runToken) {
          stopExecution('Execution hard-stopped after watchdog timeout.');
        }
      }, TIMEOUT_MS + 1500);

      try {
        const checkRes = await sendWorker({ type: 'check', source });
        if (activeRunId !== runToken) return;
        const checkPayload = checkRes.payload || {};

        if (!checkPayload.ok) {
          clearTimeout(watchdogTimer);
          activeRunId = null;
          runBtn.disabled = false;
          stopBtn.disabled = true;
          renderDiagnostics(checkPayload.diagnostics || []);
          runMeta.textContent = 'Compile error';
          setStatus('error', `Stopped with ${(checkPayload.diagnostics || []).length} diagnostic(s)`);
          return;
        }

        if (checkPayload.hasUi) {
          const webRes = await sendWorker({ type: 'compileWeb', source, title: 'Otter Playground App' });
          if (activeRunId !== runToken) return;
          clearTimeout(watchdogTimer);
          activeRunId = null;
          runBtn.disabled = false;
          stopBtn.disabled = true;

          const payload = webRes.payload || {};
          renderDiagnostics(payload.diagnostics || []);
          if (payload.ok && payload.html) {
            previewPlaceholder.classList.add('pg-panel-hidden');
            previewFrame.classList.remove('pg-panel-hidden');
            previewFrame.srcdoc = payload.html;
            htmlView.textContent = payload.html;
            const kb = (payload.html.length / 1024).toFixed(1);
            const ms = typeof payload.elapsedMs === 'number' ? `${payload.elapsedMs.toFixed(1)} ms` : '';
            runMeta.textContent = [ms, `${kb} KB HTML`, 'River Slate UI'].filter(Boolean).join(' · ');
            consoleEl.classList.remove('pg-console-empty');
            consoleEl.textContent = `Compiled Otter Web UI app in ${ms || '<1 ms'} (${payload.html.length.toLocaleString()} bytes standalone River Slate HTML).\nRendered live in the sandboxed Preview tab.`;
            switchTab('preview');
            setStatus('ready', `Live River Slate UI compiled · ${runtimeVersion}`);
          } else {
            runMeta.textContent = 'Compile error';
            setStatus('error', `Web compile failed (${(payload.diagnostics || []).length} diagnostic(s))`);
          }
          return;
        }

        const res = await sendWorker({
          type: 'run',
          source,
          stdin,
          maxSteps: MAX_STEPS,
          timeoutMs: TIMEOUT_MS,
          maxOutputBytes: MAX_OUTPUT_BYTES
        });
        if (activeRunId !== runToken) return;
        clearTimeout(watchdogTimer);
        activeRunId = null;
        runBtn.disabled = false;
        stopBtn.disabled = true;

        const payload = res.payload || {};
        const out = payload.stdout || '';
        if (out.length > 0) {
          consoleEl.classList.remove('pg-console-empty');
          consoleEl.textContent = out;
        } else {
          consoleEl.classList.add('pg-console-empty');
          consoleEl.textContent = payload.ok
            ? '(Program finished with no output)'
            : '(No output before error)';
        }

        switchTab('console');
        renderDiagnostics(payload.diagnostics || []);
        const ms = typeof payload.elapsedMs === 'number' ? `${payload.elapsedMs.toFixed(1)} ms` : '';
        const steps = typeof payload.stepsExecuted === 'number' ? `${payload.stepsExecuted.toLocaleString()} steps` : '';
        runMeta.textContent = [ms, steps].filter(Boolean).join(' · ') || 'Done';

        if (payload.ok) {
          setStatus('ready', `Finished cleanly · ${runtimeVersion}`);
        } else {
          setStatus('error', `Stopped with ${(payload.diagnostics || []).length} diagnostic(s)`);
        }
      } catch (err) {
        if (activeRunId !== runToken) return;
        clearTimeout(watchdogTimer);
        activeRunId = null;
        runBtn.disabled = false;
        stopBtn.disabled = true;
        setStatus('error', `Execution error: ${err.message}`);
      }
    }

    function stopExecution(reason = 'Stopped by user.') {
      clearTimeout(watchdogTimer);
      activeRunId = null;
      renderDiagnostics([{ line: 1, code: 'OTTER_PLAYGROUND_STOPPED', message: reason, suggestion: 'Click Run to execute again.' }]);
      runMeta.textContent = 'Stopped';
      spawnWorker();
    }

    // Live debounced syntax check while typing
    let checkTimer = null;
    function scheduleLiveCheck() {
      clearTimeout(checkTimer);
      checkTimer = setTimeout(async () => {
        if (!workerReady || activeRunId !== null) return;
        try {
          const res = await sendWorker({ type: 'check', source: editorEl.value });
          if (activeRunId === null && res && res.payload) {
            renderDiagnostics(res.payload.diagnostics || []);
          }
        } catch {
          // ignore transient check failures
        }
      }, 380);
    }

    editorEl.addEventListener('input', () => {
      syncEditorVisuals();
      scheduleLiveCheck();
    });
    editorEl.addEventListener('scroll', syncScroll);
    editorEl.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        executeProgram();
        return;
      }
      if (e.key === 'Tab') {
        e.preventDefault();
        const start = editorEl.selectionStart;
        const end = editorEl.selectionEnd;
        editorEl.value = editorEl.value.slice(0, start) + '    ' + editorEl.value.slice(end);
        editorEl.selectionStart = editorEl.selectionEnd = start + 4;
        syncEditorVisuals();
      }
    });

    function loadExample(found, updateUrl = true) {
      currentExampleId = found.id;
      editorEl.value = found.code;
      stdinEl.value = found.stdin || '';
      stdinDetails.open = Boolean(found.stdin);
      syncEditorVisuals();
      renderDiagnostics([]);
      consoleEl.classList.add('pg-console-empty');
      consoleEl.textContent = 'Click Run (or press Ctrl/Cmd + Enter) to execute your Otter program.';
      previewFrame.srcdoc = '';
      previewFrame.classList.add('pg-panel-hidden');
      previewPlaceholder.classList.remove('pg-panel-hidden');
      htmlView.textContent = '<!-- Compile an Otter UI app to inspect the generated standalone River Slate HTML -->';
      switchTab(found.mode === 'web' ? 'preview' : 'console');
      runMeta.textContent = 'Idle';
      if (updateUrl) {
        history.replaceState(null, '', `#example=${encodeURIComponent(found.id)}`);
      }
    }

    selectEl.addEventListener('change', () => {
      const found = EXAMPLES.find((ex) => ex.id === selectEl.value);
      if (found) loadExample(found, true);
    });

    runBtn.addEventListener('click', executeProgram);
    stopBtn.addEventListener('click', () => stopExecution('Execution stopped by user.'));

    resetBtn.addEventListener('click', () => {
      const found = EXAMPLES.find((ex) => ex.id === currentExampleId) || EXAMPLES[0];
      loadExample(found, false);
    });

    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(editorEl.value);
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy Code'; }, 1400);
      } catch {
        copyBtn.textContent = 'Copy failed';
        setTimeout(() => { copyBtn.textContent = 'Copy Code'; }, 1400);
      }
    });

    shareBtn.addEventListener('click', async () => {
      const hash = encodeShareHash(editorEl.value, stdinEl.value);
      history.replaceState(null, '', hash);
      try {
        await navigator.clipboard.writeText(window.location.href);
        shareBtn.textContent = 'Link Copied!';
        setTimeout(() => { shareBtn.textContent = 'Share Link'; }, 1600);
      } catch {
        shareBtn.textContent = 'URL Updated';
        setTimeout(() => { shareBtn.textContent = 'Share Link'; }, 1600);
      }
    });

    syncEditorVisuals();
    spawnWorker();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountPlayground);
  } else {
    mountPlayground();
  }
})();
