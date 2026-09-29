    // otter-ui.js - Otter's UI runtime for the web and desktop (Electron) targets.
    //
    // Inlined into every compiled page by Otter.Web.psm1. Top-level UI
    // declarations are rendered to static HTML at compile time; everything
    // here serves UI that exists while the program runs:
    //
    //   - `card is a card with ...` inside a function, handler or loop creates
    //     a real element (otterCreateUi). Elements are ordinary Otter values:
    //     a function can build one and return it, which is how Otter programs
    //     make reusable components.
    //   - `put`, `remove ... from`, `clear`, `show`, `hide`, `focus` and
    //     `when x is <event>` work on those elements at run time.
    //   - property reads and writes go through one mapping (otterSetUi /
    //     otterGetUi) for both static and runtime elements, so `padding of x
    //     is 12` means the same thing whenever it runs.
    //   - `shortcut "Ctrl+K"` makes a key combination activate an element.
    //
    // Nothing in this file knows about any particular program.

    let otterUiCounter = 0;

    const OTTER_UI_KINDS = {
      'window': 'window', 'page': 'page', 'card': 'card', 'panel': 'panel',
      'button': 'button', 'text box': 'text box', 'text': 'text', 'image': 'image',
      'link': 'link', 'checkbox': 'checkbox', 'check box': 'checkbox',
      'dropdown': 'dropdown', 'drop down': 'dropdown', 'select': 'dropdown',
      'slider': 'slider', 'range': 'slider', 'text area': 'text area', 'textarea': 'text area',
      'badge': 'badge', 'tag': 'badge', 'canvas': 'canvas', 'table': 'table', 'scroll': 'scroll',
      'progress': 'progress', 'progress bar': 'progress', 'toggle': 'toggle', 'switch': 'toggle',
      'radio': 'radio', 'radio button': 'radio', 'dialog': 'dialog', 'modal': 'dialog',
      'row': 'row', 'column': 'column', 'list': 'list', 'icon': 'icon'
    };

    // Class name -> Otter kind, for elements the compiler rendered statically.
    const OTTER_UI_CLASS_KINDS = [
      ['otter-page', 'page'], ['otter-window', 'window'], ['otter-card', 'card'],
      ['otter-row', 'row'], ['otter-column', 'column'], ['otter-scroll', 'scroll'],
      ['otter-button', 'button'], ['otter-text-box', 'text box'], ['otter-text-area', 'text area'],
      ['otter-text', 'text'], ['otter-image', 'image'], ['otter-link', 'link'],
      ['otter-checkbox', 'checkbox'], ['otter-toggle', 'toggle'], ['otter-radio', 'radio'],
      ['otter-select', 'dropdown'], ['otter-slider', 'slider'], ['otter-badge', 'badge'],
      ['otter-progress', 'progress'], ['otter-canvas', 'canvas'], ['otter-icon', 'icon']
    ];

    function otterIsElement(value) {
      return !!value && typeof value === 'object' && value.nodeType === 1;
    }

    // An element Otter made: rendered by the compiler (an otter-* class) or
    // built while the program runs. Anything else in the document - an
    // icon sprite's <symbol id="settings">, say - is not UI to Otter, even
    // though the browser exposes elements with ids as window.<id>.
    function otterIsUiElement(value) {
      if (!otterIsElement(value)) return false;
      if (value.__otterKind) return true;
      const cls = value.classList;
      if (!cls) return false;
      for (const c of cls) { if (c.startsWith('otter-')) return true; }
      return false;
    }
    window.otterIsUiElement = otterIsUiElement;

    // An Otter name refers to a UI element either by holding one (built at
    // run time) or by being the id of one the compiler rendered.
    function otterUiRef(value, name) {
      if (otterIsUiElement(value)) return value;
      if (name) {
        const el = document.getElementById(name);
        if (otterIsUiElement(el)) return el;
      }
      return value;
    }

    function otterUiKind(el) {
      if (!otterIsElement(el)) return null;
      if (el.__otterKind) return el.__otterKind;
      const cls = el.classList;
      for (const [c, kind] of OTTER_UI_CLASS_KINDS) { if (cls.contains(c)) return kind; }
      for (const c of cls) { if (c.startsWith('otter-') && c !== 'otter-resource') return c.slice(6).replace(/-/g, ' '); }
      return 'element';
    }

    function otterDescribe(value) {
      if (value === null || value === undefined) return 'gone';
      if (otterIsElement(value)) return 'a ' + otterUiKind(value);
      if (typeof value === 'string') return 'some text';
      if (typeof value === 'number') return 'a number';
      if (typeof value === 'boolean') return 'true or false';
      if (Array.isArray(value)) return 'a list';
      if (typeof value === 'object' && value.__otterThing) return 'a ' + (value.typeName || 'thing');
      if (typeof value === 'object' && value.__otterDate) return 'a date';
      return 'something else';
    }

    function otterRequireUi(value, what) {
      if (!otterIsUiElement(value)) {
        throw new Error('I can only ' + what + ' a UI element, but this is ' + otterDescribe(value) + '.');
      }
      return value;
    }

    // A checkbox, toggle or radio is an <input> inside a <label>. The label is
    // what gets placed, hidden and styled; the input holds the state.
    function otterUiOuter(el) {
      if (el && el.tagName === 'INPUT' && el.parentElement && el.parentElement.matches &&
          el.parentElement.matches('.otter-checkbox-label, .otter-toggle-label, .otter-radio-label')) {
        return el.parentElement;
      }
      return el;
    }
    function otterUiInput(el) {
      if (el && el.__otterInput) return el.__otterInput;
      if (el && el.matches && el.matches('.otter-checkbox-label, .otter-toggle-label, .otter-radio-label')) {
        return el.querySelector('input') || el;
      }
      return el;
    }
    // Where children go: a page or window keeps them in its content area.
    function otterUiContent(el) {
      const kind = otterUiKind(el);
      if (kind === 'page') return el.querySelector(':scope > .otter-page-content') || el;
      if (kind === 'window') return el.querySelector(':scope > .otter-window-content') || el;
      return el;
    }

    function otterCss(value) {
      if (typeof value === 'number') return value + 'px';
      if (value === 'full') return '100%';
      return value === null || value === undefined ? '' : String(value);
    }
    function otterTruthy(value) {
      return value === true || value === 'true' || value === 'yes';
    }

    // Row and column placement (D54): `align` names a physical side, and its
    // word decides which axis it applies to; `spread` spaces children out.
    function otterApplyFlexLayout(el, kind) {
      const p = el.__otterProps || {};
      const isRow = kind === 'row';
      const dir = p.align === undefined ? null : String(p.align);
      const spread = otterTruthy(p.spread);
      const mainWords = isRow ? { left: 'flex-start', center: 'center', right: 'flex-end' } : { top: 'flex-start', middle: 'center', bottom: 'flex-end' };
      const crossWords = isRow ? { top: 'flex-start', middle: 'center', bottom: 'flex-end' } : { left: 'flex-start', center: 'center', right: 'flex-end' };
      if (spread && dir && dir in mainWords) {
        throw new Error((isRow ? 'Horizontal' : 'Vertical') + " alignment 'align " + dir + "' conflicts with 'spread' on a " + kind + '.');
      }
      let justify = 'flex-start';
      if (spread) justify = 'space-between';
      else if (dir && dir in mainWords) justify = mainWords[dir];
      else if (p.justify !== undefined) justify = String(p.justify);
      let align = isRow ? 'center' : 'stretch';
      if (dir && dir in crossWords) align = crossWords[dir];
      else if (p.alignitems !== undefined) align = String(p.alignitems);
      else if (p.items !== undefined) align = String(p.items);
      el.style.justifyContent = justify;
      el.style.alignItems = align;
    }

    // The words `with` accepts on a UI element, applied one at a time. The
    // static renderer in Otter.Web.psm1 gives the same words the same CSS.
    function otterSetUi(target, prop, value) {
      const el = otterRequireUi(target, 'set a property on');
      const key = String(prop).toLowerCase();
      const kind = otterUiKind(el);
      const outer = otterUiOuter(el);
      const input = otterUiInput(el);
      const style = outer.style;
      if (!outer.__otterProps) outer.__otterProps = {};
      outer.__otterProps[key] = value;
      if (kind === 'icon') {
        if (key === 'name') { const use = outer.querySelector('use'); if (use) use.setAttribute('href', '#' + String(value)); return; }
        if (key === 'size') { style.width = otterCss(value); style.height = otterCss(value); return; }
        if (key === 'label') { outer.setAttribute('role', 'img'); outer.setAttribute('aria-label', String(value)); outer.removeAttribute('aria-hidden'); return; }
      }
      // `icon "name"` on a button or link: a symbol before the label. The
      // label moves into its own span so text changes leave the icon alone.
      if (key === 'icon' && (kind === 'button' || kind === 'link')) {
        let svg = outer.querySelector(':scope > .otter-icon');
        if (value === null || value === '') { if (svg) svg.remove(); outer.classList.remove('otter-has-icon'); return; }
        if (!svg) {
          const ns = 'http://www.w3.org/2000/svg';
          svg = document.createElementNS(ns, 'svg');
          svg.setAttribute('class', 'otter-icon');
          svg.setAttribute('aria-hidden', 'true');
          svg.appendChild(document.createElementNS(ns, 'use'));
          const words = outer.textContent;
          if (!outer.querySelector(':scope > .otter-button-text')) {
            outer.textContent = '';
            outer.appendChild(svg);
            if (words.trim()) { const span = document.createElement('span'); span.className = 'otter-button-text'; span.textContent = words; outer.appendChild(span); }
          } else {
            outer.insertBefore(svg, outer.firstChild);
          }
          outer.classList.add('otter-has-icon');
        }
        svg.querySelector('use').setAttribute('href', '#' + String(value));
        return;
      }
      switch (key) {
        case 'text': case 'value': {
          if (kind === 'progress' || kind === 'slider') { input.value = value; return; }
          if (kind === 'checkbox' || kind === 'toggle' || kind === 'radio') {
            if (key === 'value' || typeof value === 'boolean') { input.checked = otterTruthy(value); return; }
            const span = outer.querySelector('span:not(.otter-toggle-track):not(.otter-toggle-thumb)');
            if (span) { span.textContent = value; return; }
          }
          otterSetText(input, value);
          return;
        }
        case 'checked': input.checked = otterTruthy(value); return;
        case 'title': {
          if (kind === 'page' || kind === 'window') { document.title = value; return; }
          if (kind === 'card') {
            let heading = outer.querySelector(':scope > .otter-card-title');
            if (!heading) { heading = document.createElement('h3'); heading.className = 'otter-card-title'; outer.insertBefore(heading, outer.firstChild); }
            heading.textContent = value;
            return;
          }
          outer.title = value;
          return;
        }
        case 'tooltip': outer.title = value === null ? '' : String(value); if (!outer.textContent.trim()) outer.setAttribute('aria-label', String(value)); return;
        case 'label': input.setAttribute('aria-label', String(value)); return;
        case 'placeholder': input.placeholder = value === null ? '' : String(value); return;
        case 'source': case 'src': input.src = value; return;
        case 'alt': input.alt = value; return;
        case 'url': case 'href': {
          outer.href = value;
          if (/^https?:\/\//i.test(String(value))) { outer.target = '_blank'; outer.rel = 'noopener noreferrer'; }
          return;
        }
        case 'options': {
          const current = input.value;
          const list = Array.isArray(value) ? value : String(value).split(',').map(s => s.trim());
          input.replaceChildren(...list.map(o => { const opt = document.createElement('option'); opt.value = String(o); opt.textContent = String(o); return opt; }));
          if (list.map(String).includes(current)) input.value = current;
          return;
        }
        case 'min': case 'max': case 'rows': case 'step': input.setAttribute(key, value); return;
        case 'group': case 'name': if (input.tagName === 'INPUT') { input.name = value; return; } break;
        case 'style': case 'class': {
          // Named styles from the stylesheet. Otter's own otter-* classes stay.
          for (const c of Array.from(outer.classList)) { if (!c.startsWith('otter-')) outer.classList.remove(c); }
          for (const c of String(value === null ? '' : value).split(/\s+/)) { if (c) outer.classList.add(c); }
          return;
        }
        case 'hidden': outer.classList.toggle('otter-hidden', otterTruthy(value)); return;
        case 'visible': outer.classList.toggle('otter-hidden', !otterTruthy(value)); return;
        case 'enabled': {
          const on = otterTruthy(value);
          if ('disabled' in input) input.disabled = !on;
          outer.classList.toggle('otter-disabled', !on);
          if (on) outer.removeAttribute('aria-disabled'); else outer.setAttribute('aria-disabled', 'true');
          return;
        }
        case 'shortcut': {
          if (value === null || value === '') { delete outer.dataset.otterShortcut; return; }
          outer.dataset.otterShortcut = otterNormalizeShortcut(String(value));
          otterInstallShortcuts();
          return;
        }
        case 'draggable': if (otterTruthy(value)) outer.setAttribute('draggable', 'true'); else outer.removeAttribute('draggable'); return;
        case 'accepts drops': if (otterTruthy(value)) outer.setAttribute('data-otter-accepts-drops', 'true'); else outer.removeAttribute('data-otter-accepts-drops'); return;
        case 'width': style.width = value === 'full' ? '100%' : otterCss(value); if (value === 'full') style.maxWidth = '100%'; return;
        case 'height': style.height = otterCss(value); return;
        case 'maxwidth': style.maxWidth = otterCss(value); return;
        case 'minwidth': style.minWidth = otterCss(value); return;
        case 'maxheight': style.maxHeight = otterCss(value); return;
        case 'minheight': style.minHeight = otterCss(value); return;
        case 'background': style.background = value; return;
        case 'foreground': style.color = value; return;
        case 'round': if (otterTruthy(value)) style.borderRadius = '9999px'; return;
        case 'radius': style.borderRadius = value === 'round' ? '9999px' : otterCss(value); return;
        case 'border': style.border = value; return;
        case 'shadow': style.boxShadow = value; return;
        case 'padding': style.padding = otterCss(value); return;
        case 'margin': style.margin = otterCss(value); return;
        case 'size': case 'fontsize': style.fontSize = otterCss(value); return;
        case 'weight': case 'fontweight': style.fontWeight = value; return;
        case 'bold': style.fontWeight = otterTruthy(value) ? '700' : ''; return;
        case 'italic': style.fontStyle = otterTruthy(value) ? 'italic' : ''; return;
        case 'fontstyle': style.fontStyle = value; return;
        case 'family': case 'fontfamily': style.fontFamily = value; return;
        case 'lineheight': style.lineHeight = value; return;
        case 'letterspacing': style.letterSpacing = value; return;
        case 'whitespace': style.whiteSpace = value; return;
        case 'overflow': style.overflow = value; return;
        case 'opacity': style.opacity = value; return;
        case 'flex': style.flex = value; style.minWidth = '0'; return;
        case 'grow': style.flexGrow = value; return;
        case 'cursor': style.cursor = value; return;
        case 'position': style.position = value; return;
        case 'top': case 'left': case 'right': case 'bottom': style[key] = otterCss(value); return;
        case 'zindex': style.zIndex = value; return;
        case 'customstyle': style.cssText += ';' + value; return;
        case 'spacing': case 'gap': style.gap = otterCss(value); return;
        case 'wrap': style.flexWrap = otterTruthy(value) || value === 'wrap' ? 'wrap' : 'nowrap'; return;
        case 'align': case 'spread': case 'justify': case 'alignitems': case 'items':
          if (kind === 'row' || kind === 'column') { otterApplyFlexLayout(outer, kind); return; }
          if (key === 'align') { style.textAlign = value; return; }
          break;
        case 'variant': outer.classList.add('otter-button-' + value); return;
        default: break;
      }
      // Anything else is kept as data on the element (readable back, and
      // usable from the stylesheet as [data-<name>="..."]).
      if (/^[a-z][a-z0-9-]*$/.test(key)) outer.dataset[key.replace(/-([a-z])/g, (_m, c) => c.toUpperCase())] = value;
    }

    function otterGetUi(target, prop) {
      const el = otterRequireUi(target, 'read a property of');
      const key = String(prop).toLowerCase();
      const kind = otterUiKind(el);
      const outer = otterUiOuter(el);
      const input = otterUiInput(el);
      if (kind === 'icon' && key === 'name') { const use = outer.querySelector('use'); return use ? String(use.getAttribute('href') || '').replace(/^#/, '') : ''; }
      if (key === 'icon' && (kind === 'button' || kind === 'link')) { const use = outer.querySelector(':scope > .otter-icon use'); return use ? String(use.getAttribute('href') || '').replace(/^#/, '') : ''; }
      switch (key) {
        case 'text': case 'value':
          if (kind === 'progress' || kind === 'slider') return Number(input.value);
          if ((kind === 'checkbox' || kind === 'toggle' || kind === 'radio') && key === 'text' && !input.__otterLegacyText) {
            const span = outer.querySelector('span:not(.otter-toggle-track):not(.otter-toggle-thumb)');
            if (el === outer && span) return span.textContent;
          }
          return otterGetText(input);
        case 'checked': return !!input.checked;
        case 'title':
          if (kind === 'page' || kind === 'window') return document.title;
          if (kind === 'card') { const h = outer.querySelector(':scope > .otter-card-title'); return h ? h.textContent : ''; }
          return outer.title;
        case 'tooltip': return outer.title;
        case 'placeholder': return input.placeholder || '';
        case 'source': case 'src': return input.getAttribute('src') || '';
        case 'options': return input.options ? Array.from(input.options).map(o => o.value) : [];
        case 'style': case 'class': return Array.from(outer.classList).filter(c => !c.startsWith('otter-')).join(' ');
        case 'hidden': return outer.classList.contains('otter-hidden');
        case 'visible': return !outer.classList.contains('otter-hidden');
        case 'enabled': return !('disabled' in input ? input.disabled : outer.classList.contains('otter-disabled'));
        case 'focused': return document.activeElement === input;
        case 'shortcut': return outer.dataset.otterShortcut || '';
        case 'width': return outer.style.width;
        case 'height': return outer.style.height;
        case 'kind': return kind;
        default: break;
      }
      if (outer.__otterProps && key in outer.__otterProps) return outer.__otterProps[key];
      const dataKey = key.replace(/-([a-z])/g, (_m, c) => c.toUpperCase());
      if (outer.dataset && dataKey in outer.dataset) return outer.dataset[dataKey];
      const native = input[key];
      return native === undefined || typeof native === 'function' ? null : native;
    }

    // `name is a <kind> with ...` executed while the program runs. `props`
    // is [[word, value], ...] in source order.
    function otterCreateUi(kindWord, props, name) {
      const kind = OTTER_UI_KINDS[String(kindWord).toLowerCase()];
      if (!kind) throw new Error('Otter does not know how to make a "' + kindWord + '".');
      let outer;
      let input = null;
      const make = (tag, cls) => { const e = document.createElement(tag); if (cls) e.className = cls; return e; };
      switch (kind) {
        case 'page': {
          outer = make('main', 'otter-page');
          const content = make('div', 'otter-page-content');
          content.style.cssText = 'display: flex; flex-direction: column; gap: 12px; width: 100%; min-width: 0; flex: 1 1 0%; min-height: 0; height: 100%;';
          outer.appendChild(content);
          break;
        }
        case 'window': {
          outer = make('div', 'otter-window');
          const content = make('div', 'otter-window-content');
          content.style.cssText = 'display: flex; flex-direction: column; gap: 12px; min-width: 0;';
          outer.appendChild(content);
          break;
        }
        case 'card': outer = make('div', 'otter-card'); outer.style.gap = '12px'; break;
        case 'button': outer = make('button', 'otter-button'); outer.type = 'button'; outer.textContent = 'Button'; break;
        case 'text box': outer = make('input', 'otter-text-box'); outer.type = 'text'; break;
        case 'text area': outer = make('textarea', 'otter-text-area'); outer.rows = 3; break;
        case 'text': outer = make('div', 'otter-text'); break;
        case 'image': outer = make('img', 'otter-image'); outer.alt = name || ''; break;
        case 'link': outer = make('a', 'otter-link'); outer.href = '#'; break;
        case 'badge': outer = make('span', 'otter-badge'); break;
        case 'progress': outer = make('progress', 'otter-progress'); outer.max = 100; outer.value = 0; break;
        case 'slider': outer = make('input', 'otter-slider'); outer.type = 'range'; outer.min = 0; outer.max = 100; outer.value = 50; break;
        case 'dropdown': outer = make('select', 'otter-select'); break;
        case 'canvas': outer = make('canvas', 'otter-canvas'); outer.width = 400; outer.height = 300; break;
        case 'icon': {
          const ns = 'http://www.w3.org/2000/svg';
          outer = document.createElementNS(ns, 'svg');
          outer.setAttribute('class', 'otter-icon');
          outer.setAttribute('aria-hidden', 'true');
          outer.appendChild(document.createElementNS(ns, 'use'));
          break;
        }
        case 'checkbox': case 'radio': {
          outer = make('label', 'otter-' + kind + '-label');
          input = make('input', 'otter-' + kind);
          input.type = kind;
          if (kind === 'radio') input.name = 'default-group';
          outer.append(input, ' ', make('span'));
          break;
        }
        case 'toggle': {
          outer = make('label', 'otter-toggle-label');
          input = make('input', 'otter-toggle');
          input.type = 'checkbox';
          input.setAttribute('role', 'switch');
          const track = make('span', 'otter-toggle-track');
          track.appendChild(make('span', 'otter-toggle-thumb'));
          outer.append(input, track, make('span', 'otter-toggle-text'));
          break;
        }
        case 'row':
          outer = make('div', 'otter-row');
          outer.style.cssText = 'display: flex; flex-direction: row; gap: 8px; align-items: center; justify-content: flex-start; flex-wrap: nowrap;';
          break;
        case 'column':
          outer = make('div', 'otter-column');
          outer.style.cssText = 'display: flex; flex-direction: column; gap: 8px; align-items: stretch; justify-content: flex-start;';
          break;
        case 'scroll':
          outer = make('div', 'otter-scroll');
          outer.style.cssText = 'overflow-y: auto; overflow-x: hidden; display: flex; flex-direction: column;';
          break;
        default: outer = make('div', 'otter-resource otter-' + kind.replace(/\s+/g, '-')); break;
      }
      outer.__otterKind = kind;
      if (input) { outer.__otterInput = input; input.__otterKind = kind; }
      outer.id = 'otter-ui-' + (++otterUiCounter);
      if (name) outer.dataset.otterName = name;
      // A button declared with an icon and no text is an icon button.
      const words = (props || []).map(([word]) => String(word).toLowerCase());
      if (kind === 'button' && words.includes('icon') && !words.includes('text')) outer.textContent = '';
      for (const [word, value] of props || []) {
        if (String(word).toLowerCase() === 'text' && (kind === 'toggle')) {
          outer.querySelector('.otter-toggle-text').textContent = value;
          continue;
        }
        otterSetUi(outer, word, value);
      }
      return outer;
    }

    // put <item> in <container>
    function otterPutIn(item, container) {
      const child = otterUiOuter(otterRequireUi(item, 'put'));
      const parent = otterRequireUi(container, 'put things in');
      if (child.parentNode && child.isConnected) {
        throw new Error('A ' + otterUiKind(child) + ' can only be in one place at a time, and this one is already somewhere else.');
      }
      if (child === parent || child.contains(parent)) {
        throw new Error('I cannot put a ' + otterUiKind(child) + ' inside itself.');
      }
      otterUiContent(parent).appendChild(child);
    }

    // remove <item> from <container>
    function otterRemoveUi(item, container) {
      const child = otterUiOuter(otterRequireUi(item, 'remove'));
      const parent = otterUiContent(otterRequireUi(container, 'remove things from'));
      if (child.parentNode !== parent) {
        throw new Error('That ' + otterUiKind(child) + ' is not in this ' + otterUiKind(container) + ', so it cannot be removed from it.');
      }
      parent.removeChild(child);
    }

    // clear <container>: remove everything that was put in it.
    function otterClearUi(container) {
      const el = otterRequireUi(container, 'clear');
      const kind = otterUiKind(el);
      if (kind === 'dropdown') { el.replaceChildren(); return; }
      if (kind === 'text box' || kind === 'text area') { el.value = ''; return; }
      otterUiContent(el).replaceChildren();
    }

    function otterShowUi(target) {
      const el = otterUiOuter(otterRequireUi(target, 'show'));
      el.classList.remove('otter-hidden');
      if (el.style.display === 'none') el.style.display = '';
    }
    function otterHideUi(target) {
      otterUiOuter(otterRequireUi(target, 'hide')).classList.add('otter-hidden');
    }
    function otterFocusUi(target) {
      const input = otterUiInput(otterRequireUi(target, 'focus'));
      if (typeof input.focus === 'function') input.focus();
      if (typeof input.select === 'function' && (input.tagName === 'INPUT' || input.tagName === 'TEXTAREA')) input.select();
    }

    // when <element> is <event>, registered while the program runs. The same
    // event words as a top-level `when`: clicked, changed, submitted, the
    // D110 drag words, or any DOM event name.
    function otterOnUi(target, eventWord, handler) {
      const el = otterRequireUi(target, 'listen for an event on');
      const word = String(eventWord).toLowerCase();
      const outer = otterUiOuter(el);
      const input = otterUiInput(el);
      const run = (event) => Promise.resolve(handler(event)).catch((err) => otterReportError(err));
      if (word === 'clicked') { (input !== outer ? input : outer).addEventListener('click', run); return; }
      if (word === 'changed') { input.addEventListener('input', run); return; }
      if (word === 'submitted') {
        input.addEventListener('keydown', (event) => {
          if (event.key !== 'Enter' || event.isComposing) return;
          if (input.tagName === 'TEXTAREA' && !(event.ctrlKey || event.metaKey)) return;
          event.preventDefault();
          run(event);
        });
        return;
      }
      if (word === 'drag' || word === 'drop' || word === 'files dropped') {
        const domEvent = word === 'drag' ? 'dragstart' : 'drop';
        outer.addEventListener(domEvent, (event) => {
          if (word === 'drop' && typeof otterIsItemDrop === 'function' && !otterIsItemDrop(event)) return;
          if (word === 'files dropped' && typeof otterIsFileDrop === 'function' && !otterIsFileDrop(event)) return;
          if (typeof otterMakeDragCtx === 'function') window.otterDragCtx = otterMakeDragCtx(event, outer, word);
          run(event);
        });
        return;
      }
      if (word === 'hovered') { outer.addEventListener('mouseenter', run); return; }
      outer.addEventListener(word, run);
    }

    function otterReportError(err) {
      const message = String((err && err.message) || err);
      console.error(message);
      const out = document.getElementById('otter-live-output');
      if (out) { out.style.display = 'block'; out.textContent = message; }
    }

    // ---- Keyboard shortcuts ---------------------------------------------------
    // `shortcut "Ctrl+K"` on an element: the key combination activates it
    // (a text box is focused, anything else is clicked). Only visible,
    // enabled elements answer; the last one in the page wins, so a dialog
    // shown above the page takes Escape before the page does.

    function otterNormalizeShortcut(text) {
      const parts = text.split('+').map(p => p.trim()).filter(Boolean);
      const mods = [];
      let key = '';
      for (const part of parts) {
        const lower = part.toLowerCase();
        if (lower === 'ctrl' || lower === 'control' || lower === 'cmd' || lower === 'command') { if (!mods.includes('Ctrl')) mods.push('Ctrl'); }
        else if (lower === 'alt' || lower === 'option') mods.push('Alt');
        else if (lower === 'shift') mods.push('Shift');
        else key = lower === 'esc' ? 'escape' : (lower === 'del' ? 'delete' : lower);
      }
      const order = ['Ctrl', 'Alt', 'Shift'];
      mods.sort((a, b) => order.indexOf(a) - order.indexOf(b));
      return [...mods, key].join('+');
    }

    function otterShortcutFromEvent(event) {
      const mods = [];
      if (event.ctrlKey || event.metaKey) mods.push('Ctrl');
      if (event.altKey) mods.push('Alt');
      if (event.shiftKey) mods.push('Shift');
      let key = String(event.key || '').toLowerCase();
      if (key === ' ') key = 'space';
      if (key === 'esc') key = 'escape';
      return [...mods, key].join('+');
    }

    let otterShortcutsInstalled = false;
    function otterInstallShortcuts() {
      if (otterShortcutsInstalled) return;
      otterShortcutsInstalled = true;
      document.addEventListener('keydown', (event) => {
        if (event.defaultPrevented || event.isComposing) return;
        const combo = otterShortcutFromEvent(event);
        const t = event.target;
        const typing = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);
        const plainKey = !(event.ctrlKey || event.metaKey || event.altKey);
        if (typing && plainKey && combo !== 'escape' && combo !== 'enter') return;
        if (combo === 'enter' && t && (t.tagName === 'TEXTAREA' || t.tagName === 'BUTTON' || t.tagName === 'A')) return;
        const candidates = Array.from(document.querySelectorAll('[data-otter-shortcut]'))
          .filter(el => el.dataset.otterShortcut === combo && el.getClientRects().length > 0 && !el.classList.contains('otter-disabled') && !el.disabled);
        const el = candidates[candidates.length - 1];
        if (!el) return;
        event.preventDefault();
        const input = otterUiInput(el);
        const kind = otterUiKind(el);
        if (kind === 'text box' || kind === 'text area') otterFocusUi(el);
        else (input !== el ? input : el).click();
      });
    }

    document.addEventListener('DOMContentLoaded', () => {
      if (document.querySelector('[data-otter-shortcut]')) otterInstallShortcuts();
    });
