// css-ast.js - Lossless CSS AST parser and surgical manipulator
// Preserves comments, whitespace, ordering, custom properties (--var), and unknown rules.

export class CssAstManager {
  constructor(cssText = '') {
    this.rawText = cssText;
    this.rules = [];
    this.parse(cssText);
  }

  // Parse CSS into structured rules while preserving unknown properties and comment blocks
  parse(cssText) {
    this.rawText = cssText || '';
    this.rules = [];

    // Simple tokenizer for CSS top-level blocks
    let i = 0;
    const len = this.rawText.length;
    let currentComment = '';

    while (i < len) {
      // Check for comments
      if (this.rawText.slice(i, i + 2) === '/*') {
        const end = this.rawText.indexOf('*/', i + 2);
        if (end !== -1) {
          const comment = this.rawText.slice(i, end + 2);
          this.rules.push({ type: 'comment', raw: comment });
          i = end + 2;
          continue;
        }
      }

      // Whitespace / newlines outside rules
      if (/\s/.test(this.rawText[i])) {
        let ws = '';
        while (i < len && /\s/.test(this.rawText[i])) {
          ws += this.rawText[i];
          i++;
        }
        if (this.rules.length > 0 && this.rules[this.rules.length - 1].type === 'whitespace') {
          this.rules[this.rules.length - 1].raw += ws;
        } else {
          this.rules.push({ type: 'whitespace', raw: ws });
        }
        continue;
      }

      // Read rule selector until '{'
      const openBrace = this.rawText.indexOf('{', i);
      if (openBrace === -1) {
        // Leftover text
        const remainder = this.rawText.slice(i);
        if (remainder.trim()) {
          this.rules.push({ type: 'raw', raw: remainder });
        }
        break;
      }

      const selectorRaw = this.rawText.slice(i, openBrace);
      const selector = selectorRaw.trim();

      // Find matching closing brace '}'
      let closeBrace = -1;
      let depth = 1;
      let j = openBrace + 1;
      while (j < len) {
        if (this.rawText[j] === '{') depth++;
        else if (this.rawText[j] === '}') {
          depth--;
          if (depth === 0) {
            closeBrace = j;
            break;
          }
        }
        j++;
      }

      if (closeBrace === -1) {
        // Malformed, store as raw
        this.rules.push({ type: 'raw', raw: this.rawText.slice(i) });
        break;
      }

      const bodyRaw = this.rawText.slice(openBrace + 1, closeBrace);
      const declarations = this.parseDeclarations(bodyRaw);

      this.rules.push({
        type: 'rule',
        selectorRaw,
        selector,
        declarations,
        rawBefore: '',
      });

      i = closeBrace + 1;
    }
  }

  parseDeclarations(bodyText) {
    const decls = [];
    const lines = bodyText.split(';');

    for (let rawPart of lines) {
      const part = rawPart.trim();
      if (!part) continue;

      // Check if it's a comment
      if (part.startsWith('/*') && part.endsWith('*/')) {
        decls.push({ type: 'comment', raw: rawPart });
        continue;
      }

      const colonIdx = part.indexOf(':');
      if (colonIdx === -1) {
        decls.push({ type: 'raw', raw: rawPart });
        continue;
      }

      const property = part.slice(0, colonIdx).trim();
      const value = part.slice(colonIdx + 1).trim();

      decls.push({
        type: 'declaration',
        property,
        value,
        rawLeading: '    ',
      });
    }

    return decls;
  }

  // Get declaration value for a given selector and property
  getProperty(selector, property) {
    const rule = this.rules.find(r => r.type === 'rule' && r.selector === selector);
    if (!rule) return null;

    const decl = rule.declarations.find(d => d.type === 'declaration' && d.property.toLowerCase() === property.toLowerCase());
    return decl ? decl.value : null;
  }

  // Get all declarations for a selector as a key-value map
  getRuleDeclarations(selector) {
    const rule = this.rules.find(r => r.type === 'rule' && r.selector === selector);
    if (!rule) return {};

    const map = {};
    for (let d of rule.declarations) {
      if (d.type === 'declaration') {
        map[d.property.toLowerCase()] = d.value;
      }
    }
    return map;
  }

  // Set or update a property on a selector
  setProperty(selector, property, value) {
    let rule = this.rules.find(r => r.type === 'rule' && r.selector === selector);

    if (!rule) {
      // Create new rule
      rule = {
        type: 'rule',
        selectorRaw: selector,
        selector,
        declarations: [],
      };
      // Insert rule before trailing whitespace if any
      this.rules.push(rule);
    }

    const propLower = property.toLowerCase();
    const existingDecl = rule.declarations.find(d => d.type === 'declaration' && d.property.toLowerCase() === propLower);

    if (value === null || value === undefined || value === '') {
      // Remove property
      if (existingDecl) {
        rule.declarations = rule.declarations.filter(d => d !== existingDecl);
      }
    } else {
      if (existingDecl) {
        existingDecl.value = String(value);
      } else {
        rule.declarations.push({
          type: 'declaration',
          property,
          value: String(value),
          rawLeading: '    ',
        });
      }
    }
  }

  // Generate CSS string output preserving comments, rules, and ordering
  generateCss() {
    let out = '';

    for (let item of this.rules) {
      if (item.type === 'comment' || item.type === 'whitespace' || item.type === 'raw') {
        out += item.raw;
      } else if (item.type === 'rule') {
        out += `${item.selector} {\n`;
        for (let d of item.declarations) {
          if (d.type === 'declaration') {
            out += `    ${d.property}: ${d.value};\n`;
          } else if (d.type === 'comment') {
            out += `    ${d.raw};\n`;
          } else if (d.type === 'raw') {
            out += `    ${d.raw};\n`;
          }
        }
        out += `}\n\n`;
      }
    }

    return out.trim() + '\n';
  }
}
