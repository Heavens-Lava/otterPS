// starter-templates.js - Pre-built application designs for Otter Studio with dual .ot and .css

export const StarterTemplates = {
  'blank': {
    name: 'New Application',
    archetype: 'blank',
    description: 'Clean starter window ready for custom UI design',
    defaultFileName: 'untitled.ot',
    defaultMode: 'code',
    code: `# untitled.ot\n\nsay "Hello from Otter!"\n`,
    css: `/* Application Stylesheet */
#app {
    width: 720px;
    min-height: 480px;
    background: #ffffff;
    border-radius: 8px;
    padding: 24px;
    gap: 16px;
    display: flex;
    flex-direction: column;
}
`,
    load(uiModel) {
      uiModel.components.clear();
      uiModel.events.clear();
      uiModel.nameCounters = {};

      const root = uiModel.createComponent('window', {
        name: 'app',
        properties: {
          title: 'My Application',
          width: 720,
          height: 480,
          background: '#ffffff',
          padding: 24,
          spacing: 16
        }
      });
      uiModel.rootId = root.id;
      uiModel.selectedId = root.id;
      uiModel.notify('template', { name: 'blank' });
    }
  },
  'console': {
    name: 'Console Application',
    archetype: 'console',
    icon: '💻',
    badge: 'CLI Tool',
    description: 'Command-line tool with formatted output, arguments, environment scanning, and task processing',
    defaultFileName: 'main.ot',
    defaultMode: 'code',
    css: '',
    code: `# Console Application
# Command-line utility built with Otter

say "======================================"
say "   Welcome to Otter CLI Utility       "
say "======================================"
say ""

say "Scanning system environment..."
get environment variable "OS" into osName
say "Operating System:" osName

say ""
say "Processing tasks..."
step is 0
items is ["System Check", "Data Sync", "Cache Cleanup"]

for each item in items
    step is step + 1
    say "  [" step "/ 3] Running" item "..."
.

say ""
say "All tasks finished successfully! 🐾"
`,
    load(uiModel) {
      StarterTemplates['blank'].load(uiModel);
    }
  },
  'desktop': {
    name: 'Desktop Application',
    archetype: 'desktop',
    icon: '🪟',
    badge: 'UI Designer',
    description: 'Interactive windowed application with visual widgets, buttons, forms, and layout hierarchy',
    defaultFileName: 'app.ot',
    defaultMode: 'designer',
    css: `/* Desktop Application Styles */

/* Free layout: controls stay exactly where they are placed in the designer
   (like a Visual Studio form). Rows, columns and cards inside it arrange
   their own children. The window's title is its title bar. */
#app {
    --otter-layout: free;
    position: relative;
    width: 720px;
    min-height: 480px;
    background: #ffffff;
    border-radius: 10px;
    padding: 24px;
}

#app > .otter-window-header {
    display: none;
}

#headerTitle {
    position: absolute;
    left: 24px;
    top: 24px;
    font-size: 22px;
    font-weight: 700;
    color: #0f172a;
}

#actionCard {
    position: absolute;
    left: 24px;
    top: 76px;
    width: 460px;
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

#primaryBtn {
    background: #2563eb;
    color: #ffffff;
    border-radius: 6px;
    padding: 8px 16px;
    font-weight: 600;
}
`,
    code: `# Desktop Application
# Visual UI event bindings and application logic

window "app" has title "My Desktop Application"

button "primaryBtn" was clicked
    say "Primary button was pressed!"
.
`,
    load(uiModel) {
      uiModel.components.clear();
      uiModel.events.clear();
      uiModel.nameCounters = {};

      const root = uiModel.createComponent('window', {
        name: 'app',
        properties: {
          title: 'My Desktop Application',
          width: 720,
          height: 480,
          background: '#ffffff',
          padding: 24,
          spacing: 16
        }
      });
      uiModel.rootId = root.id;

      const title = uiModel.createComponent('text', {
        name: 'headerTitle',
        properties: { text: 'My Desktop Application', size: 22 }
      });

      const card = uiModel.createComponent('card', {
        name: 'actionCard',
        properties: { padding: 16 }
      });

      const row = uiModel.createComponent('row', { name: 'actionRow' });
      const input = uiModel.createComponent('text box', {
        name: 'userInput',
        properties: { placeholder: 'Your name' }
      });
      const btn = uiModel.createComponent('primary button', {
        name: 'primaryBtn',
        properties: { text: 'Say hello' }
      });

      row.children.push(input.id, btn.id);
      input.parentId = row.id;
      btn.parentId = row.id;
      card.children.push(row.id);
      row.parentId = card.id;

      root.children.push(title.id, card.id);
      title.parentId = root.id;
      card.parentId = root.id;

      // A starter that does what it says: greet whoever typed their name.
      uiModel.setEvent(btn.id, 'clicked', 'name is text of userInput\ntext of headerTitle is "Hello, " and name and "!"');
      uiModel.select(root.id);
      uiModel.notify('template', { name: 'desktop' });
    }
  },
  'web': {
    name: 'Website',
    archetype: 'web',
    description: 'A landing page: navigation, a hero, features and a footer, responsive from the start',
    defaultFileName: 'web-app.ot',
    defaultMode: 'designer',
    // Rows wrap and cards share the width, so it works on a phone as it is.
    css: `/* Website Stylesheet: a starting point; change anything. */
#app {
    font-family: "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
}

#siteNav {
    padding: 18px 32px;
    border-bottom: 1px solid #e2e8f0;
}

#brand {
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.01em;
}

#navLinks {
    width: auto;
}

#navLinks > .otter-link {
    color: #334155;
    text-decoration: none;
    font-weight: 500;
}

#hero {
    padding: 88px 32px 72px;
    max-width: 880px;
    margin: 0 auto;
    align-items: center;
    text-align: center;
    gap: 18px;
}

#heroBadge {
    background: #eef2ff;
    color: #3730a3;
    padding: 4px 12px;
    border-radius: 999px;
    font-size: 13px;
    font-weight: 600;
}

#heroTitle {
    font-size: clamp(34px, 6vw, 56px);
    line-height: 1.08;
    letter-spacing: -0.02em;
    font-weight: 800;
    margin: 0;
}

#heroText {
    font-size: 19px;
    line-height: 1.6;
    color: #475569;
    max-width: 640px;
}

#heroActions {
    width: auto;
}

#getStarted {
    background: #2563eb;
    color: #ffffff;
    padding: 12px 22px;
    border-radius: 8px;
    font-weight: 600;
    text-decoration: none;
}

#learnMore {
    padding: 12px 18px;
    color: #0f172a;
    font-weight: 600;
    text-decoration: none;
}

#features {
    padding: 64px 32px;
    background: #f8fafc;
    gap: 28px;
}

#featuresTitle {
    font-size: 30px;
    font-weight: 700;
    text-align: center;
    margin: 0;
}

#featureRow {
    max-width: 1080px;
    margin: 0 auto;
}

#featureRow > * {
    flex: 1 1 260px;
    background: #ffffff;
    border: 1px solid #e2e8f0;
    border-radius: 12px;
    padding: 24px;
}

.feature-title,
#featureOneTitle,
#featureTwoTitle,
#featureThreeTitle {
    font-size: 18px;
    font-weight: 700;
}

#featureOneText,
#featureTwoText,
#featureThreeText {
    color: #475569;
    line-height: 1.6;
}

#footer {
    padding: 28px 32px;
    border-top: 1px solid #e2e8f0;
    color: #64748b;
}

#contactLink {
    color: #2563eb;
    text-decoration: none;
    font-weight: 500;
}
`,
    load(uiModel) {
      uiModel.components.clear();
      uiModel.events.clear();
      uiModel.nameCounters = {};

      // No schema defaults: the stylesheet below gives the look, and a
      // default in the source (an inline style) would override it.
      const make = (kind, name, properties = {}) => uiModel.createComponent(kind, { name, properties, defaults: false });
      const put = (parent, ...kids) => {
        for (const kid of kids) {
          parent.children.push(kid.id);
          kid.parentId = parent.id;
        }
      };

      // A web page, not a desktop window: it fills the browser.
      const root = make('window', 'app', { title: 'My Website', width: 'full', hideheader: true, spacing: 0, padding: 0, background: '#ffffff', foreground: '#0f172a' });
      uiModel.rootId = root.id;
      uiModel.rootKind = 'page';

      const nav = make('row', 'siteNav', { width: 'full', spread: true, wrap: true, spacing: 16 });
      const brand = make('text', 'brand', { text: 'Your Company' });
      const navLinks = make('row', 'navLinks', { spacing: 24, wrap: true });
      put(navLinks,
        make('link', 'featuresLink', { text: 'Features', url: '#features' }),
        make('link', 'contactNavLink', { text: 'Contact', url: '#footer' }));
      put(nav, brand, navLinks);

      const hero = make('column', 'hero', { width: 'full', align: 'center', spacing: 18 });
      put(hero,
        make('badge', 'heroBadge', { text: 'Built with Otter' }),
        make('heading', 'heroTitle', { text: 'A website your customers will love' }),
        make('text', 'heroText', { text: 'Say what you do, show why it matters, and make it easy to get in touch. Change every word and colour in the Designer.' }));
      const actions = make('row', 'heroActions', { spacing: 12, wrap: true });
      put(actions,
        make('link', 'getStarted', { text: 'Get started', url: '#features' }),
        make('link', 'learnMore', { text: 'Learn more →', url: '#features' }));
      put(hero, actions);

      // Named "features" so the Features link (#features) jumps here.
      const features = make('column', 'features', { width: 'full', spacing: 28 });
      const featureRow = make('row', 'featureRow', { width: 'full', spacing: 20, wrap: true, align: 'top' });
      const feature = (key, title, text) => {
        const card = make('column', `feature${key}`, { spacing: 8 });
        put(card, make('text', `feature${key}Title`, { text: title }), make('text', `feature${key}Text`, { text }));
        return card;
      };
      put(featureRow,
        feature('One', 'Fast', 'Pages compile to plain HTML, CSS and JavaScript: nothing to install for your visitors.'),
        feature('Two', 'Yours', 'Every part is readable Otter you can open, change and keep.'),
        feature('Three', 'Everywhere', 'The layout wraps on its own, from a wide screen to a phone.'));
      put(features, make('heading', 'featuresTitle', { text: 'Why people choose us' }), featureRow);

      const footer = make('row', 'footer', { width: 'full', spread: true, wrap: true, spacing: 12 });
      put(footer,
        make('text', 'copyright', { text: '© 2026 Your Company' }),
        make('link', 'contactLink', { text: 'hello@example.com', url: 'mailto:hello@example.com' }));

      put(root, nav, hero, features, footer);
      uiModel.select(root.id);
      uiModel.notify('template', { name: 'web' });
    }
  },
  'game': {
    name: '2D Game (Otter River Catch)',
    archetype: 'game',
    icon: '🎮',
    badge: '2D Game Canvas',
    description: 'Interactive 2D arcade game with game loop, keyboard controls, collision, and score counter',
    defaultFileName: 'game.ot',
    defaultMode: 'preview',
    css: `/* 2D Game Stylesheet */
#app {
    width: 100%;
    min-height: 560px;
    background: #0f172a;
    color: #ffffff;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 20px;
    user-select: none;
}

#gameCanvasBox {
    background: linear-gradient(180deg, #1e3a8a 0%, #0c4a6e 100%);
    border: 3px solid #38bdf8;
    border-radius: 12px;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
    overflow: hidden;
    position: relative;
}

#hudRow {
    width: 640px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 0;
    font-weight: 700;
    font-size: 16px;
}
`,
    code: `# 2D Game: Otter River Catch
# Move the otter left and right (A / D or Arrow Keys) to catch river pearls!

game "Otter River Catch"
    width is 640
    height is 440
    score is 0
    playerX is 280
    playerY is 380
    pearlX is 200
    pearlY is 30
    pearlSpeed is 4

    on tick
        pearlY is pearlY + pearlSpeed
        if pearlY > 410
            # Missed pearl, reset
            pearlY is 30
            pearlX is random from 40 to 600
        .

        # Check collision with otter
        if pearlY is at least 370 and pearlY is at most 390
            diff is pearlX - playerX
            if diff is at least -30 and diff is at most 30
                score is score + 10
                say "Caught pearl! Score: " score
                pearlY is 30
                pearlX is random from 40 to 600
            .
        .
    .

    on key "ArrowLeft" or key "a"
        playerX is playerX - 18
    .

    on key "ArrowRight" or key "d"
        playerX is playerX + 18
    .
.
`,
    load(uiModel) {
      StarterTemplates['blank'].load(uiModel);
    }
  },
  'task-manager': {
    name: 'Task Manager',
    description: 'Responsive task manager with inputs, buttons, and card lists',
    css: `/* Task Manager Stylesheet - Canonical CSS */
#app {
    width: 740px;
    min-height: 540px;
    background: #0f172a;
    color: #f8fafc;
    border-radius: 12px;
    padding: 20px;
    gap: 16px;
    display: flex;
    flex-direction: column;
}

#headerRow {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

#appTitle {
    font-size: 24px;
    font-weight: 700;
    color: #f8fafc;
}

#filterBtn {
    background: #1e293b;
    color: #94a3b8;
    border-radius: 6px;
    padding: 6px 12px;
    font-size: 13px;
    border: 1px solid #334155;
    cursor: pointer;
    transition: all 0.15s ease;
}

#filterBtn:hover {
    background: #334155;
    color: #f8fafc;
}

#inputCard {
    width: 100%;
    background: #1e293b;
    border-radius: 10px;
    padding: 12px;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2);
}

#inputRow {
    width: 100%;
    display: flex;
    gap: 10px;
    align-items: center;
}

#taskInput {
    flex: 1;
    background: #0f172a;
    color: #f8fafc;
    border: 1px solid #334155;
    border-radius: 6px;
    height: 40px;
    padding: 0 14px;
    font-size: 14px;
}

#addBtn {
    background: #2563eb;
    color: #ffffff;
    border-radius: 6px;
    height: 40px;
    padding: 0 18px;
    font-weight: 600;
    cursor: pointer;
    border: none;
    transition: background 0.15s ease;
}

#addBtn:hover {
    background: #1d4ed8;
}

#taskList {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.task-item {
    width: 100%;
    background: #1e293b;
    border-radius: 8px;
    padding: 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-left: 3px solid #3b82f6;
    transition: transform 0.15s ease;
}

.task-item:hover {
    transform: translateX(2px);
}

#del1, #del2, #del3 {
    background: rgba(239, 68, 68, 0.15);
    color: #ef4444;
    border: 1px solid rgba(239, 68, 68, 0.3);
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 12px;
    cursor: pointer;
}

#del1:hover, #del2:hover, #del3:hover {
    background: #ef4444;
    color: #ffffff;
}
`,
    load(uiModel) {
      uiModel.components.clear();
      uiModel.events.clear();

      const root = uiModel.createComponent('window', {
        name: 'app',
        properties: {
          title: 'Task Manager'
        }
      });
      uiModel.rootId = root.id;

      // Header row
      const headerRow = uiModel.createComponent('row', { name: 'headerRow' });
      const title = uiModel.createComponent('heading', {
        name: 'appTitle',
        properties: { text: 'Active Tasks' }
      });
      const filterBtn = uiModel.createComponent('button', {
        name: 'filterBtn',
        properties: { text: 'All Tasks (3)' }
      });
      headerRow.children.push(title.id, filterBtn.id);
      title.parentId = headerRow.id;
      filterBtn.parentId = headerRow.id;

      // Input card
      const inputCard = uiModel.createComponent('card', { name: 'inputCard' });
      const inputRow = uiModel.createComponent('row', { name: 'inputRow' });
      const taskInput = uiModel.createComponent('text box', {
        name: 'taskInput',
        properties: { placeholder: 'Add a new task description...' }
      });
      const addBtn = uiModel.createComponent('primary button', {
        name: 'addBtn',
        properties: { text: '+ Add Task' }
      });
      inputRow.children.push(taskInput.id, addBtn.id);
      taskInput.parentId = inputRow.id;
      addBtn.parentId = inputRow.id;
      inputCard.children.push(inputRow.id);
      inputRow.parentId = inputCard.id;

      // Task list column
      const taskList = uiModel.createComponent('column', { name: 'taskList' });

      // Task 1
      const task1 = uiModel.createComponent('card', { name: 'task1' });
      const task1Row = uiModel.createComponent('row', { name: 'task1Row' });
      const check1 = uiModel.createComponent('checkbox', {
        name: 'check1',
        properties: { text: 'Compile Otter documentation site', checked: true }
      });
      const del1 = uiModel.createComponent('danger button', {
        name: 'del1',
        properties: { text: 'Remove' }
      });
      task1Row.children.push(check1.id, del1.id);
      check1.parentId = task1Row.id;
      del1.parentId = task1Row.id;
      task1.children.push(task1Row.id);
      task1Row.parentId = task1.id;

      // Task 2
      const task2 = uiModel.createComponent('card', { name: 'task2' });
      const task2Row = uiModel.createComponent('row', { name: 'task2Row' });
      const check2 = uiModel.createComponent('checkbox', {
        name: 'check2',
        properties: { text: 'Ship desktop runtime for Windows & macOS', checked: false }
      });
      const del2 = uiModel.createComponent('danger button', {
        name: 'del2',
        properties: { text: 'Remove' }
      });
      task2Row.children.push(check2.id, del2.id);
      check2.parentId = task2Row.id;
      del2.parentId = task2Row.id;
      task2.children.push(task2Row.id);
      task2Row.parentId = task2.id;

      // Task 3
      const task3 = uiModel.createComponent('card', { name: 'task3' });
      const task3Row = uiModel.createComponent('row', { name: 'task3Row' });
      const check3 = uiModel.createComponent('checkbox', {
        name: 'check3',
        properties: { text: 'Integrate Otter Studio visual CSS editor', checked: true }
      });
      const del3 = uiModel.createComponent('danger button', {
        name: 'del3',
        properties: { text: 'Remove' }
      });
      task3Row.children.push(check3.id, del3.id);
      check3.parentId = task3Row.id;
      del3.parentId = task3Row.id;
      task3.children.push(task3Row.id);
      task3Row.parentId = task3.id;

      taskList.children.push(task1.id, task2.id, task3.id);
      task1.parentId = taskList.id;
      task2.parentId = taskList.id;
      task3.parentId = taskList.id;

      // Put into root
      root.children.push(headerRow.id, inputCard.id, taskList.id);
      headerRow.parentId = root.id;
      inputCard.parentId = root.id;
      taskList.parentId = root.id;

      // Event handlers in Otter
      uiModel.setEvent(addBtn.id, 'clicked', `say "Adding new task..."\ntaskInput has text ""`);
      uiModel.setEvent(del1.id, 'clicked', `say "Removed item 1"`);

      uiModel.select(root.id);
      uiModel.notify('template', { name: 'task-manager' });
    }
  }
};
