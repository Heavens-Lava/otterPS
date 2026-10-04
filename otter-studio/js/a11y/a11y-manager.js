/**
 * Otter Studio - Accessibility Manager
 * WCAG 2.1 AA / AAA Compliance, Focus Trapping, Live Announcer, Canvas Keyboard Controls & Audit Engine
 */

export class OtterAccessibilityManager {
  constructor(options = {}) {
    this.root = options.root || (typeof document !== 'undefined' ? document : null);
    this.announcerElement = null;
    this.announcerTimeout = null;
    this.currentZoom = 1.0;
    this.previousFocusElement = null;
    this.activeFocusTrap = null;
    this.highContrastEnabled = false;
    this.reducedMotionEnabled = false;

    if (this.root && typeof document !== 'undefined') {
      this.ensureAnnouncer();
      this.detectMediaPreferences();
    }
  }

  /**
   * Ensure screen-reader live region exists in the DOM.
   */
  ensureAnnouncer() {
    if (!this.root || typeof document === 'undefined') return;
    let announcer = this.root.getElementById('a11yAnnouncer');
    if (!announcer) {
      announcer = document.createElement('div');
      announcer.id = 'a11yAnnouncer';
      announcer.className = 'sr-only';
      announcer.setAttribute('aria-live', 'polite');
      announcer.setAttribute('aria-atomic', 'true');
      document.body.appendChild(announcer);
    }
    this.announcerElement = announcer;
  }

  /**
   * Detect OS media preferences for reduced motion and high contrast.
   */
  detectMediaPreferences() {
    if (typeof window === 'undefined' || !window.matchMedia) return;
    try {
      const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
      if (motionQuery.matches) {
        this.setReducedMotion(true);
      }
      motionQuery.addEventListener?.('change', (e) => this.setReducedMotion(e.matches));

      const contrastQuery = window.matchMedia('(forced-colors: active)');
      if (contrastQuery.matches) {
        this.setHighContrast(true);
      }
      contrastQuery.addEventListener?.('change', (e) => this.setHighContrast(e.matches));
    } catch {
      // Graceful fallback for headless or restricted test runners
    }
  }

  /**
   * Announce an alert or status message to screen readers.
   * @param {string} message
   * @param {'polite' | 'assertive'} priority
   */
  announce(message, priority = 'polite') {
    if (!this.announcerElement) this.ensureAnnouncer();
    if (!this.announcerElement) return;

    this.announcerElement.setAttribute('aria-live', priority);
    // Clear first to trigger change detection in AT screen readers
    this.announcerElement.textContent = '';
    clearTimeout(this.announcerTimeout);

    this.announcerTimeout = setTimeout(() => {
      this.announcerElement.textContent = message;
    }, 50);
  }

  /**
   * Trap keyboard focus within a modal or dialog.
   * @param {HTMLElement} container
   * @returns {() => void} untrap cleanup function
   */
  trapFocus(container) {
    if (!container) return () => {};
    if (typeof document !== 'undefined') {
      this.previousFocusElement = document.activeElement;
    }

    const focusableSelectors = [
      'a[href]',
      'button:not([disabled])',
      'input:not([disabled])',
      'select:not([disabled])',
      'textarea:not([disabled])',
      '[tabindex]:not([tabindex="-1"])',
      '[contenteditable="true"]'
    ].join(',');

    const handleKeyDown = (e) => {
      if (e.key !== 'Tab') return;

      const focusables = Array.from(container.querySelectorAll(focusableSelectors))
        .filter((el) => el.offsetParent !== null || el.getAttribute('aria-hidden') !== 'true');

      if (focusables.length === 0) {
        e.preventDefault();
        return;
      }

      const firstEl = focusables[0];
      const lastEl = focusables[focusables.length - 1];

      if (e.shiftKey) {
        if (document.activeElement === firstEl || !container.contains(document.activeElement)) {
          e.preventDefault();
          lastEl.focus();
        }
      } else {
        if (document.activeElement === lastEl || !container.contains(document.activeElement)) {
          e.preventDefault();
          firstEl.focus();
        }
      }
    };

    container.addEventListener('keydown', handleKeyDown);

    // Initial focus on first focusable element
    const initialFocusables = container.querySelectorAll(focusableSelectors);
    if (initialFocusables.length > 0) {
      initialFocusables[0].focus();
    }

    const untrap = () => {
      container.removeEventListener('keydown', handleKeyDown);
      if (this.previousFocusElement && typeof this.previousFocusElement.focus === 'function') {
        this.previousFocusElement.focus();
        this.previousFocusElement = null;
      }
    };

    this.activeFocusTrap = untrap;
    return untrap;
  }

  /**
   * Set theme with support for High Contrast modes.
   * @param {'theme-dark' | 'theme-light' | 'theme-high-contrast-dark' | 'theme-high-contrast-light'} themeClass
   */
  setTheme(themeClass) {
    if (typeof document === 'undefined') return;
    const body = document.body;
    body.classList.remove('theme-dark', 'theme-light', 'theme-high-contrast-dark', 'theme-high-contrast-light');
    body.classList.add(themeClass);
    this.highContrastEnabled = themeClass.includes('high-contrast');
    this.announce(`Theme changed to ${themeClass.replace('theme-', '')}`);
  }

