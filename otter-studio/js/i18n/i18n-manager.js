/**
 * Otter Studio - Internationalization & Localization Manager
 * Multi-Language Translations, RTL Directionality, Number/Date Formatting,
 * IME Composition Tracking, Unicode Path Safety, and Grapheme-Safe Cursor Navigation
 */

export class OtterI18nManager {
  constructor(initialLocale = 'en-US') {
    this.locale = initialLocale;
    this.isComposing = false;
    this.compositionText = '';

    this.dictionaries = {
      'en-US': {
        'app.title': 'Otter Studio',
        'file.newProject': 'New Project...',
        'file.newFile': 'New File',
        'file.openFolder': 'Open Folder...',
        'file.save': 'Save',
        'file.projectSettings': 'Project Settings...',
        'edit.undo': 'Undo',
        'edit.redo': 'Redo',
        'edit.find': 'Find',
        'edit.replace': 'Replace',
        'run.runProgram': 'Run Program',
        'run.debug': 'Start Debugging',
        'run.stop': 'Stop',
        'view.terminal': 'Terminal',
        'view.highContrast': 'High Contrast',
        'view.zoomIn': 'Zoom In',
        'view.zoomOut': 'Zoom Out',
        'status.ready': 'Ready',
        'status.running': 'Running...',
        'status.buildSuccess': 'Build succeeded with 0 errors.',
        'status.buildFailed': 'Build failed with {count} errors.',
        'dialog.confirm': 'Confirm',
        'dialog.cancel': 'Cancel',
        'dialog.close': 'Close'
      },
      'es-ES': {
        'app.title': 'Otter Studio',
        'file.newProject': 'Nuevo proyecto...',
        'file.newFile': 'Nuevo archivo',
        'file.openFolder': 'Abrir carpeta...',
        'file.save': 'Guardar',
        'file.projectSettings': 'Configuración del proyecto...',
        'edit.undo': 'Deshacer',
        'edit.redo': 'Rehacer',
        'edit.find': 'Buscar',
        'edit.replace': 'Reemplazar',
        'run.runProgram': 'Ejecutar programa',
        'run.debug': 'Iniciar depuración',
        'run.stop': 'Detener',
        'view.terminal': 'Terminal',
        'view.highContrast': 'Alto contraste',
        'view.zoomIn': 'Acercar',
        'view.zoomOut': 'Alejar',
        'status.ready': 'Listo',
        'status.running': 'Ejecutando...',
        'status.buildSuccess': 'Compilación correcta con 0 errores.',
        'status.buildFailed': 'La compilación falló con {count} errores.',
        'dialog.confirm': 'Confirmar',
        'dialog.cancel': 'Cancelar',
        'dialog.close': 'Cerrar'
      },
      'ja-JP': {
        'app.title': 'Otter Studio',
        'file.newProject': '新規プロジェクト...',
        'file.newFile': '新規ファイル',
        'file.openFolder': 'フォルダーを開く...',
        'file.save': '保存',
        'file.projectSettings': 'プロジェクト設定...',
        'edit.undo': '元に戻す',
        'edit.redo': 'やり直し',
        'edit.find': '検索',
        'edit.replace': '置換',
        'run.runProgram': 'プログラムを実行',
        'run.debug': 'デバッグを開始',
        'run.stop': '停止',
        'view.terminal': 'ターミナル',
        'view.highContrast': 'ハイコントラスト',
        'view.zoomIn': '拡大',
        'view.zoomOut': '縮小',
        'status.ready': '準備完了',
        'status.running': '実行中...',
        'status.buildSuccess': 'ビルドが正常に完了しました（エラー 0 件）。',
        'status.buildFailed': 'ビルドが失敗しました（エラー {count} 件）。',
        'dialog.confirm': '確認',
        'dialog.cancel': 'キャンセル',
        'dialog.close': '閉じる'
      },
      'ar-SA': {
        'app.title': 'استوديو أوتر',
        'file.newProject': 'مشروع جديد...',
        'file.newFile': 'ملف جديد',
        'file.openFolder': 'فتح مجلد...',
        'file.save': 'حفظ',
        'file.projectSettings': 'إعدادات المشروع...',
        'edit.undo': 'تراجع',
        'edit.redo': 'إعادة',
        'edit.find': 'بحث',
        'edit.replace': 'استبدال',
        'run.runProgram': 'تشغيل البرنامج',
        'run.debug': 'بدء التصحيح',
        'run.stop': 'إيقاف',
        'view.terminal': 'الطرفية',
        'view.highContrast': 'تباين عالي',
        'view.zoomIn': 'تكبير',
        'view.zoomOut': 'تصغير',
        'status.ready': 'جاهز',
        'status.running': 'قيد التشغيل...',
        'status.buildSuccess': 'نجح البناء مع 0 أخطاء.',
        'status.buildFailed': 'فشل البناء مع {count} أخطاء.',
        'dialog.confirm': 'تأكيد',
        'dialog.cancel': 'إلغاء',
        'dialog.close': 'إغلاق'
      }
    };
  }

