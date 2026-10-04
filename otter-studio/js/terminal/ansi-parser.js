// ansi-parser.js - Production ANSI / VT100 Escape Sequence Parser & HTML Renderer
// Converts ANSI/VT terminal output (colors, styles, cursor control) to clean, sanitized HTML.

const STANDARD_FG = {
  30: '#1e1e1e', // Black
  31: '#f44336', // Red
  32: '#4caf50', // Green
  33: '#ffeb3b', // Yellow
  34: '#2196f3', // Blue
  35: '#9c27b0', // Magenta
  36: '#00bcd4', // Cyan
  37: '#e0e0e0', // White
  90: '#757575', // Bright Black / Gray
  91: '#ef5350', // Bright Red
  92: '#66bb6a', // Bright Green
  93: '#fff176', // Bright Yellow
  94: '#42a5f5', // Bright Blue
  95: '#ab47bc', // Bright Magenta
  96: '#26c6da', // Bright Cyan
  97: '#ffffff'  // Bright White
};

const STANDARD_BG = {
  40: '#000000',
  41: '#b71c1c',
  42: '#1b5e20',
  43: '#f57f17',
  44: '#0d47a1',
  45: '#4a148c',
  46: '#006064',
  47: '#eeeeee',
  100: '#424242',
  101: '#e53935',
  102: '#43a047',
  103: '#fdd835',
  104: '#1e88e5',
  105: '#8e24aa',
  106: '#00acc1',
  107: '#ffffff'
};

