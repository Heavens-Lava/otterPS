/**
 * Otter Studio - Crash Recovery & Autosave Manager
 * Automatic Dirty Buffer Journaling, Crash Detection, Unsaved Edit Recovery,
 * Corrupt Settings/Workspace Healing, and State Reset Engine
 */

export class OtterRecoveryManager {
  constructor(options = {}) {
    this.storage = options.storage || (typeof localStorage !== 'undefined' ? localStorage : new Map());
    this.journalKey = options.journalKey || 'otter_studio_recovery_journal';
    this.cleanExitKey = options.cleanExitKey || 'otter_studio_clean_exit';
    this.autosaveIntervalMs = options.autosaveIntervalMs || 3000;
    this.dirtyBuffers = new Map();
    this.autosaveTimer = null;
    this.onRecoveryAvailable = options.onRecoveryAvailable || null;
  }

  /**
   * Initialize recovery manager and detect if prior session crashed.
   * @returns {{ crashed: boolean, recoveredCount: number, recoveredFiles: string[] }}
   */
  init() {
    const rawClean = this.getItem(this.cleanExitKey);
    const rawJournal = this.getItem(this.journalKey);
    let journal = null;

    if (rawJournal) {
      try {
        journal = typeof rawJournal === 'string' ? JSON.parse(rawJournal) : rawJournal;
      } catch {
        // Journal itself corrupted; reset safely
        this.removeItem(this.journalKey);
      }
    }

    const previousCrashed = rawClean === 'false' && journal && journal.entries && Object.keys(journal.entries).length > 0;
    const recoveredFiles = previousCrashed ? Object.keys(journal.entries) : [];

    // Mark current session as running (not yet clean exit)
    this.setItem(this.cleanExitKey, 'false');

    if (previousCrashed && this.onRecoveryAvailable) {
      this.onRecoveryAvailable(journal);
    }

    return {
      crashed: Boolean(previousCrashed),
      recoveredCount: recoveredFiles.length,
      recoveredFiles,
      journal
    };
  }

  /**
   * Storage abstraction supporting both window.localStorage and Map for Node tests.
   */
  getItem(key) {
    if (this.storage instanceof Map) return this.storage.get(key) || null;
    try {
      return this.storage.getItem(key);
    } catch {
      return null;
    }
  }

  setItem(key, value) {
    if (this.storage instanceof Map) {
      this.storage.set(key, String(value));
      return;
    }
    try {
      this.storage.setItem(key, String(value));
    } catch {
      // Storage quota exceeded or blocked
    }
  }

  removeItem(key) {
    if (this.storage instanceof Map) {
      this.storage.delete(key);
      return;
    }
    try {
      this.storage.removeItem(key);
    } catch {}
  }

  /**
   * Record a document change into the dirty buffer journal.
   * @param {string} filePath
   * @param {string} content
   * @param {Object} [meta]
   */
  recordBufferChange(filePath, content, meta = {}) {
    if (!filePath) return;

    this.dirtyBuffers.set(filePath, {
      content,
      cursor: meta.cursor || 0,
      timestamp: Date.now(),
      revision: meta.revision || null
    });

    this.scheduleAutosave();
  }

  /**
   * Mark a file as cleanly saved to disk, removing it from dirty buffer journal.
   * @param {string} filePath
   */
  markFileSaved(filePath) {
    this.dirtyBuffers.delete(filePath);
    this.flushJournal();
  }

  /**
   * Schedule debounced journal flush.
   */
  scheduleAutosave() {
    clearTimeout(this.autosaveTimer);
    this.autosaveTimer = setTimeout(() => {
      this.flushJournal();
    }, 250);
  }

  /**
   * Immediately write all dirty buffers to local recovery journal.
   */
  flushJournal() {
    clearTimeout(this.autosaveTimer);
    if (this.dirtyBuffers.size === 0) {
      this.removeItem(this.journalKey);
      return;
    }

    const entries = {};
    for (const [filePath, data] of this.dirtyBuffers.entries()) {
      entries[filePath] = data;
    }

    const payload = {
      timestamp: Date.now(),
      entries
    };

    this.setItem(this.journalKey, JSON.stringify(payload));
  }

  /**
   * Restore all dirty edits from journal.
   * @returns {Record<string, { content: string, cursor: number, timestamp: number }>}
   */
  restoreJournal() {
    const raw = this.getItem(this.journalKey);
    if (!raw) return {};
    try {
      const journal = JSON.parse(raw);
      if (journal && journal.entries) {
        for (const [filePath, data] of Object.entries(journal.entries)) {
          this.dirtyBuffers.set(filePath, data);
        }
        return journal.entries;
      }
    } catch {}
    return {};
  }

  /**
   * Discard dirty journal after user decision or successful disk sync.
   */
  discardJournal() {
    this.dirtyBuffers.clear();
    this.removeItem(this.journalKey);
  }

  /**
   * Safely heal and recover a corrupted configuration or manifest file.
   * If parsing fails, preserves a backup of the corrupted content and returns a safe fallback.
   * @param {string} rawContent
   * @param {() => any} fallbackFactory
   */
  healCorruptJson(rawContent, fallbackFactory) {
    try {
      if (!rawContent || !rawContent.trim()) {
        return { ok: true, data: fallbackFactory(), healed: true, reason: 'Empty file initialized to defaults' };
      }
      const data = JSON.parse(rawContent.replace(/^\uFEFF/, ''));
      return { ok: true, data, healed: false };
    } catch (err) {
      const fallback = fallbackFactory();
      return {
        ok: true,
        data: fallback,
        healed: true,
        reason: `Corrupt JSON healed: ${err.message}`,
        corruptBackup: rawContent
      };
    }
  }

  /**
   * Complete safe shutdown. Marks clean exit so restart won't trigger false crash alerts.
   */
  recordCleanExit() {
    this.flushJournal();
    this.setItem(this.cleanExitKey, 'true');
  }

  /**
   * Reset all Studio state and caches (Recovery Mode).
   * Preserves workspace files on disk while resetting corrupted IDE settings.
   */
  resetStudioState() {
    const keysToRemove = [
      this.journalKey,
      this.cleanExitKey,
      'otter_studio_session',
      'otter-studio-theme',
      'otter_studio_recents',
      'otter_trusted_workspaces'
    ];

    for (const key of keysToRemove) {
      this.removeItem(key);
    }
    this.dirtyBuffers.clear();

    return { reset: true, clearedKeys: keysToRemove };
  }
}

export const recoveryManager = new OtterRecoveryManager();
