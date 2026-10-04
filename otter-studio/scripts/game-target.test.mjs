// game-target.test.mjs - Comprehensive Test Suite for Section 17: 2D Game Target
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  GameLoop,
  InputManager,
  SpriteAnimation,
  Collision2D,
  SoundEngine,
  Scene,
  SceneManager,
  Camera2D,
  TileMap2D,
  ArcadePhysics2D,
  AssetManager,
  SaveDataManager,
  GameProfiler,
  generatePlayableGameHtml,
  exportWebGame,
  exportDesktopGame
} from '../js/project/game-target-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ----------------------------------------------------------------------------
// 1. Game Loop & Delta Time (Section 17.2, 17.3)
// ----------------------------------------------------------------------------
test('Section 17.2, 17.3: Game Loop Fixed Timestep & Delta Time', () => {
  let updateTicks = 0;
  let renderTicks = 0;

  const loop = new GameLoop({
    fps: 60,
    update: (dt) => { updateTicks++; },
    render: (alpha, dt) => { renderTicks++; }
  });

  loop.start();
  assert.equal(loop.running, true);

  // Initial tick to establish time baseline, then advance 100ms
  loop.tick(0);
  loop.tick(100);
  // Fixed step is 1/60s (~16.6ms). 100ms should execute ~6 fixed updates
  assert.ok(updateTicks >= 5 && updateTicks <= 7);
  assert.equal(renderTicks, 1);

  loop.stop();
  assert.equal(loop.running, false);
});

// ----------------------------------------------------------------------------
// 2. Keyboard, Mouse & Gamepad Input (Section 17.4, 17.18)
// ----------------------------------------------------------------------------
test('Section 17.4, 17.18: Unified Input Manager (Keyboard, Mouse, Gamepad)', () => {
  const input = new InputManager();

  // Keyboard input
  input.handleKeyDown('ArrowRight');
  assert.equal(input.isDown('ArrowRight'), true);
  assert.equal(input.isPressed('ArrowRight'), true);

  const axis = input.getAxisVector();
  assert.equal(axis.x, 1);
  assert.equal(axis.y, 0);

  input.endFrame();
  assert.equal(input.isPressed('ArrowRight'), false); // single-frame press cleared
  assert.equal(input.isDown('ArrowRight'), true);     // still held down

  // Gamepad input
  input.updateGamepad([-0.8, 0.6], [false, true]);
  assert.equal(input.gamepad.connected, true);
  assert.equal(input.gamepad.buttons[1], true);

  // Mouse input
  input.handleMouseMove(320, 240);
  input.handleMouseDown();
  assert.equal(input.mouse.x, 320);
  assert.equal(input.mouse.down, true);
  assert.equal(input.mouse.clicked, true);
});

// ----------------------------------------------------------------------------
// 3. Sprites & Animation Sequencer (Section 17.5)
// ----------------------------------------------------------------------------
test('Section 17.5: Sprite Animation Sequencer', () => {
  const anim = new SpriteAnimation({
    frames: [0, 1, 2, 3],
    fps: 10,
    loop: true
  });

  assert.equal(anim.getCurrentFrame(), 0);
  anim.update(0.1); // 1 frame duration (1/10s)
  assert.equal(anim.getCurrentFrame(), 1);

  anim.update(0.3); // advance 3 frames -> loops back
  assert.equal(anim.getCurrentFrame(), 0);
});

// ----------------------------------------------------------------------------
// 4. Collision 2D: AABB, Circle & Raycast (Section 17.6)
// ----------------------------------------------------------------------------
test('Section 17.6: Collision 2D Systems', () => {
  const rectA = { x: 10, y: 10, width: 30, height: 30 };
  const rectB = { x: 25, y: 25, width: 30, height: 30 };
  const rectC = { x: 100, y: 100, width: 30, height: 30 };

  assert.equal(Collision2D.aabb(rectA, rectB), true);
  assert.equal(Collision2D.aabb(rectA, rectC), false);

  const circleA = { x: 50, y: 50, radius: 20 };
  const circleB = { x: 70, y: 50, radius: 10 };
  const circleC = { x: 200, y: 200, radius: 10 };

  assert.equal(Collision2D.circle(circleA, circleB), true);
  assert.equal(Collision2D.circle(circleA, circleC), false);

  // Raycast
  const hit = Collision2D.raycastAabb({ x: 0, y: 20 }, { x: 1, y: 0 }, rectA);
  assert.ok(hit);
  assert.equal(hit.point.x, 10);
  assert.equal(hit.point.y, 20);
});

// ----------------------------------------------------------------------------
// 5. Sound & Audio Synthesis (Section 17.7)
// ----------------------------------------------------------------------------
test('Section 17.7: Audio Synthesis Engine', () => {
  const sound = new SoundEngine();
  const coin = sound.playCoinSound();
  assert.equal(coin.synthType, 'square');
  assert.ok(coin.frequency > 900);

  const jump = sound.playJumpSound();
  assert.equal(jump.synthType, 'triangle');

  const exp = sound.playExplosionSound();
  assert.equal(exp.synthType, 'sawtooth');
  assert.equal(sound.history.length, 3);
});

