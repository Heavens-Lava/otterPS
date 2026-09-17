// otter-studio/js/navigation/signature-provider.js

export const SIGNATURE_TABLE = [
  {
    name: 'say',
    prefix: /^\s*say\s+/i,
    label: 'say <expression>',
    parameters: [
      { label: '<expression>', doc: 'Value or string to print to standard output.' }
    ],
    doc: 'Prints text or expressions to output.'
  },
  {
    name: 'ask',
    prefix: /^\s*ask\s+/i,
    label: 'ask <prompt> into <variable>',
    parameters: [
      { label: '<prompt>', doc: 'Prompt string displayed to the user.' },
      { label: '<variable>', doc: 'Variable to store the user response.' }
    ],
    doc: 'Prompts the user interactively and saves input.',
    splitParam: /\s+into\s+/i
  },
  {
    name: 'make',
    prefix: /^\s*make\s+/i,
    label: 'make <name> is <value>',
    parameters: [
      { label: '<name>', doc: 'Name of the variable to declare.' },
      { label: '<value>', doc: 'Initial value or expression.' }
    ],
    doc: 'Declares a variable in the current scope.',
    splitParam: /\s+is\s+/i
  },
  {
    name: 'count',
    prefix: /^\s*count\s+/i,
    label: 'count <var> from <start> to <end>',
    parameters: [
      { label: '<var>', doc: 'Loop counter variable.' },
      { label: '<start>', doc: 'Starting integer value.' },
      { label: '<end>', doc: 'Ending integer value.' }
    ],
    doc: 'Loops with an incrementing counter.',
    customActive: (line) => {
      if (/\s+to\s+/i.test(line)) return 2;
      if (/\s+from\s+/i.test(line)) return 1;
      return 0;
    }
  },
  {
    name: 'for each',
    prefix: /^\s*for\s+each\s+/i,
    label: 'for each <item> in <collection>',
    parameters: [
      { label: '<item>', doc: 'Item variable for the current element.' },
      { label: '<collection>', doc: 'List or collection to iterate over.' }
    ],
    doc: 'Iterates through each element in a collection.',
    splitParam: /\s+in\s+/i
  },
  {
    name: 'add',
    prefix: /^\s*add\s+/i,
    label: 'add <value> to <collection>',
    parameters: [
      { label: '<value>', doc: 'Element or number to add.' },
      { label: '<collection>', doc: 'List or numeric variable.' }
    ],
    doc: 'Appends to a list or increases a value.',
    splitParam: /\s+to\s+/i
  },
  {
    name: 'remove',
    prefix: /^\s*remove\s+/i,
    label: 'remove <value> from <collection>',
    parameters: [
      { label: '<value>', doc: 'Element to remove.' },
      { label: '<collection>', doc: 'List to remove element from.' }
    ],
    doc: 'Removes an element from a list.',
    splitParam: /\s+from\s+/i
  },
  {
    name: 'copy file',
    prefix: /^\s*copy\s+file\s+/i,
    label: 'copy file <source> to <destination>',
    parameters: [
      { label: '<source>', doc: 'Source file path on disk.' },
      { label: '<destination>', doc: 'Destination file path.' }
    ],
    doc: 'Copies a file to another location.',
    splitParam: /\s+to\s+/i
  },
  {
    name: 'put',
    prefix: /^\s*put\s+/i,
    label: 'put <widget> in <container>',
    parameters: [
      { label: '<widget>', doc: 'UI widget component.' },
      { label: '<container>', doc: 'Target container panel.' }
    ],
    doc: 'Places a UI widget inside a container.',
    splitParam: /\s+in\s+/i
  },
  {
    name: 'when',
    prefix: /^\s*when\s+/i,
    label: 'when <event> <target>',
    parameters: [
      { label: '<event>', doc: 'Event name (e.g. clicked, changed, closed).' },
      { label: '<target>', doc: 'UI element or window target.' }
    ],
    doc: 'Attaches an event handler block to a UI element.',
    customActive: (line) => {
      const parts = line.trim().split(/\s+/);
      return parts.length > 2 ? 1 : 0;
    }
  },
  {
    name: 'get files in',
    prefix: /^\s*get\s+files\s+in\s+/i,
    label: 'get files in <path> [and subfolders into <var>]',
    parameters: [
      { label: '<path>', doc: 'Directory path to scan.' },
      { label: '<var>', doc: 'Target variable to store the list of files.' }
    ],
    doc: 'Scans a directory for matching files.',
    splitParam: /\s+into\s+/i
  }
];

export function getSignatureHelp(lineUntilCursor, symbols = []) {
  if (!lineUntilCursor) return null;
  const trimmed = lineUntilCursor.trimStart();

  // 1. Check built-in statements
  for (const def of SIGNATURE_TABLE) {
    if (def.prefix.test(trimmed)) {
      let activeIndex = 0;
      if (typeof def.customActive === 'function') {
        activeIndex = def.customActive(trimmed);
      } else if (def.splitParam) {
        activeIndex = def.splitParam.test(trimmed) ? 1 : 0;
      }
      return {
        label: def.label,
        parameters: def.parameters,
        activeParameter: Math.min(activeIndex, def.parameters.length - 1),
        doc: def.doc
      };
    }
  }

  // 2. Check user-defined function calls (e.g. `greet with "name", ...` or `calc(a, b)`)
  const withMatch = trimmed.match(/^([A-Za-z0-9_]+)\s+with\s+(.*)$/i);
  if (withMatch) {
    const fnName = withMatch[1];
    const argsString = withMatch[2];
    const fnSymbol = symbols.find(s => s.name?.toLowerCase() === fnName.toLowerCase() && s.kind === 'function');
    const paramCount = argsString.split(',').length - 1;
    return {
      label: fnSymbol ? `function ${fnSymbol.name} with params...` : `${fnName} with params...`,
      parameters: [{ label: `param ${paramCount + 1}`, doc: `Argument for ${fnName}` }],
      activeParameter: 0,
      doc: fnSymbol ? `User function declared at line ${fnSymbol.line}.` : `Call to ${fnName}`
    };
  }

  return null;
}
