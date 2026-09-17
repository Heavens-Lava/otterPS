// otter-studio/js/language/otter-metadata.js
// Authoritative Otter Language Metadata: single source of truth for
// syntax signatures, descriptions, parameter documentation, and examples.

export const OTTER_LANGUAGE_METADATA = [
  // --- Core Statements & Builtins ---
  {
    name: 'say',
    category: 'statement',
    syntax: 'say <expression>',
    doc: 'Outputs text or values directly to the console / standard output.',
    example: 'say "Hello, world!"',
    prefix: /^\s*say\s+/i,
    parameters: [
      { name: 'expression', label: '<expression>', doc: 'Value or text expression to write to standard output.' }
    ]
  },
  {
    name: 'ask',
    category: 'statement',
    syntax: 'ask <prompt> into <variable>',
    doc: 'Prompts the user for interactive input and stores the text response into a variable.',
    example: 'ask "What is your name? " into userName',
    prefix: /^\s*ask\s+/i,
    parameters: [
      { name: 'prompt', label: '<prompt>', doc: 'Prompt string displayed to the user.' },
      { name: 'variable', label: '<variable>', doc: 'Variable name to receive the user response.' }
    ],
    splitParam: /\s+into\s+/i
  },
  {
    name: 'make',
    category: 'statement',
    syntax: 'make <variable> is <value>',
    doc: 'Declares or binds a new variable in the current scope with an initial value.',
    example: 'make count is 0',
    prefix: /^\s*make\s+/i,
    parameters: [
      { name: 'name', label: '<variable>', doc: 'Name of the variable to declare.' },
      { name: 'value', label: '<value>', doc: 'Initial expression or value.' }
    ],
    splitParam: /\s+is\s+/i
  },
  {
    name: 'is',
    category: 'operator',
    syntax: '<target> is <value>',
    doc: 'Assigns a value at statement level, or tests for equality inside a condition.',
    example: 'total is 10'
  },
  {
    name: 'function',
    category: 'statement',
    syntax: 'to <name> [and <params...>]',
    doc: 'Declares a reusable named function with optional parameters.',
    example: 'to greet name\n    say "Hello " name\n.'
  },
  {
    name: 'to',
    category: 'statement',
    syntax: 'to <name> [and <params...>]',
    doc: 'Defines a function with optional parameters separated by "and".',
    example: 'to addNums a and b\n    return a plus b\n.',
    prefix: /^\s*to\s+/i,
    parameters: [
      { name: 'name', label: '<name>', doc: 'Name of the function.' },
      { name: 'params', label: '[and <params...>]', doc: 'Parameters separated by and.' }
    ]
  },
  {
    name: 'return',
    category: 'statement',
    syntax: 'return <expression>',
    doc: 'Returns a value from a function and completes its execution.',
    example: 'return result',
    prefix: /^\s*return\s+/i,
    parameters: [
      { name: 'expression', label: '<expression>', doc: 'Value to return from the function.' }
    ]
  },
  {
    name: 'stop',
    category: 'statement',
    syntax: 'stop',
    doc: 'Terminates the current loop or exits a block early.',
    example: 'stop'
  },
  {
    name: 'if',
    category: 'statement',
    syntax: 'if <condition>',
    doc: 'Executes an indented block if the boolean condition evaluates to true.',
    example: 'if score is greater than 100\n    say "Winner!"\n.',
    prefix: /^\s*if\s+/i,
    parameters: [
      { name: 'condition', label: '<condition>', doc: 'Boolean condition expression.' }
    ]
  },
  {
    name: 'otherwise',
    category: 'statement',
    syntax: 'otherwise [if <condition>]',
    doc: 'Alternative branch when previous if conditions are false.',
    example: 'otherwise\n    say "Try again!"\n.'
  },
  {
    name: 'while',
    category: 'statement',
    syntax: 'while <condition>',
    doc: 'Repeats an indented block as long as the condition evaluates to true.',
    example: 'while count is less than 10\n    increase count\n.',
    prefix: /^\s*while\s+/i,
    parameters: [
      { name: 'condition', label: '<condition>', doc: 'Boolean loop condition.' }
    ]
  },
  {
    name: 'count',
    category: 'statement',
    syntax: 'count <variable> from <start> to <end>',
    doc: 'Iterates a counter variable from a start value to an end value inclusive.',
    example: 'count i from 1 to 5\n    say i\n.',
    prefix: /^\s*count\s+/i,
    parameters: [
      { name: 'var', label: '<variable>', doc: 'Counter loop variable name.' },
      { name: 'start', label: '<start>', doc: 'Starting integer value.' },
      { name: 'end', label: '<end>', doc: 'Ending integer value.' }
    ],
    customActive: (line) => {
      if (/\s+to\s+/i.test(line)) return 2;
      if (/\s+from\s+/i.test(line)) return 1;
      return 0;
    }
  },
  {
    name: 'for each',
    category: 'statement',
    syntax: 'for each <item> in <collection>',
    doc: 'Iterates through each element in a list or collection.',
    example: 'for each file in fileList\n    say file\n.',
    prefix: /^\s*(?:for\s+each|each)\s+/i,
    parameters: [
      { name: 'item', label: '<item>', doc: 'Variable receiving the current item.' },
      { name: 'collection', label: '<collection>', doc: 'List or collection expression.' }
    ],
    splitParam: /\s+in\s+/i
  },
  {
    name: 'repeat',
    category: 'statement',
    syntax: 'repeat <count> times',
    doc: 'Repeats an indented block a specified number of times.',
    example: 'repeat 3 times\n    say "Otter!"\n.',
    prefix: /^\s*repeat\s+/i,
    parameters: [
      { name: 'count', label: '<count>', doc: 'Number of times to repeat.' }
    ]
  },
  {
    name: 'add',
    category: 'statement',
    syntax: 'add <value> to <collection>',
    doc: 'Appends a value to a list or adds a number to a numeric variable.',
    example: 'add 10 to score',
    prefix: /^\s*add\s+/i,
    parameters: [
      { name: 'value', label: '<value>', doc: 'Value or number to add.' },
      { name: 'target', label: '<collection>', doc: 'List or numeric variable target.' }
    ],
    splitParam: /\s+to\s+/i
  },
  {
    name: 'remove',
    category: 'statement',
    syntax: 'remove <value> from <collection>',
    doc: 'Removes an element from a list or decreases a numeric variable.',
    example: 'remove item from items',
    prefix: /^\s*remove\s+/i,
    parameters: [
      { name: 'value', label: '<value>', doc: 'Item or number to remove.' },
      { name: 'target', label: '<collection>', doc: 'List or numeric variable target.' }
    ],
    splitParam: /\s+from\s+/i
  },
  {
    name: 'try',
    category: 'statement',
    syntax: 'try ... otherwise ... .',
    doc: 'Executes a protected block, catching runtime errors in the otherwise branch.',
    example: 'try\n    say 10 divided by 0\notherwise\n    say "Error caught"\n.'
  },

  // --- UI Statements ---
  {
    name: 'put',
    category: 'ui',
    syntax: 'put <widget> in <container>',
    doc: 'Places a child UI widget or layout element into a container element.',
    example: 'put myButton in mainPanel',
    prefix: /^\s*put\s+/i,
    parameters: [
      { name: 'widget', label: '<widget>', doc: 'Widget or element to insert.' },
      { name: 'container', label: '<container>', doc: 'Container widget receiving the element.' }
    ],
    splitParam: /\s+in\s+/i
  },
  {
    name: 'when',
    category: 'ui',
    syntax: 'when <event> <target>',
    doc: 'Binds an event listener block to a UI element or window trigger.',
    example: 'when clicked btnSubmit\n    say "Submitted!"\n.',
    prefix: /^\s*when\s+/i,
    parameters: [
      { name: 'event', label: '<event>', doc: 'Event trigger (e.g. clicked, changed, closed).' },
      { name: 'target', label: '<target>', doc: 'UI element target.' }
    ],
    customActive: (line) => {
      const parts = line.trim().split(/\s+/);
      return parts.length > 2 ? 1 : 0;
    }
  },
  {
    name: 'display',
    category: 'ui',
    syntax: 'display <widget>',
    doc: 'Renders and displays a top-level window or view.',
    example: 'display mainWindow',
    prefix: /^\s*display\s+/i,
    parameters: [
      { name: 'widget', label: '<widget>', doc: 'Window or root widget to display.' }
    ]
  },

  // --- Filesystem Statements ---
  {
    name: 'get files in',
    category: 'stdlib',
    syntax: 'get files in <path> [and subfolders] into <variable>',
    doc: 'Scans the specified folder and returns a list of matching file paths.',
    example: 'get files in "C:/Projects" into projectFiles',
    prefix: /^\s*get\s+files\s+in\s+/i,
    parameters: [
      { name: 'path', label: '<path>', doc: 'Folder path to scan.' },
      { name: 'target', label: '<variable>', doc: 'Target variable receiving the file list.' }
    ],
    splitParam: /\s+into\s+/i
  },
  {
    name: 'get folders in',
    category: 'stdlib',
    syntax: 'get folders in <path> into <variable>',
    doc: 'Queries the directory structure and returns child folder paths.',
    example: 'get folders in "." into dirList',
    prefix: /^\s*get\s+folders\s+in\s+/i,
    parameters: [
      { name: 'path', label: '<path>', doc: 'Folder path to scan.' },
      { name: 'target', label: '<variable>', doc: 'Target variable receiving folder list.' }
    ],
    splitParam: /\s+into\s+/i
  },
  {
    name: 'create folder',
    category: 'stdlib',
    syntax: 'create folder <path>',
    doc: 'Creates a new folder on the filesystem if it does not already exist.',
    example: 'create folder "output"',
    prefix: /^\s*create\s+folder\s+/i,
    parameters: [
      { name: 'path', label: '<path>', doc: 'Folder path to create.' }
    ]
  },
  {
    name: 'copy file to',
    category: 'stdlib',
    syntax: 'copy file <source> to <destination>',
    doc: 'Copies a file on disk from source to destination location.',
    example: 'copy file "data.txt" to "backup/data.txt"',
    prefix: /^\s*copy\s+file\s+/i,
    parameters: [
      { name: 'source', label: '<source>', doc: 'Source file path.' },
      { name: 'destination', label: '<destination>', doc: 'Destination file path.' }
    ],
    splitParam: /\s+to\s+/i
  },

  // --- Literals & Operators ---
  {
    name: 'true',
    category: 'literal',
    syntax: 'true',
    doc: 'Boolean literal representing true.',
    example: 'flag is true'
  },
  {
    name: 'false',
    category: 'literal',
    syntax: 'false',
    doc: 'Boolean literal representing false.',
    example: 'flag is false'
  },
  {
    name: 'gone',
    category: 'literal',
    syntax: 'gone',
    doc: 'Otter literal representing an unassigned, missing, or deleted state.',
    example: 'item is gone'
  },
  {
    name: 'and',
    category: 'operator',
    syntax: '<left> and <right>',
    doc: 'Performs numeric addition in `make` statements, or logical AND in conditions.',
    example: 'if a is 1 and b is 2'
  },
  {
    name: 'or',
    category: 'operator',
    syntax: '<left> or <right>',
    doc: 'Performs logical disjunction (OR) between conditions.',
    example: 'if a is 1 or b is 2'
  },
  {
    name: 'not',
    category: 'operator',
    syntax: 'not <condition>',
    doc: 'Inverts the truth value of a condition.',
    example: 'if not ready'
  },
  {
    name: 'plus',
    category: 'operator',
    syntax: '<left> plus <right>',
    doc: 'Arithmetic addition operator.',
    example: 'total is subtotal plus tax'
  },
  {
    name: 'minus',
    category: 'operator',
    syntax: '<left> minus <right>',
    doc: 'Arithmetic subtraction operator.',
    example: 'net is total minus discount'
  },
  {
    name: 'times',
    category: 'operator',
    syntax: '<left> times <right>',
    doc: 'Arithmetic multiplication operator.',
    example: 'area is width times height'
  },
  {
    name: 'divided by',
    category: 'operator',
    syntax: '<left> divided by <right>',
    doc: 'Arithmetic division operator.',
    example: 'average is sum divided by count'
  },
  {
    name: 'length of',
    category: 'stdlib',
    syntax: 'length of <target>',
    doc: 'Returns the number of characters in a string, or number of items in a list.',
    example: 'len is length of fileList'
  },
  {
    name: 'uppercase of',
    category: 'stdlib',
    syntax: 'uppercase of <string>',
    doc: 'Returns a new string with all characters converted to uppercase.',
    example: 'upper is uppercase of name'
  },
  {
    name: 'lowercase of',
    category: 'stdlib',
    syntax: 'lowercase of <string>',
    doc: 'Returns a new string with all characters converted to lowercase.',
    example: 'lower is lowercase of name'
  },
  {
    name: 'is greater than',
    category: 'operator',
    syntax: '<left> is greater than <right>',
    doc: 'Tests if left value is strictly greater than right value.',
    example: 'if score is greater than 50'
  },
  {
    name: 'is less than',
    category: 'operator',
    syntax: '<left> is less than <right>',
    doc: 'Tests if left value is strictly less than right value.',
    example: 'if count is less than 10'
  },
  {
    name: 'is at least',
    category: 'operator',
    syntax: '<left> is at least <right>',
    doc: 'Tests if left value is greater than or equal to right value.',
    example: 'if age is at least 18'
  },
  {
    name: 'is at most',
    category: 'operator',
    syntax: '<left> is at most <right>',
    doc: 'Tests if left value is less than or equal to right value.',
    example: 'if count is at most 100'
  },
  {
    name: 'is not',
    category: 'operator',
    syntax: '<left> is not <right>',
    doc: 'Tests inequality between values.',
    example: 'if item is not gone'
  }
];

const metadataMap = new Map();
for (const entry of OTTER_LANGUAGE_METADATA) {
  metadataMap.set(entry.name.toLowerCase(), entry);
}

export function getBuiltinMetadata(name) {
  if (!name) return null;
  return metadataMap.get(name.toLowerCase()) || null;
}

export function getBuiltinSignatures() {
  return OTTER_LANGUAGE_METADATA.filter(m => m.prefix && m.parameters);
}
