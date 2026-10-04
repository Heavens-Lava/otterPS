# Otter Tutorials: Complete Step-by-Step Practical Guide

Welcome to the official Otter tutorial suite. This guide walks you through building real-world software across every supported target—from single-line scripts to full-stack web and 2D canvas games.

---

## Table of Contents
1. [Hello World](#1-hello-world)
2. [Command Line Utility (CLI)](#2-command-line-utility-cli)
3. [System Automation & Filesystem](#3-system-automation--filesystem)
4. [Desktop Application with Visual UI](#4-desktop-application-with-visual-ui)
5. [Web Application with Responsive Layout](#5-web-application-with-responsive-layout)
6. [Services & REST API Backend](#6-services--rest-api-backend)
7. [Data Processing & Database Querying](#7-data-processing--database-querying)
8. [2D Game Development with Canvas Loop](#8-2d-game-development-with-canvas-loop)
9. [Full-Stack Application Architecture](#9-full-stack-application-architecture)
10. [Creating & Publishing an Otter Package](#10-creating--publishing-an-otter-package)
11. [Developing an Otter Studio Extension](#11-developing-an-otter-studio-extension)

---

## 1. Hello World

The traditional starting point. Otter programs are clean, natural, and expressive.

```otter
# hello.ot
say "Hello from Otter!"
```

### Running Your Program
```bash
otter run hello.ot
```

### Key Concept: Natural Statements
- Otter statements do not use semicolons.
- Variable assignment uses `is`:
  ```otter
  name is "Jeff"
  say "Hello, " and name
  ```

---

## 2. Command Line Utility (CLI)

Build an interactive command-line tool with user prompts, options, and exit codes.

```otter
# cli_tool.ot
say "=== Otter Greeter CLI ==="
say "What is your name?"
user is ask

if user is ""
    say "Error: Name cannot be blank."
    stop
.

say "Welcome to Otter, " and user and "!"
```

### Running with Arguments
```bash
otter run cli_tool.ot
```

---

## 3. System Automation & Filesystem

Otter excels at filesystem administration, log parsing, and file organization.

```otter
# backup.ot
sourceDir is "projects/app"
backupDir is "backups/app_backup"

if not file sourceDir exists
    say "Source directory not found: " and sourceDir
    stop
.

say "Starting automated backup..."
write "Backup timestamp: " to (backupDir and "/log.txt") atomically
say "Backup completed successfully."
```

---

## 4. Desktop Application with Visual UI

Otter provides first-class native desktop windowing with declarative controls and reactive events.

```otter
# counter_app.ot
app is a window with title "Otter Counter", width 400, height 300, spacing 12, padding 16

count is 0
counterLabel is a heading with text "Current Count: 0", size 20

incrementBtn is a button with text "Increment Count", round
resetBtn is a button with text "Reset", round

put counterLabel, incrementBtn, resetBtn in app

when incrementBtn is clicked
    add 1 to count
    counterLabel.text is "Current Count: " and count
.

when resetBtn is clicked
    count is 0
    counterLabel.text is "Current Count: 0"
.

show app
```

---

## 5. Web Application with Responsive Layout

Build responsive, client-side single page applications (SPAs) with Otter Web Target.

```otter
# web_app.ot
title is "Otter Web Portal"

hero is a column with spacing 16, padding 24, background "#0f172a"
titleText is a heading with text "Otter Web Application", size 28, foreground "#38bdf8"
subtitle is a text with text "Modern, safe, natural programming for the browser."

actionBtn is a button with text "Explore Features", round, background "#0284c7", foreground "#ffffff"

put titleText, subtitle, actionBtn in hero

when actionBtn is clicked
    say "Navigating to features overview..."
.
```

### Compiling to Web
```bash
otter.ps1 web web_app.ot -NoOpen
```

---

## 6. Services & REST API Backend

Otter Backend Target lets you build high-performance microservices and API gateways.

```otter
# api_service.ot
use http

server is create http server with port 8080

on request to "/api/status" do
    return json {
        "status": "healthy",
        "service": "otter-orders-api",
        "uptime": 3600
    }
.

on request to "/api/calculate" with payload do
    subtotal is payload.subtotal
    taxRate is 0.08
    tax is subtotal multiplied by taxRate
    total is subtotal and tax
    return json { "subtotal": subtotal, "tax": tax, "total": total }
.

start server
```

---

## 7. Data Processing & Database Querying

Filter, transform, and aggregate structured datasets using Otter's natural query primitives.

```otter
# query_data.ot
employees is [
    { "id": 1, "name": "Alice", "department": "Engineering", "salary": 95000 },
    { "id": 2, "name": "Bob", "department": "Design", "salary": 82000 },
    { "id": 3, "name": "Carol", "department": "Engineering", "salary": 110000 }
]

engineers is []
totalEngineeringSalary is 0

for each emp in employees
    if emp.department is "Engineering"
        add emp to engineers
        add emp.salary to totalEngineeringSalary
    .
.

say "Found " and (count of engineers) and " engineers."
say "Total payroll: $" and totalEngineeringSalary
```

---

## 8. 2D Game Development with Canvas Loop

Build smooth, 60 FPS 2D action games with delta timing, sprite kinematics, and collision detection.

```otter
# game.ot
game is a canvas with width 800, height 600, targetFps 60

ballX is 400
ballY is 300
velocityX is 4
velocityY is 3
radius is 15

when game tick with delta
    add velocityX to ballX
    add velocityY to ballY

    if ballX is less than radius or ballX is greater than (800 - radius)
        velocityX is 0 - velocityX
    .

    if ballY is less than radius or ballY is greater than (600 - radius)
        velocityY is 0 - velocityY
    .

    clear canvas
    draw circle at ballX, ballY with radius radius, color "#38bdf8"
.

start game
```

---

## 9. Full-Stack Application Architecture

Organize multi-tier solutions sharing domain models across frontend, backend, and CLI.

```
MySolution/
├── solution.json
├── shared/
│   └── models.ot          # Shared types, validation rules, constants
├── backend/
│   └── service.ot         # REST API server & database layer
├── desktop/
│   └── main.ot            # Visual desktop client
└── web/
    └── app.ot             # Responsive web SPA
```

### Shared Contract (`shared/models.ot`)
```otter
function validateUser with name, email
    if name is "" or email is ""
        return false
    .
    return true
.
```

---

## 10. Creating & Publishing an Otter Package

Create reusable libraries and distribute them to the Otter Package Registry.

### 1. Initialize Manifest (`project.json`)
```json
{
  "name": "otter-string-utils",
  "version": "1.0.0",
  "author": "Jeff",
  "license": "MIT",
  "entryPoint": "lib/strings.ot",
  "exports": ["capitalize", "slugify"]
}
```

### 2. Implement Library Code (`lib/strings.ot`)
```otter
function capitalize with text
    if text is ""
        return ""
    .
    firstChar is slice text from 1 to 1
    rest is slice text from 2 to (count of text)
    return (uppercase firstChar) and rest
.
```

### 3. Pack & Publish
```bash
otter pack
otter publish
```

---

## 11. Developing an Otter Studio Extension

Extend Otter Studio with custom commands, themes, sidebars, and diagnostic linters.

### Extension Manifest (`extension.json`)
```json
{
  "id": "otter-markdown-preview",
  "name": "Otter Markdown Live Preview",
  "version": "1.0.0",
  "main": "index.js",
  "contributes": {
    "commands": [
      { "id": "md.preview", "title": "Markdown: Open Live Preview" }
    ],
    "views": [
      { "id": "mdPreviewPanel", "name": "Markdown Preview", "location": "secondary" }
    ]
  },
  "permissions": ["ui:panels", "workspace:read"]
}
```

### Extension Logic (`index.js`)
```javascript
export function activate(context) {
  context.commands.registerCommand('md.preview', () => {
    const activeDoc = context.workspace.getActiveDocument();
    context.panels.createOrShow('mdPreviewPanel', {
      title: 'Preview: ' + activeDoc.path,
      content: renderMarkdown(activeDoc.content)
    });
  });
}

export function deactivate() {
  // Clean up timers and panel subscriptions
}
```
