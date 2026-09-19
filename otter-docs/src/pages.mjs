const escape = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const keywords = /\b(say|ask|call|it|and|or|not|if|otherwise|while|repeat|times|count|for|each|in|to|from|return|is|at|least|most|greater|less|than|starts|ends|with|contains|are|empty|gone|true|false|make|makes|add|remove|minus|divided|by|thing|has|try|read|write|copy|move|delete|create|file|folder|files|folders|subfolders|exists|get|into|of|run|command|length|uppercase|lowercase|first|last|sort|reverse|replace|split|join|find|where|as|json|convert|random|number|item|today|now|year|years|month|months|day|days|hour|hours|minute|minutes|second|seconds|format|between|log|warn|error)\b/g;
const code = (source) => `<pre class="otter-code" data-otter="1"><code>${source.split(/("(?:\\.|[^"\\])*")/).map((part, index) => index % 2 ? `<span class="tok-string">${escape(part)}</span>` : escape(part).replace(keywords, '<span class="tok-keyword">$1</span>')).join('')}</code></pre>`;

// Terminal commands and REPL transcripts are NOT Otter source. They are
// marked differently so scripts/check-examples.mjs skips them.
const shell = (source) => `<pre class="shell-code"><code>${escape(source)}</code></pre>`;
const note = (text) => `<aside class="note"><strong>Note</strong><p>${text}</p></aside>`;