  /**
   * Toggle High Contrast mode.
   * @param {boolean} [enable]
   */
  setHighContrast(enable) {
    if (typeof document === 'undefined') return;
    const body = document.body;
    const isDark = body.classList.contains('theme-dark') || !body.classList.contains('theme-light');
    const target = enable ?? !this.highContrastEnabled;

    if (target) {
      this.setTheme(isDark ? 'theme-high-contrast-dark' : 'theme-high-contrast-light');
    } else {
      this.setTheme(isDark ? 'theme-dark' : 'theme-light');
    }
  }

  /**
   * Set Reduced Motion mode.
   * @param {boolean} enable
   */
  setReducedMotion(enable) {
    if (typeof document === 'undefined') return;
    this.reducedMotionEnabled = enable;
    if (enable) {
      document.body.classList.add('reduced-motion');
    } else {
      document.body.classList.remove('reduced-motion');
    }
  }

  /**
   * Zoom controls (font and display scaling).
   */
  setZoom(scale) {
    this.currentZoom = Math.max(0.75, Math.min(2.0, Number(scale.toFixed(2))));
    if (typeof document !== 'undefined') {
      document.documentElement.style.setProperty('--studio-zoom', `${this.currentZoom}`);
      document.documentElement.style.fontSize = `${14 * this.currentZoom}px`;
    }
    this.announce(`Zoom level ${Math.round(this.currentZoom * 100)} percent`);
    return this.currentZoom;
  }

  zoomIn() {
    return this.setZoom(this.currentZoom + 0.1);
  }

  zoomOut() {
    return this.setZoom(this.currentZoom - 0.1);
  }

  resetZoom() {
    return this.setZoom(1.0);
  }

  /**
   * Color-independent status formatting.
   * Formats status messages with mandatory text prefixes and distinct icons so color is never the sole indicator.
   */
  formatStatus(level, message) {
    const config = {
      error: { icon: '✕', label: 'Error', role: 'alert', className: 'a11y-status-error' },
      warning: { icon: '⚠', label: 'Warning', role: 'status', className: 'a11y-status-warning' },
      success: { icon: '✓', label: 'Success', role: 'status', className: 'a11y-status-success' },
      info: { icon: 'ℹ', label: 'Info', role: 'status', className: 'a11y-status-info' }
    };

    const c = config[level] || config.info;
    const fullText = `[${c.label}] ${message}`;

    return {
      level,
      icon: c.icon,
      label: c.label,
      role: c.role,
      className: c.className,
      message,
      fullText,
      html: `<span class="a11y-status ${c.className}" role="${c.role}" aria-label="${fullText}"><span aria-hidden="true">${c.icon}</span> <span>${message}</span></span>`
    };
  }

  /**
   * Enable keyboard navigation and manipulation for the visual designer canvas.
   * Allows arrow-key movement, resize, tab cycling, and deletion.
   */
  setupCanvasKeyboard(container, { getSelected, getElements, selectElement, updateElement, deleteElement }) {
    if (!container) return () => {};

    const handleKeyDown = (e) => {
      const selected = getSelected?.();
      if (!selected) return;

      const step = e.altKey ? 10 : 1;

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          if (e.shiftKey) {
            updateElement?.(selected.id, { width: Math.max(10, (selected.width || 100) - step) });
          } else {
            updateElement?.(selected.id, { x: (selected.x || 0) - step });
          }
          break;

        case 'ArrowRight':
          e.preventDefault();
          if (e.shiftKey) {
            updateElement?.(selected.id, { width: (selected.width || 100) + step });
          } else {
            updateElement?.(selected.id, { x: (selected.x || 0) + step });
          }
          break;

        case 'ArrowUp':
          e.preventDefault();
          if (e.shiftKey) {
            updateElement?.(selected.id, { height: Math.max(10, (selected.height || 40) - step) });
          } else {
            updateElement?.(selected.id, { y: (selected.y || 0) - step });
          }
          break;

        case 'ArrowDown':
          e.preventDefault();
          if (e.shiftKey) {
            updateElement?.(selected.id, { height: (selected.height || 40) + step });
          } else {
            updateElement?.(selected.id, { y: (selected.y || 0) + step });
          }
          break;

        case 'Delete':
        case 'Backspace':
          if (e.target === container || e.target.classList?.contains('designer-element')) {
            e.preventDefault();
            deleteElement?.(selected.id);
            this.announce(`Deleted ${selected.name || 'element'}`);
          }
          break;

        case 'Tab': {
          const elements = getElements?.() || [];
          if (elements.length <= 1) return;
          e.preventDefault();
          const currentIndex = elements.findIndex((el) => el.id === selected.id);
          const nextIndex = e.shiftKey
            ? (currentIndex - 1 + elements.length) % elements.length
            : (currentIndex + 1) % elements.length;
          const next = elements[nextIndex];
          selectElement?.(next.id);
          this.announce(`Selected ${next.name || next.type || 'element'}`);
          break;
        }
      }
    };

