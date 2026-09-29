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
        properties: { placeholder: 'Type something here...' }
      });
      const btn = uiModel.createComponent('primary button', {
        name: 'primaryBtn',
        properties: { text: 'Click Me' }
      });

      row.children.push(input.id, btn.id);
      input.parentId = row.id;
      btn.parentId = row.id;
      card.children.push(row.id);
      row.parentId = card.id;

      root.children.push(title.id, card.id);
      title.parentId = root.id;
      card.parentId = root.id;

      uiModel.setEvent(btn.id, 'clicked', 'say "Primary button was pressed!"');
      uiModel.select(root.id);
      uiModel.notify('template', { name: 'desktop' });
    }
  },
  'web': {
    name: 'Web Application',
    archetype: 'web',
    icon: '🌐',
    badge: 'Reactive Web',
    description: 'Modern responsive web application with interactive components and CSS styling',
    defaultFileName: 'web-app.ot',
    defaultMode: 'split',
    css: `/* Web Application Stylesheet */
#app {
    width: 100%;
    min-height: 520px;
    background: #f8fafc;
    padding: 32px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
}

#heroCard {
    width: 680px;
    background: #ffffff;
    border-radius: 12px;
    padding: 28px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
    display: flex;
    flex-direction: column;
    gap: 16px;
    text-align: center;
}

#heroTitle {
    font-size: 26px;
    font-weight: 800;
    color: #1e293b;
}

#counterBadge {
    font-size: 28px;
    font-weight: 700;
    color: #2563eb;
    margin: 8px 0;
}
`,
    code: `# Web Application
# Interactive reactive web page in Otter

page "app"
    card "heroCard"
        heading "heroTitle" text "Welcome to Otter Web App"
        paragraph text "Build fast, reactive web apps with Otter syntax."

        badge "counterBadge" text "Clicks: 0"

        row
            button "incBtn" text "+ Increment"
            button "resetBtn" text "Reset"
        .
    .
.

clicks is 0

button "incBtn" was clicked
    clicks is clicks + 1
    badge "counterBadge" has text "Clicks: " clicks
.

button "resetBtn" was clicked
    clicks is 0
    badge "counterBadge" has text "Clicks: 0"
.
`,
    load(uiModel) {
      uiModel.components.clear();
      uiModel.events.clear();
      uiModel.nameCounters = {};

      const root = uiModel.createComponent('window', {
        name: 'app',
        properties: {
          title: 'Otter Web Application',
          width: 720,
          height: 520,
          background: '#f8fafc',
          padding: 28,
          spacing: 16
        }
      });
      uiModel.rootId = root.id;

      const hero = uiModel.createComponent('card', {
        name: 'heroCard',
        properties: { padding: 24 }
      });

      const title = uiModel.createComponent('text', {
        name: 'heroTitle',
        properties: { text: 'Welcome to Otter Web App', size: 24 }
      });

      const badge = uiModel.createComponent('text', {
        name: 'counterBadge',
        properties: { text: 'Clicks: 0' }
      });

      const row = uiModel.createComponent('row', { name: 'btnRow' });
      const incBtn = uiModel.createComponent('primary button', {
        name: 'incBtn',
        properties: { text: '+ Increment' }
      });
      const resetBtn = uiModel.createComponent('button', {
        name: 'resetBtn',
        properties: { text: 'Reset' }
      });

      row.children.push(incBtn.id, resetBtn.id);
      incBtn.parentId = row.id;
      resetBtn.parentId = row.id;

      hero.children.push(title.id, badge.id, row.id);
      title.parentId = hero.id;
      badge.parentId = hero.id;
      row.parentId = hero.id;

      root.children.push(hero.id);
      hero.parentId = root.id;

      uiModel.setEvent(incBtn.id, 'clicked', 'say "Increment clicked!"');
      uiModel.setEvent(resetBtn.id, 'clicked', 'say "Reset clicked!"');
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