export const sections = [
  ['Getting Started', [
    ['welcome', 'Welcome to Otter'], ['download', 'Download Otter'], ['installation', 'Installation'], ['hello', 'Hello, Otter!'], ['running-files', 'Running .ot Files'], ['repl', 'REPL']
  ]],
  ['Learn Otter', [
    ['variables', 'Variables and Values'], ['input-output', 'Input and Output'], ['conditions', 'Conditions'], ['loops', 'Loops'], ['lists', 'Lists'], ['functions', 'Functions'], ['objects', 'Objects'], ['files-folders', 'Files and Folders'], ['error-handling', 'Error Handling']
  ]],
  ['Language Reference', [
    ['values', 'Values and Types'], ['gone', 'gone'], ['operators', 'Operators'], ['property-access', 'Property Access'], ['strings', 'Strings'], ['collections', 'Collections'], ['files', 'Files'], ['folders', 'Folders'], ['try', 'try / otherwise'], ['json', 'JSON'], ['random', 'Random'], ['dates', 'Dates and Time'], ['scope', 'Scope'], ['diagnostics', 'Diagnostic Output']
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
  page('download', 'Download Otter', 'Getting Started', `
    <p class="lead">Otter is currently distributed as a Windows-friendly project folder. It includes the <code>otter</code> launcher, the language implementation, examples, tests, and editor support.</p>
    <section class="download-hero">
      <div>
        <p class="eyebrow">CURRENT RELEASE</p>
        <h2>Otter for Windows</h2>
        <p>Run Otter with Windows PowerShell 5.1. No separate runtime installation is required.</p>
      </div>
      <div class="download-status"><strong>Source-first release</strong><span>Installer coming later</span></div>
    </section>
    <h2>Start from the Otter folder</h2>
    <p>Open PowerShell in the folder containing <code>otter.cmd</code>, then run one of the included examples:</p>
    ${shell('.\\otter.cmd examples\\hello.ot')}
    <p>To make the <code>otter</code> command available from any folder, add the Otter project folder to your user PATH. See <a href="/installation/">Installation</a> for the exact command and a quick verification step.</p>
    <h2>What is included</h2>
    <div class="download-grid">
      <div><strong>Otter launcher</strong><span>Run <code>.ot</code> programs from PowerShell.</span></div>
      <div><strong>Examples</strong><span>Learn from programs you can run and change.</span></div>
      <div><strong>VS Code support</strong><span>Syntax highlighting and editor help for <code>.ot</code> files.</span></div>
      <div><strong>Web compiler</strong><span>Build an Otter web program with <code>otter web</code>.</span></div>
    </div>
    ${note('An official installer and public release-download link are not published yet. Until then, use the Otter project folder supplied with the current release.')}`,
    'How to get and run the current Windows release of Otter.'),
  page('installation', 'Installation', 'Getting Started', `
    <p>Otter runs on Windows PowerShell 5.1. Start from the Otter project folder, which contains the launcher and examples. See <a href="/download/">Download Otter</a> for what is currently included.</p>
    ${shell('.\\otter.cmd examples\\hello.ot')}
    <p>To use <code>otter</code> from any folder, the way <code>python</code> works, add the project folder to your PATH once:</p>
    ${shell("$userPath = [Environment]::GetEnvironmentVariable('Path','User')\n[Environment]::SetEnvironmentVariable('Path', $userPath + ';C:\\path\\to\\otterPS', 'User')")}
    <p>Open a <strong>new</strong> terminal afterwards. A program keeps the environment it started with, so an already-open window will not see the change.</p>
    ${shell('otter hello.ot')}
    ${note('A packaged installer is not available yet. This page will be updated when an official distribution exists.')}`),
  page('hello', 'Hello, Otter!', 'Getting Started', `<p>Create <code>hello.ot</code>:</p>${code('say "Hello, Otter!"')}<p>Run it with the Otter launcher.</p>`),
  page('running-files', 'Running .ot Files', 'Getting Started', `<p>Pass an Otter source file to the launcher.</p>${shell('otter hello.ot')}<p>Otter reports syntax and runtime errors with the line that needs attention.</p><p>To check that a file is well formed without running it, add <code>-ParseOnly</code>. Nothing is printed, no file is written, and no program is launched.</p>${shell('otter hello.ot -ParseOnly')}`),
  page('repl', 'REPL', 'Getting Started', `<p>Run <code>otter</code> without a file to start the interactive prompt. Variables set on one line are still there on the next. Type <code>exit</code> to leave it.</p>${shell('otter> name is "Jeff"\notter> say "Hello" name\nHello Jeff\notter> exit')}`),

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
  page('property-access', 'Property Access', 'Language Reference', `<p>Properties are written property-first: <code>name of person</code>. A period is not property access.</p>${code('say name of person')}<p>Property access nests, reading right to left. This is the <code>city</code> of the <code>address</code> of the <code>user</code>:</p>${code('say city of address of user')}<p>A property can also be assigned:</p>${code('age of person is 30')}${note('Write <code>name of person</code>, never <code>person.name</code>. Otter reserves the period for closing a block.')}`),
  page('strings', 'Strings', 'Language Reference', `<p>Derived text operations return new values. They do not alter the original text.</p>${code('say length of name\nsay uppercase of name\nif name starts with "J"\n    say "Starts with J"\n\nreplace "Jeff" with "Jeffrey" in name')}`),
  page('collections', 'Collections', 'Language Reference', `<p>Lists support inspection, matching, ordering, splitting, joining, and finding one item.</p>${code('sort games\nreverse games\nsplit "red,green" by "," into colors\njoin colors with " | " into text\nfind game in games where game is "Mario" into result')}`),
  page('files', 'Files', 'Language Reference', `<p>Read, write, copy, move, and delete files with explicit statements.</p>${code('copy "notes.txt" to "backup/notes.txt"\ndelete file "notes.txt"\nif file "notes.txt" exists\n    say "Found it"')}`),
  page('folders', 'Folders', 'Language Reference', `<p>Discover folders with <code>get folders</code>. Discovery is not recursive unless <code>and subfolders</code> is written.</p>${code('get files in "Pictures" and subfolders into files\ncreate folder "Backup"\ndelete folder "Backup"')}`),
  page('try', 'try / otherwise', 'Language Reference', `<p><code>otherwise</code> runs when the <code>try</code> body fails. A return remains normal control flow.</p>${code('try\n    read "settings.json" into settings\notherwise\n    say "Using defaults."\n.')}`),
  page('json', 'JSON', 'Language Reference', `<p>Read JSON straight from a file:</p>${code('read json from "settings.json" into settings\nsay theme of settings')}<p>There is <strong>no JSON navigation syntax</strong>. Once it is read, JSON is ordinary Otter data: an object is a thing, a list is a list, and JSON <code>null</code> is <code>gone</code>. Everything you already know about properties works on it.</p>${code('say city of address of user\n\nfor each tag in tags of user\n    say tag\n.\n\nif boss of user is gone\n    say "No boss on record."\n.')}<p>Text can be converted in both directions:</p>${code('convert user to json into text\nconvert text from json into again')}`),
  page('random', 'Random', 'Language Reference', `<p>Pick a number, with both ends of the range included:</p>${code('random number from 1 to 6 into roll\nsay "You rolled" roll')}<p>Or pick from a list:</p>${code('random item from games into pick\nsay "Tonight we play" pick')}<p>Picking from an empty list gives <code>gone</code> rather than failing, so the empty case can be handled the same way as anywhere else.</p>${code('random item from shelf into nothing\n\nif nothing is gone\n    say "The shelf is empty."\n.')}`),

  page('dates', 'Dates and Time', 'Language Reference', `
    <p>A date is a real Otter value, not text. <code>today</code> gives the current date; <code>now</code> gives the current date and time.</p>
    ${code('date is today\nstarted is now')}

    <h2>A date and a date-time are different</h2>
    <p><code>today</code> has no time of day at all &mdash; it is not midnight, it simply does not carry a time. <code>now</code> carries both a date and a time. This is a meaningful distinction, not a technicality: a date with "no time" and a date at "00:00:00" are not the same idea, so Otter does not pretend one is the other.</p>
    <p>Because of that, asking a plain date for its hour, minute, or second is invalid rather than answering with a silent zero:</p>
    ${code('date is today\nsay hour of date')}
    <p>That fails when it runs, with an error explaining that this date has no time of day. Reach for <code>now</code> when you need a time as well as a date.</p>

    <h2>Reading the parts of a date</h2>
    <p>Date parts are read the same way any other property is read &mdash; with <code>of</code>, not with a period. Year, month, and day work on both a date and a date-time:</p>
    ${code('say year of date\nsay month of date\nsay day of date')}
    <p><code>month of date</code> is always a number from 1 to 12, never a month name.</p>
    <p>Hour, minute, and second work on a date-time such as <code>started</code>:</p>
    ${code('say hour of started\nsay minute of started\nsay second of started')}

    <h2>Adjusting a date</h2>
    <p>Move a date forward with <code>add</code>, or backward with <code>remove</code>. Both the singular and plural spelling of a unit are accepted, so <code>1 day</code> and <code>7 days</code> both work:</p>
    ${code('add 7 days to date\nremove 1 month from date')}
    <p>The same words work on a date-time, down to the second:</p>
    ${code('add 1 hour to started\nadd 30 minutes to started')}

    <h2>Formatting</h2>
    <p><code>format ... as ... into ...</code> produces text. It does not change the date it was given:</p>
    ${code('format date as "MM/dd/yyyy" into text\nsay text\nsay date')}
    <p>The second <code>say</code> still prints the original date, untouched.</p>

    <h2>The difference between two dates</h2>
    <p><code>days between</code> is an expression, so assign it with the same <code>is</code> form used for every other value:</p>
    ${code('waiting is days between startDate and endDate\nsay waiting')}
    <p>The expression can also be used directly wherever a value is expected:</p>
    ${code('say days between startDate and endDate')}
    <p>The older <code>days between ... make ...</code> statement remains accepted for compatibility, but new programs should prefer the expression form.</p>
    <p>The result is signed, computed as <code>end minus start</code>:</p>
    <ul>
      <li>positive &mdash; <code>endDate</code> is later than <code>startDate</code></li>
      <li>zero &mdash; the two are the same, at the precision asked for</li>
      <li>negative &mdash; <code>endDate</code> is earlier than <code>startDate</code></li>
    </ul>

    <h2>Comparing dates</h2>
    <p>Dates compare with the same words as any other value &mdash; there is no separate date-comparison syntax:</p>
    ${code('if endDate is greater than startDate\n    say "The end date is later."\n.\n\nif date is not started\n    say "These are different moments."\n.')}

    <h2>How a date prints</h2>
    <p><code>say</code> prints a date-only value like this:</p>
    ${code('say today')}
    ${note('Example output: <code>2026-09-09</code>')}
    <p>and a date-time value like this:</p>
    ${code('say now')}
    ${note('Example output: <code>2026-09-09 14:30:05</code>')}

    <h2>Not part of this version</h2>
    <p>There is no timezone syntax &mdash; a date is always in local time. There is no month-name syntax; <code>month of date</code> is always a number.</p>`,
    'today, now, and reading, adjusting, formatting, and comparing date values.'),
  page('scope', 'Scope', 'Language Reference', `<p>Function parameters and local work do not overwrite names outside the function.</p>${code('name is "Outside"\nto greet name\n    say "Hello" name\ngreet "Jeff"\nsay name')}`),
  page('diagnostics', 'Diagnostic Output', 'Language Reference', `
    <p><code>log</code>, <code>warn</code>, and <code>error</code> send a message to Otter's diagnostic output rather than to the program's normal output.</p>
    ${code('log "Server started."\nwarn "Connection is slow."\nerror "Could not connect."')}
    ${note('This page is about the <code>log</code> / <code>warn</code> / <code>error</code> statements. It is not about the messages Otter itself prints when a program has a syntax or runtime error &mdash; every reference page shows what those look like for the statement it covers.')}
    <h2>Diagnostics are not <code>say</code></h2>
    <p><code>say</code> is what a program tells the person using it. <code>log</code>, <code>warn</code>, and <code>error</code> are what it tells whoever is running or operating it &mdash; a developer watching a console, a log file, a monitoring tool. Otter keeps the two separate on purpose:</p>
    ${code('say "Welcome!"\nlog "Startup complete."')}
    <p>A host running Otter can send <code>say</code> output to a user interface while sending diagnostics somewhere else entirely, such as a log file or a monitoring service, without the program needing to know or care. They travel on separate channels.</p>
    <h2>Three levels</h2>
    <p>All three take the same kind of message as <code>say</code> &mdash; one or more values, joined with a space:</p>
    ${code('port is 8080\nlog "Listening on port" port')}
    <p><code>log</code> records something that happened normally. <code>warn</code> flags something that is not wrong yet but is worth attention. <code>error</code> reports something that failed.</p>
    <h2>A realistic example</h2>
    ${code('port is 8080\n\nsay "Otter web server"\n\nlog "Starting up."\nlog "Listening on port" port\nwarn "No configuration file found, using defaults."\nerror "Could not reach the database."\n\nsay "Ready."')}
    <p>Only the <code>say</code> lines are part of what the program is telling its user. The <code>log</code>, <code>warn</code>, and <code>error</code> lines went to the diagnostic channel.</p>`, 'log, warn, and error: diagnostic output kept separate from what a program says to its user.'),

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