// ----------------------------------------------------------------------------
// 6. Scene Management (Section 17.8)
// ----------------------------------------------------------------------------
test('Section 17.8: Scene Management & Lifecycle Transitions', () => {
  const sm = new SceneManager();
  let menuEntered = false;
  let gameEntered = false;
  let menuExited = false;

  class MenuScene extends Scene {
    onEnter() { menuEntered = true; }
    onExit() { menuExited = true; }
  }

  class GameScene extends Scene {
    onEnter() { gameEntered = true; }
  }

  sm.addScene('menu', new MenuScene('menu'));
  sm.addScene('game', new GameScene('game'));

  sm.switchScene('menu');
  assert.equal(menuEntered, true);
  assert.equal(sm.currentScene.name, 'menu');

  sm.switchScene('game');
  assert.equal(menuExited, true);
  assert.equal(gameEntered, true);
  assert.equal(sm.currentScene.name, 'game');
});

// ----------------------------------------------------------------------------
// 7. 2D Camera Following & Shake (Section 17.9)
// ----------------------------------------------------------------------------
test('Section 17.9: 2D Camera Following and Shake', () => {
  const cam = new Camera2D(800, 600);
  cam.follow(400, 300, 1.0); // instant follow

  assert.equal(cam.x, 0);
  assert.equal(cam.y, 0);

  cam.shake(15, 0.5);
  cam.update(0.1);
  const offset = cam.getOffset();
  assert.ok(offset.x !== 0 || offset.y !== 0 || cam.shakeIntensity > 0);
});

// ----------------------------------------------------------------------------
// 8. Tile Maps & Solid Collisions (Section 17.10)
// ----------------------------------------------------------------------------
test('Section 17.10: Tile Map Representation and Solid Queries', () => {
  const map = new TileMap2D({
    tileSize: 32,
    width: 3,
    height: 3,
    data: [
      0, 0, 0,
      1, 1, 1,
      1, 1, 1
    ],
    collisionTiles: [1]
  });

  assert.equal(map.getTile(0, 0), 0);
  assert.equal(map.getTile(1, 1), 1);
  assert.equal(map.isSolid(10, 10), false); // row 0, col 0 is 0 (air)
  assert.equal(map.isSolid(10, 40), true);  // row 1, col 0 is 1 (solid ground)
});

// ----------------------------------------------------------------------------
// 9. Arcade Physics 2D (Section 17.11)
// ----------------------------------------------------------------------------
test('Section 17.11: 2D Kinematic / Arcade Physics Strategy', () => {
  const physics = new ArcadePhysics2D({ gravity: 1000 });
  const body = { x: 0, y: 0, vx: 100, vy: 0, grounded: false };

  physics.applyPhysics(body, 0.1);
  assert.equal(body.x, 10);
  assert.equal(body.y, 10);
  assert.equal(body.vy, 100);
});

// ----------------------------------------------------------------------------
// 10. Assets, Save Data & Profiler (Section 17.12, 17.13, 17.15)
// ----------------------------------------------------------------------------
test('Section 17.12, 17.13, 17.15: Asset Manager, Save System & Profiler', () => {
  // Asset Manager
  const assets = new AssetManager();
  assets.register('hero', 'image', 'assets/hero.png');
  assert.equal(assets.get('hero').source, 'assets/hero.png');

  // Save Data Manager
  const saves = new SaveDataManager();
  saves.save('slot_1', { level: 3, score: 1540 });
  const loaded = saves.load('slot_1');
  assert.equal(loaded.level, 3);
  assert.equal(loaded.score, 1540);

  // Profiler
  const profiler = new GameProfiler();
  profiler.updateMetrics(60, 16.4, 24, 150);
  const overlay = profiler.formatOverlay();
  assert.match(overlay, /FPS: 60/);
  assert.match(overlay, /16\.4ms/);
  assert.match(overlay, /DrawCalls: 24/);
  assert.match(overlay, /Entities: 150/);
});

// ----------------------------------------------------------------------------
// 11. Production-Certify Generated Playable Game (Section 17.1, 17.14, 17.16, 17.17)
// ----------------------------------------------------------------------------
test('Section 17.1, 17.14, 17.16, 17.17: Playable Game Export Pipeline (Web & Desktop)', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-game-app');

  try {
    const webRes = exportWebGame({
      outputDir: testOutDir,
      title: 'Otter Platformer Deluxe',
      width: 800,
      height: 600
    });

    assert.equal(webRes.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'index.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'game.json')));

    const htmlContent = fs.readFileSync(path.join(testOutDir, 'index.html'), 'utf8');
    assert.match(htmlContent, /Otter Platformer Deluxe/);
    assert.match(htmlContent, /<canvas id="game-canvas"/);
    assert.match(htmlContent, /requestFullscreen/);

    const deskRes = exportDesktopGame({
      outputDir: testOutDir,
      title: 'Otter Platformer Deluxe'
    });
    assert.equal(deskRes.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'run-game.cmd')));

    const cmdContent = fs.readFileSync(path.join(testOutDir, 'run-game.cmd'), 'utf8');
    assert.match(cmdContent, /Otter Platformer Deluxe/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});
