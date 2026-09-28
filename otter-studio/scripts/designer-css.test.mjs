// Designer CSS engine certification: the stylesheet the designer edits keeps
// everything a person wrote by hand (comments, @media, states, @keyframes,
// tricky values) and round-trips to identical text.
import assert from 'node:assert/strict';
import { CssAstManager } from '../js/compiler/css-ast.js';

const handWritten = `/* Application Stylesheet */
#app {
    display: flex;
    background: url("data:image/png;base64,AAAA;BBBB");
}

#card:hover {
    transform: translateY(-2px);
}

@media (max-width: 900px) {
    #card {
        width: 100%;
    }

    #title {
        font-size: 20px;
    }
}

@keyframes pop {
    from { opacity: 0; }
    to { opacity: 1; }
}

@import url("fonts.css");
`;

// 1. Round trip is stable and lossless.
const css = new CssAstManager(handWritten);
const once = css.generateCss();
const twice = new CssAstManager(once).generateCss();
assert.equal(twice, once, 'parse(generate(x)) generates identical text');
assert.match(once, /\/\* Application Stylesheet \*\//, 'keeps comments');
assert.match(once, /@keyframes pop \{[\s\S]*to \{ opacity: 1; \}/, 'keeps @keyframes verbatim');
assert.match(once, /@import url\("fonts.css"\);/, 'keeps statement at-rules');
assert.equal(css.getProperty('#app', 'background'), 'url("data:image/png;base64,AAAA;BBBB")',
  'a semicolon inside url(...) does not split the declaration');

// 2. @media rules are addressable and do not leak into the top level.
assert.deepEqual(css.getMediaQueries(), ['(max-width: 900px)']);
assert.equal(css.getProperty('#card', 'width', '(max-width: 900px)'), '100%');
assert.equal(css.getProperty('#card', 'width'), null, 'breakpoint value is not a base value');
assert.equal(css.getProperty('#title', 'font-size', '(max-width:900px)'), '20px',
  'media lookup ignores spacing differences');

// 3. Writing into a breakpoint creates the block once, then reuses it.
css.setProperty('#card', 'padding', '8px', '(max-width: 600px)');
css.setProperty('#title', 'font-size', '16px', '(max-width: 600px)');
assert.deepEqual(css.getMediaQueries(), ['(max-width: 900px)', '(max-width: 600px)']);
assert.match(css.generateCss(), /@media \(max-width: 600px\) \{\n    #card \{\n        padding: 8px;\n    \}\n\n    #title \{\n        font-size: 16px;\n    \}\n\}/);

// 4. State selectors are separate rules.
css.setProperty('#card:hover', 'background', '#eef');
assert.equal(css.getProperty('#card:hover', 'background'), '#eef');
assert.equal(css.getProperty('#card:hover', 'transform'), 'translateY(-2px)', 'existing state rule is reused');

// 5. Removing the last declaration removes the rule, and an emptied @media block.
css.setProperty('#card', 'padding', null, '(max-width: 600px)');
css.removeProperty('#title', 'font-size', '(max-width: 600px)');
assert.deepEqual(css.getMediaQueries(), ['(max-width: 900px)'], 'empty @media block is pruned');
css.setProperty('#lonely', 'color', 'red');
css.removeProperty('#lonely', 'color');
assert.doesNotMatch(css.generateCss(), /#lonely/, 'empty rule is pruned');

// 6. Families: rename, copy and remove follow a component everywhere.
css.renameSelectorFamily('card', 'heroCard');
assert.equal(css.getProperty('#heroCard:hover', 'background'), '#eef');
assert.equal(css.getProperty('#heroCard', 'width', '(max-width: 900px)'), '100%');
assert.equal(css.getProperty('#card:hover', 'background'), null);

css.setProperty('#heroCardTitle', 'color', 'blue');
css.copySelectorFamily('heroCard', 'heroCard2');
assert.equal(css.getProperty('#heroCard2:hover', 'transform'), 'translateY(-2px)');
assert.equal(css.getProperty('#heroCard2', 'width', '(max-width: 900px)'), '100%');
assert.equal(css.getProperty('#heroCard2Title', 'color'), null, '#heroCardTitle is a different component');

css.removeSelectorFamily('heroCard2');
assert.equal(css.getProperty('#heroCard2:hover', 'transform'), null);
assert.equal(css.getProperty('#heroCard', 'width', '(max-width: 900px)'), '100%', 'the original is untouched');
assert.equal(css.getProperty('#heroCardTitle', 'color'), 'blue', 'a similarly named component is untouched');

// 7. Duplicate declarations collapse to one when edited.
const dupes = new CssAstManager('#a {\n    color: red;\n    color: blue;\n}\n');
assert.equal(dupes.getProperty('#a', 'color'), 'blue', 'last declaration wins, as in CSS');
dupes.setProperty('#a', 'color', 'green');
assert.equal((dupes.generateCss().match(/color:/g) || []).length, 1);

// 8. Palette lists colors by use.
const palette = new CssAstManager('#a { color: #2563eb; }\n#b { background: #2563EB; border: 1px solid rgba(0, 0, 0, 0.1); }\n');
assert.deepEqual(palette.getColorPalette(), ['#2563eb', 'rgba(0, 0, 0, 0.1)']);

// 9. An empty stylesheet stays empty.
assert.equal(new CssAstManager('').generateCss(), '');

// 10. Breakpoints stay widest-first whatever order they are created in, so the
// narrower one wins on a phone (both max-width rules match there).
const order = new CssAstManager('#a { color: red; }\n');
order.setProperty('#a', 'color', 'green', '(max-width: 600px)');
order.setProperty('#a', 'color', 'blue', '(max-width: 900px)');
assert.deepEqual(order.getMediaQueries(), ['(max-width: 900px)', '(max-width: 600px)']);
assert.ok(order.generateCss().indexOf('900px') < order.generateCss().indexOf('600px'));

// 11. A new plain rule for a selector a breakpoint already styles is written
// above that @media block, so the breakpoint still overrides it. Any other
// new rule is appended, leaving existing text where it was.
const late = new CssAstManager('#a { color: red; }\n');
late.setProperty('#b', 'color', 'green', '(max-width: 600px)');
late.setProperty('#b', 'color', 'blue');
late.setProperty('#c', 'color', 'black');
const lateCss = late.generateCss();
assert.ok(lateCss.indexOf('#b {') < lateCss.indexOf('@media'), 'base #b precedes the @media block that overrides it');
assert.ok(lateCss.startsWith('#a { color: red; }\n'), 'existing text untouched');
assert.ok(lateCss.indexOf('#c {') > lateCss.indexOf('@media'), 'unrelated rule appended');

// 12. Lossless: unedited text comes back byte for byte, and an edit inside
// an @media block rewrites only that declaration.
const lossText = '/* keep */\n#a{color:red}\n\n@media (max-width: 900px) {\n  #a { color: blue; margin:0 }\n  #z{top:1px}\n}\n';
const lossless = new CssAstManager(lossText);
assert.equal(lossless.generateCss(), lossText);
assert.equal(lossless.dirty, false);
lossless.setProperty('#a', 'color', 'green', '(max-width: 900px)');
assert.equal(lossless.generateCss(), lossText.replace('color: blue', 'color: green'));
assert.equal(lossless.dirty, true);
lossless.markSaved('rev-2');
assert.equal(lossless.dirty, false);
assert.equal(lossless.revision, 'rev-2');

console.log('Designer CSS engine certification passed (12 checks).');
