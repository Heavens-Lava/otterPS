// otter-studio/js/navigation/hover-provider.js

export const OTTER_DOCS = {
  'say': {
    signature: 'say <expression>',
    description: 'Outputs text or values directly to the console / standard output.',
    example: 'say "Hello, world!"'
  },
  'ask': {
    signature: 'ask <prompt> into <variable>',
    description: 'Prompts the user for interactive input and stores the text response into a variable.',
    example: 'ask "What is your name? " into userName'
  },
  'make': {
    signature: 'make <variable> [is <value>]',
    description: 'Declares a new variable or instantiates a new object in the current scope.',
    example: 'make count is 0'
  },
  'is': {
    signature: '<target> is <value>',
    description: 'Assigns a value at statement level, or tests for equality inside a condition.',
    example: 'total is 10'
  },
  'function': {
    signature: 'function <name> [with <params...>]',
    description: 'Declares a reusable named function with optional parameters.',
    example: 'function greet with name\n    say "Hello " name\n.'
  },
  'return': {
    signature: 'return <expression>',
    description: 'Returns a value from a function and finishes its execution.',
    example: 'return result'
  },
  'stop': {
    signature: 'stop',
    description: 'Terminates the current loop or exits a block early.',
    example: 'stop'
  },
  'when': {
    signature: 'when <event> <target>',
    description: 'Binds an event listener to a UI component or window trigger.',
    example: 'when clicked btnSubmit\n    say "Submitted!"\n.'
  },
  'put': {
    signature: 'put <widget> in <container>',
    description: 'Places a child widget or layout item into a container element.',
    example: 'put myButton in mainPanel'
  },
  'display': {
    signature: 'display <widget>',
    description: 'Renders and displays a top-level window or view.',
    example: 'display mainWindow'
  },
  'for each': {
    signature: 'for each <item> in <collection>',
    description: 'Iterates through each element in a list or array.',
    example: 'for each file in fileList\n    say file\n.'
  },
  'while': {
    signature: 'while <condition>',
    description: 'Repeats a block of code as long as the condition evaluates to true.',
    example: 'while count is less than 10\n    increase count\n.'
  },
  'count': {
    signature: 'count <variable> from <start> to <end>',
    description: 'Iterates a counter variable from a start value to an end value.',
    example: 'count i from 1 to 5\n    say i\n.'
  },
  'repeat': {
    signature: 'repeat <count> times',
    description: 'Repeats a block of statements a specified number of times.',
    example: 'repeat 3 times\n    say "Hip hip hooray!"\n.'
  },
  'if': {
    signature: 'if <condition>',
    description: 'Executes the block if the condition evaluates to true.',
    example: 'if score is greater than 100\n    say "Winner!"\n.'
  },
  'otherwise': {
    signature: 'otherwise [if <condition>]',
    description: 'Provides a fallback alternative branch when earlier conditions are false.',
    example: 'otherwise\n    say "Try again!"\n.'
  },
  'get files in': {
    signature: 'get files in <path> [and subfolders] into <variable>',
    description: 'Scans the specified folder and returns a list of matching file paths.',
    example: 'get files in "C:/Projects" into projectFiles'
  },
  'get folders in': {
    signature: 'get folders in <path> into <variable>',
    description: 'Queries the directory structure and returns child folder paths.',
    example: 'get folders in "." into dirList'
  },
  'create folder': {
    signature: 'create folder <path>',
    description: 'Creates a new folder on the filesystem if it does not already exist.',
    example: 'create folder "output"'
  },
  'copy file to': {
    signature: 'copy file <source> to <destination>',
    description: 'Copies a file on disk to the destination location.',
    example: 'copy file "data.txt" to "backup/data.txt"'
  },
  'true': {
    signature: 'true',
    description: 'Boolean literal representing true.'
  },
  'false': {
    signature: 'false',
    description: 'Boolean literal representing false.'
  },
  'gone': {
    signature: 'gone',
    description: 'Otter literal representing an unassigned, missing, or deleted state.'
  },
  'and': {
    signature: '<left> and <right>',
    description: 'Performs numeric addition in `make` statements, or logical AND in conditions.'
  },
  'or': {
    signature: '<left> or <right>',
    description: 'Performs logical disjunction (OR) between conditions.'
  },
  'not': {
    signature: 'not <condition>',
    description: 'Inverts the truth value of a condition.'
  },
  'length of': {
    signature: 'length of <target>',
    description: 'Returns the number of characters in a string, or number of items in a list.'
  },
  'uppercase of': {
    signature: 'uppercase of <string>',
    description: 'Returns a new string with all letters converted to uppercase.'
  },
  'lowercase of': {
    signature: 'lowercase of <string>',
    description: 'Returns a new string with all letters converted to lowercase.'
  }
};

export function getWordAtOffset(text, offset) {
  if (!text || offset < 0 || offset >= text.length) return null;
  const isWordChar = c => /[A-Za-z0-9_]/.test(c || '');
  
  let lineStart = text.lastIndexOf('\n', offset - 1) + 1;
  let lineEnd = text.indexOf('\n', offset);
  if (lineEnd === -1) lineEnd = text.length;
  const line = text.slice(lineStart, lineEnd);
  const col = offset - lineStart;

  const multiWordKeywords = [
    'is at least', 'is at most', 'is greater than', 'is less than', 'is not',
    'get files in', 'get folders in', 'and subfolders into', 'copy file to',
    'for each', 'name of', 'extension of', 'create folder', 'divided by',
    'on tick', 'on key'
  ];

  for (const phrase of multiWordKeywords) {
    let searchIdx = 0;
    while ((searchIdx = line.toLowerCase().indexOf(phrase, searchIdx)) !== -1) {
      if (col >= searchIdx && col <= searchIdx + phrase.length) {
        return phrase;
      }
      searchIdx += phrase.length;
    }
  }

  let start = col;
  let end = col;
  if (!isWordChar(line[col])) {
    if (col > 0 && isWordChar(line[col - 1])) {
      start = col - 1;
      end = col - 1;
    } else {
      return null;
    }
  }
  while (start > 0 && isWordChar(line[start - 1])) start--;
  while (end < line.length && isWordChar(line[end])) end++;
  return line.slice(start, end) || null;
}

export function getHoverInfo(word, filePath, symbols = []) {

  if (!word) return null;
  const lower = word.toLowerCase();

  // 1. Check built-in docs
  if (OTTER_DOCS[lower]) {
    const doc = OTTER_DOCS[lower];
    return {
      kind: 'builtin',
      title: word,
      signature: doc.signature,
      description: doc.description,
      example: doc.example || null
    };
  }

  // 2. Check workspace/file symbols
  const activeSymbols = symbols.filter(s => s.path === filePath || !filePath);
  const match = activeSymbols.find(s => s.name?.toLowerCase() === lower);
  if (match) {
    return {
      kind: match.kind || 'symbol',
      title: match.name,
      signature: match.kind === 'function' ? `function ${match.name}` : `${match.name}`,
      description: `Defined in ${match.path || 'current file'} at line ${match.line}.`,
      line: match.line,
      path: match.path
    };
  }

  return null;
}