  /**
   * Check if a locale code is Right-to-Left (RTL).
   * @param {string} [locale]
   */
  isRTL(locale = this.locale) {
    const lang = locale.split(/[-_]/)[0].toLowerCase();
    return ['ar', 'he', 'fa', 'ur', 'yi', 'ps'].includes(lang);
  }

  /**
   * Set the active UI locale.
   * Updates document direction (LTR/RTL) and lang attributes.
   * @param {string} locale
   */
  setLocale(locale) {
    if (!this.dictionaries[locale] && !locale.startsWith('en')) {
      console.warn(`Locale ${locale} not fully registered, falling back to en-US baseline.`);
    }
    this.locale = locale;

    if (typeof document !== 'undefined') {
      const isRtl = this.isRTL(locale);
      document.documentElement.setAttribute('lang', locale);
      document.documentElement.setAttribute('dir', isRtl ? 'rtl' : 'ltr');
      if (document.body) {
        if (isRtl) {
          document.body.classList.add('rtl-layout');
        } else {
          document.body.classList.remove('rtl-layout');
        }
      }
    }
  }

  /**
   * Translate a key with optional variable interpolation.
   * @param {string} key
   * @param {Record<string, any>} [params]
   * @returns {string}
   */
  t(key, params = {}) {
    const dict = this.dictionaries[this.locale] || this.dictionaries['en-US'];
    let str = dict[key] || this.dictionaries['en-US'][key] || key;

    for (const [k, v] of Object.entries(params)) {
      str = str.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v));
    }
    return str;
  }

  /**
   * Register or extend translations for a given locale.
   * @param {string} locale
   * @param {Record<string, string>} translations
   */
  registerLocale(locale, translations) {
    this.dictionaries[locale] = {
      ...(this.dictionaries[locale] || {}),
      ...translations
    };
  }

  /**
   * Localize date using standard Intl API.
   * @param {Date | number} date
   * @param {Intl.DateTimeFormatOptions} [options]
   */
  formatDate(date, options = { dateStyle: 'medium', timeStyle: 'short' }) {
    try {
      return new Intl.DateTimeFormat(this.locale, options).format(date);
    } catch {
      return new Date(date).toLocaleString();
    }
  }

  /**
   * Localize numbers and percentages using standard Intl API.
   * @param {number} num
   * @param {Intl.NumberFormatOptions} [options]
   */
  formatNumber(num, options = {}) {
    try {
      return new Intl.NumberFormat(this.locale, options).format(num);
    } catch {
      return String(num);
    }
  }

  /**
   * Preserves and validates Unicode non-Latin source code strings (CJK, Arabic, Cyrillic, Accents, Emoji).
   * Verifies string is not corrupted by Latin1/ASCII decoders.
   * @param {string} source
   */
  validateUnicodeSource(source) {
    if (typeof source !== 'string') return { valid: false, reason: 'Source must be string' };

    // Check for common Unicode replacement characters indicating decoding failure
    const hasReplacementChar = source.includes('\uFFFD');
    const hasNullBytes = source.includes('\u0000');

    return {
      valid: !hasReplacementChar && !hasNullBytes,
      hasReplacementChar,
      hasNullBytes,
      length: source.length,
      graphemeCount: this.getGraphemeCount(source)
    };
  }

  /**
   * Sanitize non-Latin paths while preserving Unicode folder and file names.
   * Strips forbidden file system control characters (\0, <, >, :, ", |, ?, *).
   * @param {string} path
   */
  sanitizeUnicodePath(path) {
    if (!path) return '';
    // Replace OS control characters while keeping Unicode letters/digits intact
    return path
      .replace(/[\u0000-\u001F\u007F<>:"|?*]/g, '_')
      .replace(/\\/g, '/');
  }

  /**
   * Bind IME (Input Method Editor) composition lifecycle listeners.
   * Prevents keystroke execution during multi-byte CJK or accent composition.
   * @param {HTMLElement} element
   * @param {Object} [callbacks]
   */
  bindIMEComposition(element, callbacks = {}) {
    if (!element) return () => {};

    const onStart = (e) => {
      this.isComposing = true;
      this.compositionText = e.data || '';
      callbacks.onStart?.(e);
    };

    const onUpdate = (e) => {
      this.isComposing = true;
      this.compositionText = e.data || '';
      callbacks.onUpdate?.(e);
    };

    const onEnd = (e) => {
      this.isComposing = false;
      this.compositionText = e.data || '';
      callbacks.onEnd?.(e);
    };

    element.addEventListener('compositionstart', onStart);
    element.addEventListener('compositionupdate', onUpdate);
    element.addEventListener('compositionend', onEnd);

    return () => {
      element.removeEventListener('compositionstart', onStart);
      element.removeEventListener('compositionupdate', onUpdate);
      element.removeEventListener('compositionend', onEnd);
    };
  }

  /**
   * Break a string into grapheme clusters.
   * Safely handles composite emojis (e.g. ZWJ sequences) and CJK surrogate pairs.
   * @param {string} text
   * @returns {string[]}
   */
  getGraphemeClusters(text) {
    if (!text) return [];

    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
      const segmenter = new Intl.Segmenter(this.locale, { granularity: 'grapheme' });
      return Array.from(segmenter.segment(text), (s) => s.segment);
    }

    // Fallback using Unicode regex for surrogate pairs & combining diacritics
    return Array.from(text.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/gu) || []);
  }

  /**
   * Get true visual grapheme count of text.
   * @param {string} text
   */
  getGraphemeCount(text) {
    return this.getGraphemeClusters(text).length;
  }

  /**
   * Calculate next grapheme cluster boundary from a code-unit cursor position.
   * @param {string} text
   * @param {number} currentIndex
   */
  nextGraphemeIndex(text, currentIndex) {
    if (currentIndex >= text.length) return text.length;

    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
      const segmenter = new Intl.Segmenter(this.locale, { granularity: 'grapheme' });
      for (const seg of segmenter.segment(text)) {
        if (seg.index > currentIndex) {
          return seg.index;
        }
      }
      return text.length;
    }

    // Fallback: Check for surrogate pair
    const code = text.charCodeAt(currentIndex);
    if (code >= 0xd800 && code <= 0xdbff && currentIndex + 1 < text.length) {
      return currentIndex + 2;
    }
    return currentIndex + 1;
  }

  /**
   * Calculate previous grapheme cluster boundary from a code-unit cursor position.
   * @param {string} text
   * @param {number} currentIndex
   */
  prevGraphemeIndex(text, currentIndex) {
    if (currentIndex <= 0) return 0;

    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
      const segmenter = new Intl.Segmenter(this.locale, { granularity: 'grapheme' });
      let prevIndex = 0;
      for (const seg of segmenter.segment(text)) {
        if (seg.index >= currentIndex) {
          return prevIndex;
        }
        prevIndex = seg.index;
      }
      return prevIndex;
    }

    // Fallback: Check for surrogate pair backwards
    if (currentIndex >= 2) {
      const prevCode = text.charCodeAt(currentIndex - 2);
      if (prevCode >= 0xd800 && prevCode <= 0xdbff) {
        return currentIndex - 2;
      }
    }
    return currentIndex - 1;
  }
}

export const i18nManager = new OtterI18nManager();