    container.addEventListener('keydown', handleKeyDown);
    return () => container.removeEventListener('keydown', handleKeyDown);
  }

  /**
   * Relative luminance calculation per WCAG 2.1 guidelines.
   * @param {string} hex color in format "#RRGGBB"
   */
  getLuminance(hex) {
    const cleanHex = hex.replace('#', '');
    const r = parseInt(cleanHex.substring(0, 2), 16) / 255;
    const g = parseInt(cleanHex.substring(2, 4), 16) / 255;
    const b = parseInt(cleanHex.substring(4, 6), 16) / 255;

    const sRGB = [r, g, b].map((val) => {
      return val <= 0.03928 ? val / 12.92 : Math.pow((val + 0.055) / 1.055, 2.4);
    });

    return 0.2126 * sRGB[0] + 0.7152 * sRGB[1] + 0.0722 * sRGB[2];
  }

  /**
   * Calculate contrast ratio between two hex colors.
   * Returns a value between 1.0 and 21.0.
   */
  getContrastRatio(fgHex, bgHex) {
    const l1 = this.getLuminance(fgHex);
    const l2 = this.getLuminance(bgHex);
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return Number(((lighter + 0.05) / (darker + 0.05)).toFixed(2));
  }

  /**
   * Execute an automated WCAG 2.1 AA/AAA accessibility audit on a DOM subtree.
   * @param {HTMLElement} [rootNode]
   */
  runAccessibilityAudit(rootNode) {
    const root = rootNode || (typeof document !== 'undefined' ? document.body : null);
    const violations = [];
    let checksRun = 0;

    if (!root) {
      return { passed: true, checksRun: 0, violations: [] };
    }

    // 1. Check Images for alt text
    const images = root.querySelectorAll('img');
    images.forEach((img) => {
      checksRun++;
      if (!img.hasAttribute('alt')) {
        violations.push({
          id: 'image-alt',
          element: img.tagName.toLowerCase(),
          message: `Image missing alt attribute: ${img.src || img.className}`,
          severity: 'error'
        });
      }
    });

    // 2. Check Interactive Elements for Accessible Names
    const buttons = root.querySelectorAll('button, [role="button"]');
    buttons.forEach((btn) => {
      checksRun++;
      const text = btn.textContent?.trim();
      const ariaLabel = btn.getAttribute('aria-label');
      const ariaLabelledby = btn.getAttribute('aria-labelledby');
      const title = btn.getAttribute('title');

      if (!text && !ariaLabel && !ariaLabelledby && !title) {
        violations.push({
          id: 'button-name',
          element: btn.id || btn.className,
          message: 'Interactive button has no text content, aria-label, aria-labelledby, or title',
          severity: 'error'
        });
      }
    });

    // 3. Check Form Inputs for Labels
    const inputs = root.querySelectorAll('input:not([type="hidden"]), select, textarea');
    inputs.forEach((input) => {
      checksRun++;
      const id = input.id;
      const hasLabel = id && root.querySelector(`label[for="${id}"]`);
      const ariaLabel = input.getAttribute('aria-label');
      const ariaLabelledby = input.getAttribute('aria-labelledby');
      const title = input.getAttribute('title');
      const placeholder = input.getAttribute('placeholder');

      if (!hasLabel && !ariaLabel && !ariaLabelledby && !title && !placeholder) {
        violations.push({
          id: 'input-label',
          element: input.id || input.name || input.type,
          message: 'Form control lacks an associated <label>, aria-label, or title',
          severity: 'error'
        });
      }
    });

    // 4. Check Frame and Dialog ARIA attributes
    const dialogs = root.querySelectorAll('[role="dialog"]');
    dialogs.forEach((dialog) => {
      checksRun++;
      if (!dialog.getAttribute('aria-modal')) {
        violations.push({
          id: 'dialog-modal',
          element: dialog.id || 'dialog',
          message: 'Dialog role should specify aria-modal="true"',
          severity: 'warning'
        });
      }
      if (!dialog.getAttribute('aria-labelledby') && !dialog.getAttribute('aria-label')) {
        violations.push({
          id: 'dialog-label',
          element: dialog.id || 'dialog',
          message: 'Dialog missing aria-labelledby or aria-label',
          severity: 'warning'
        });
      }
    });

    // 5. Check Tablists have tabs and controls
    const tablists = root.querySelectorAll('[role="tablist"]');
    tablists.forEach((tablist) => {
      checksRun++;
      const tabs = tablist.querySelectorAll('[role="tab"]');
      if (tabs.length === 0) {
        violations.push({
          id: 'tablist-empty',
          element: tablist.id || 'tablist',
          message: 'Element with role="tablist" contains no elements with role="tab"',
          severity: 'error'
        });
      }
    });

    return {
      passed: violations.filter((v) => v.severity === 'error').length === 0,
      checksRun,
      violations
    };
  }
}

export const a11yManager = new OtterAccessibilityManager();
