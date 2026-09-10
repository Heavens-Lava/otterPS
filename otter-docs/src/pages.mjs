const escape = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const keywords = /\b(say|ask|and|or|not|if|otherwise|while|repeat|count|for|each|in|to|return|is|at|least|greater|less|than|are|empty|gone|try|read|write|copy|move|delete|file|folder|get|files|folders|into|of|length|uppercase|lowercase|first|last|sort|reverse|split|join|find|where)\b/g;
const code = (source) => `<pre class="otter-code"><code>${source.split(/("(?:\\.|[^"\\])*")/).map((part, index) => index % 2 ? `<span class="tok-string">${escape(part)}</span>` : escape(part).replace(keywords, '<span class="tok-keyword">$1</span>')).join('')}</code></pre>`;
const note = (text) => `<aside class="note"><strong>Note</strong><p>${text}</p></aside>`;

export const sections = [
  ['Getting Started', [
    ['welcome', 'Welcome to Otter'], ['installation', 'Installation'], ['hello', 'Hello, Otter!'], ['running-files', 'Running .ot Files'], ['repl', 'REPL']
  ]],
  ['Learn Otter', [
    ['variables', 'Variables and Values'], ['input-output', 'Input and Output'], ['conditions', 'Conditions'], ['loops', 'Loops'], ['lists', 'Lists'], ['functions', 'Functions'], ['objects', 'Objects'], ['files-folders', 'Files and Folders'], ['error-handling', 'Error Handling']
  ]],
  ['Language Reference', [
    ['values', 'Values and Types'], ['gone', 'gone'], ['operators', 'Operators'], ['property-access', 'Property Access'], ['strings', 'Strings'], ['collections', 'Collections'], ['files', 'Files'], ['folders', 'Folders'], ['try', 'try / otherwise'], ['json', 'JSON'], ['random', 'Random'], ['scope', 'Scope'], ['diagnostics', 'Diagnostics']
  ]],
  ['Examples', [
    ['example-hello', 'Hello World'], ['example-input', 'User Input'], ['example-conditions', 'Conditions'], ['example-counting', 'Counting'], ['example-lists', 'Lists'], ['example-discovery', 'File Discovery'], ['example-organizer', 'File Organizer'], ['example-finding', 'Finding Files'], ['example-errors', 'Error Handling']
  ]],
  ['Language Design', [
    ['design-readable', 'Readable like English. Precise like code.'], ['structural-words', 'Structural Words'], ['properties-operations', 'Properties vs Operations'], ['periods', 'Period / Block Rules'], ['philosophy', 'Design Philosophy']
  ]]
];

const page = (slug, title, section, body, description = '') => ({ slug, title, section, body, description });