const ANSI_REGEX = /[\u001b\u009b][[\]()#;?]*(?:(?:(?:[a-zA-Z\d]*(?:;[-a-zA-Z\d\/#&.:=?%@~_]*)*)?\u0007)|(?:(?:\d{1,4}(?:;\d{0,4})*)?[\dA-PR-TZcf-ntqry=><~]))/g;

/**
 * Strips all ANSI and VT escape sequences from a string.
 * @param {string} text 
 * @returns {string} Plain text with escapes removed
 */
export function stripAnsi(text) {
  if (typeof text !== 'string') return '';
  return text.replace(ANSI_REGEX, '');
}

/**
 * Escapes HTML special characters to prevent XSS injection.
 * @param {string} text 
 * @returns {string} HTML-escaped string
 */
export function escapeHtml(text) {
  if (!text) return '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Resolves 256-color palette index to a hex color.
 * @param {number} index (0-255)
 * @returns {string} Hex color
 */
export function get256Color(index) {
  index = Math.max(0, Math.min(255, index | 0));
  // 0-15: Standard 16 colors
  if (index < 8) return STANDARD_FG[30 + index];
  if (index < 16) return STANDARD_FG[90 + (index - 8)];

  // 16-231: 6x6x6 color cube
  if (index <= 231) {
    const code = index - 16;
    const r = Math.floor(code / 36);
    const g = Math.floor((code % 36) / 6);
    const b = code % 6;
    const val = [0, 95, 135, 175, 215, 255];
    return `rgb(${val[r]}, ${val[g]}, ${val[b]})`;
  }

  // 232-255: Grayscale ramp
  const gray = 8 + (index - 232) * 10;
  return `rgb(${gray}, ${gray}, ${gray})`;
}

/**
 * Parses raw terminal text with ANSI codes into formatted HTML spans.
 * @param {string} rawText 
 * @returns {string} Sanitized HTML string
 */
export function ansiToHtml(rawText) {
  if (!rawText) return '';

  let fg = null;
  let bg = null;
  let bold = false;
  let dim = false;
  let italic = false;
  let underline = false;
  let strikethrough = false;
  let inverse = false;

  let result = '';
  let lastIndex = 0;

  // Pattern specifically matching SGR codes (\x1b[...m) and OSC title codes (\x1b]0;...\x07)
  const tokenRegex = /\x1b\[([0-9;]*)m|\x1b\]0;([^\x07\x1b]*)(?:\x07|\x1b\\)/g;
  let match;

  const flushText = (text) => {
    if (!text) return;
    const escaped = escapeHtml(text);
    const styles = [];

    const effectiveFg = inverse ? (bg || '#000000') : fg;
    const effectiveBg = inverse ? (fg || '#ffffff') : bg;

    if (effectiveFg) styles.push(`color: ${effectiveFg}`);
    if (effectiveBg) styles.push(`background-color: ${effectiveBg}`);
    if (bold) styles.push('font-weight: bold');
    if (dim) styles.push('opacity: 0.7');
    if (italic) styles.push('font-style: italic');
    if (underline && strikethrough) styles.push('text-decoration: underline line-through');
    else if (underline) styles.push('text-decoration: underline');
    else if (strikethrough) styles.push('text-decoration: line-through');

    if (styles.length > 0) {
      result += `<span style="${styles.join('; ')}">${escaped}</span>`;
    } else {
      result += escaped;
    }
  };

  while ((match = tokenRegex.exec(rawText)) !== null) {
    // Flush preceding plain text
    if (match.index > lastIndex) {
      flushText(rawText.slice(lastIndex, match.index));
    }
    lastIndex = tokenRegex.lastIndex;

    // Check if this is SGR code (\x1b[...m)
    if (match[1] !== undefined) {
      const codeStr = match[1];
      const codes = codeStr ? codeStr.split(';').map(n => parseInt(n, 10)) : [0];

      for (let i = 0; i < codes.length; i++) {
        const c = isNaN(codes[i]) ? 0 : codes[i];

        if (c === 0) {
          fg = null;
          bg = null;
          bold = false;
          dim = false;
          italic = false;
          underline = false;
          strikethrough = false;
          inverse = false;
        } else if (c === 1) {
          bold = true;
        } else if (c === 2) {
          dim = true;
        } else if (c === 3) {
          italic = true;
        } else if (c === 4) {
          underline = true;
        } else if (c === 7) {
          inverse = true;
        } else if (c === 9) {
          strikethrough = true;
        } else if (c === 22) {
          bold = false;
          dim = false;
        } else if (c === 23) {
          italic = false;
        } else if (c === 24) {
          underline = false;
        } else if (c === 27) {
          inverse = false;
        } else if (c === 29) {
          strikethrough = false;
        } else if (c >= 30 && c <= 37) {
          fg = STANDARD_FG[c];
        } else if (c === 39) {
          fg = null;
        } else if (c >= 40 && c <= 47) {
          bg = STANDARD_BG[c];
        } else if (c === 49) {
          bg = null;
        } else if (c >= 90 && c <= 97) {
          fg = STANDARD_FG[c];
        } else if (c >= 100 && c <= 107) {
          bg = STANDARD_BG[c];
        } else if (c === 38) {
          // Extended foreground color: 38;5;n or 38;2;r;g;b
          if (codes[i + 1] === 5 && codes[i + 2] !== undefined) {
            fg = get256Color(codes[i + 2]);
            i += 2;
          } else if (codes[i + 1] === 2 && codes[i + 4] !== undefined) {
            fg = `rgb(${codes[i + 2]}, ${codes[i + 3]}, ${codes[i + 4]})`;
            i += 4;
          }
        } else if (c === 48) {
          // Extended background color: 48;5;n or 48;2;r;g;b
          if (codes[i + 1] === 5 && codes[i + 2] !== undefined) {
            bg = get256Color(codes[i + 2]);
            i += 2;
          } else if (codes[i + 1] === 2 && codes[i + 4] !== undefined) {
            bg = `rgb(${codes[i + 2]}, ${codes[i + 3]}, ${codes[i + 4]})`;
            i += 4;
          }
        }
      }
    }
  }

  // Flush remaining trailing text
  if (lastIndex < rawText.length) {
    flushText(rawText.slice(lastIndex));
  }

  return result;
}