export const pages = [
  page('welcome', 'Welcome to Otter', 'Getting Started', `
    <p>Otter is a small programming language designed to read naturally while remaining precise. Programs use words and indentation instead of punctuation-heavy syntax.</p>
    ${code('say "Hello, Otter!"')}
    <p>Start with a short program, then grow into files, folders, objects, and collections without changing how the language reads.</p>`, 'A gentle introduction to Otter.'),
  page('installation', 'Installation', 'Getting Started', `
    <p>Otter currently runs through the project launcher on Windows PowerShell 5.1.</p>
    ${code('.\\otter.cmd examples\\hello.ot')}
    ${note('A packaged installer and editor integration are not documented yet. This page will be updated when an official distribution is available.')}`),
  page('hello', 'Hello, Otter!', 'Getting Started', `<p>Create <code>hello.ot</code>:</p>${code('say "Hello, Otter!"')}<p>Run it with the Otter launcher.</p>`),
  page('running-files', 'Running .ot Files', 'Getting Started', `<p>Pass an Otter source file to the launcher.</p>${code('.\\otter.cmd hello.ot')}<p>Otter reports syntax and runtime errors with the line that needs attention.</p>`),
  page('repl', 'REPL', 'Getting Started', `<p>Run <code>.\\otter.cmd</code> without a file to start the interactive prompt. Type <code>exit</code> to leave it.</p>${code('otter> say "Hello"\nHello')}`),

  page('variables', 'Variables and Values', 'Learn Otter', `<p>Give a value a name with <code>is</code>.</p>${code('name is "Jeff"\nage is 29\nloggedIn is true\nsay name')}`),
  page('input-output', 'Input and Output', 'Learn Otter', `<p><code>say</code> prints values separated by one space. <code>ask</code> reads a value into a name.</p>${code('ask "What is your name?" and call it name\nsay "Hello" name')}`),
  page('conditions', 'Conditions', 'Learn Otter', `<p>Conditions use words such as <code>is at least</code>, <code>is not</code>, <code>and</code>, <code>or</code>, and <code>not</code>.</p>${code('if age is at least 18\n    say "Adult"\notherwise\n    say "Minor"')}`),
  page('loops', 'Loops', 'Learn Otter', `<p>Otter has repeat, while, count, and for-each loops.</p>${code('count from 1 to 3 as number\n    say number\n\nfor each game in games\n    say game')}`),
  page('lists', 'Lists', 'Learn Otter', `<p>Define a list with <code>are</code>. A period may make the block ending explicit.</p>${code('games are\n    "Zelda"\n    "Mario"\n.\n\nsay first of games')}`),
  page('functions', 'Functions', 'Learn Otter', `<p>Functions start with <code>to</code>. Use <code>return</code> to produce a value.</p>${code('to double number\n    number times 2 make answer\n    return answer\n\ndouble 5 make result\nsay result')}`),
  page('objects', 'Objects', 'Learn Otter', `<p>Things have named properties. Read properties with <code>property of object</code>.</p>${code('person is a thing\n    name is "Jeff"\n.\n\nsay name of person')}`),
  page('files-folders', 'Files and Folders', 'Learn Otter', `<p>Otter can work with text files and discover files or folders. File operations use explicit verbs.</p>${code('write "Hello" to "note.txt"\nread "note.txt" into note\nget files in "Pictures" into files')}`),
  page('error-handling', 'Error Handling', 'Learn Otter', `<p>Use <code>try</code> with an optional <code>otherwise</code> for operations that may fail.</p>${code('try\n    read "settings.json" into settings\notherwise\n    say "Could not load settings."\n.')}`),

  page('values', 'Values and Types', 'Language Reference', `<p>Otter values include text, numbers, booleans, lists, objects, and <code>gone</code>.</p>${code('title is "Otter"\nscore is 10\nready is true\ngames are empty')}`),
  page('gone', 'gone', 'Language Reference', `<p><code>gone</code> is Otter’s single absence value. It is different from an empty string, zero, false, and an empty list.</p>${code('user is gone\n\nif user is gone\n    say "No user found."')}`),
  page('operators', 'Operators', 'Language Reference', `<p>Arithmetic reads naturally: <code>and</code>, <code>minus</code>, <code>times</code>, and <code>divided by</code>.</p>${code('5 and 5 make total\n10 minus 5 make difference')}`),
  page('property-access', 'Property Access', 'Language Reference', `<p>Properties are written property-first: <code>name of person</code>. A period is not property access.</p>${code('say name of person\ncity of address of user')}${note('Write <code>name of person</code>, never <code>person.name</code>.')}`),
  page('strings', 'Strings', 'Language Reference', `<p>Derived text operations return new values. They do not alter the original text.</p>${code('say length of name\nsay uppercase of name\nif name starts with "J"\n    say "Starts with J"\n\nreplace "Jeff" with "Jeffrey" in name')}`),
  page('collections', 'Collections', 'Language Reference', `<p>Lists support inspection, matching, ordering, splitting, joining, and finding one item.</p>${code('sort games\nreverse games\nsplit "red,green" by "," into colors\njoin colors with " | " into text\nfind game in games where game is "Mario" into result')}`),
  page('files', 'Files', 'Language Reference', `<p>Read, write, copy, move, and delete files with explicit statements.</p>${code('copy "notes.txt" to "backup/notes.txt"\ndelete file "notes.txt"\nif file "notes.txt" exists\n    say "Found it"')}`),
  page('folders', 'Folders', 'Language Reference', `<p>Discover folders with <code>get folders</code>. Discovery is not recursive unless <code>and subfolders</code> is written.</p>${code('get files in "Pictures" and subfolders into files\ncreate folder "Backup"\ndelete folder "Backup"')}`),
  page('try', 'try / otherwise', 'Language Reference', `<p><code>otherwise</code> runs when the <code>try</code> body fails. A return remains normal control flow.</p>${code('try\n    read "settings.json" into settings\notherwise\n    say "Using defaults."\n.')}`),
  page('json', 'JSON', 'Language Reference', `<p>JSON support is available for reading and converting values. See the project examples and runtime release notes for the current supported forms.</p>${note('This reference page is intentionally brief until the user-facing JSON wording is finalized.')}`),
  page('random', 'Random', 'Language Reference', `<p>Random number and item operations are available in the current runtime.</p>${note('The final public syntax wording is awaiting a dedicated language-reference pass.')}`),
  page('scope', 'Scope', 'Language Reference', `<p>Function parameters and local work do not overwrite names outside the function.</p>${code('name is "Outside"\nto greet name\n    say "Hello" name\ngreet "Jeff"\nsay name')}`),
  page('diagnostics', 'Diagnostics', 'Language Reference', `<p>Otter syntax and runtime errors identify the relevant line and suggest a correction when one is clear.</p>`),

  page('example-hello', 'Hello World', 'Examples', `${code('say "Hello world!"')}`),
  page('example-input', 'User Input', 'Examples', `${code('ask "What is your name?" and call it name\nsay "Hello" name')}`),
  page('example-conditions', 'Conditions', 'Examples', `${code('if score is at least 90\n    say "A"\notherwise\n    say "Keep going"')}`),
  page('example-counting', 'Counting', 'Examples', `${code('count from 1 to 5 as number\n    say number')}`),
  page('example-lists', 'Lists', 'Examples', `${code('games are\n    "Zelda"\n    "Mario"\n.\n\nfor each game in games\n    say "I like" game')}`),
  page('example-discovery', 'File Discovery', 'Examples', `${code('get files in "Pictures" into files\nfor each file in files\n    say name of file')}`),
  page('example-organizer', 'File Organizer', 'Examples', `${code('get files in "Downloads" into files\nfor each file in files\n    if extension of file is ".txt"\n        move file to "Documents"')}`),
  page('example-finding', 'Finding Files', 'Examples', `${code('find file in files where extension of file is ".pdf" into result\nif result is gone\n    say "No PDF found."\notherwise\n    say name of result')}`),
  page('example-errors', 'Error Handling', 'Examples', `${code('try\n    read "settings.json" into settings\notherwise\n    say "Could not load settings."\n.')}`),

  page('design-readable', 'Readable like English. Precise like code.', 'Language Design', `<p>Otter favors language that can be read aloud without hiding program structure.</p>${code('if age is at least 18\n    say "Adult"')}`),
  page('structural-words', 'Structural Words', 'Language Design', `<p>Words such as <code>of</code>, <code>to</code>, <code>from</code>, <code>in</code>, and <code>into</code> carry grammar. They are not noise to remove.</p>`),
  page('properties-operations', 'Properties vs Operations', 'Language Design', `<p><code>name of file</code> reads a property. <code>length of games</code> applies an operation. The similar wording intentionally has different meanings.</p>`),
  page('periods', 'Period / Block Rules', 'Language Design', `<p>Indentation defines blocks. A period on its own line can explicitly close one current block.</p>${code('if ready\n    say "Starting"\n.')}`),
  page('philosophy', 'Design Philosophy', 'Language Design', `<p>Otter avoids unnecessary punctuation, but never at the expense of meaning. The language makes structure visible through words and indentation.</p>`)
];
