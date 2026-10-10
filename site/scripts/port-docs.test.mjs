import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { buildPage, castScript, expander, frontMatter, load, snippetLines, toMdx } from './port-docs.mjs';
import { toMarkdown } from './rst.mjs';

const src = load();
const { expand, ctx } = expander(src);

/** An expander over a throwaway repo tree: { 'path': 'content' }. */
function fake(files) {
  const root = mkdtempSync(join(tmpdir(), 'port-'));
  for (const [p, t] of Object.entries(files)) {
    mkdirSync(dirname(join(root, p)), { recursive: true });
    writeFileSync(join(root, p), t);
  }
  return expander({ commands: [], variables: [], rd: (p) => readFileSync(join(root, p), 'utf8'), exists: (p) => existsSync(join(root, p)) });
}

const CAST = (doc) => `#!/usr/bin/env bash\n# cast: true\n# doc: ${doc}\n# title: First configure\n# region cast\ncmake -S . -B build\n# endregion cast\n`;

test('module blocks yield 4 commands and 14 variables', () => {
  assert.deepEqual(src.commands.map((c) => c.name), ['ocx_bootstrap', 'ocx_project', 'ocx_package', 'ocx_index']);
  assert.equal(src.variables.length, 14);
});

test('reference pages convert and keep every entry as a heading', () => {
  const cmds = expand('<!-- cmake: commands -->', 't').text;
  for (const c of src.commands) assert.match(cmds, new RegExp(`^## ${c.name}$`, 'm'));
  assert.match(cmds, /^### FIND$/m);
  const vars = expand('<!-- cmake: variables -->', 't').text;
  for (const v of src.variables) assert.match(vars, new RegExp(`^## ${v.name}$`, 'm'));
  assert.doesNotMatch(expand('<!-- cmake: findocx -->', 't').text, /^Findocx$/m);
});

test('rst constructs', () => {
  assert.equal(toMarkdown('See :command:`ocx_project` and ``x``.', ctx), 'See [`ocx_project`](/integrations/cmake/reference/commands/#ocx_project) and `x`.');
  assert.match(toMarkdown('.. warning::\n\n   Careful.', ctx), /^:::caution\nCareful\.\n\n:::$/);
  assert.match(toMarkdown('Run::\n\n  cmake -P x\n', ctx), /^Run:\n\n```cmake\ncmake -P x\n```$/);
});

test('unknown directives, roles and targets fail loudly', () => {
  assert.throws(() => toMarkdown('.. frobnicate:: x\n\n   y', ctx), /unknown directive/);
  assert.throws(() => toMarkdown(':ref:`x`', ctx), /unknown role/);
  assert.throws(() => toMarkdown(':command:`nope`', ctx), /no \.\. command:: block/);
  assert.throws(() => expand('--8<-- "examples/none.cmake"', 't'), /ENOENT/);
});

test('snippet: whole file, region with markers stripped and indent removed, language from extension', () => {
  const body = 'a = 1\n# region one\n  b = 2\n  # region inner\n  c = 3\n  # endregion\n# endregion one\nd = 4\n';
  assert.deepEqual(snippetLines(body, 'one'), ['b = 2', 'c = 3']);
  assert.deepEqual(snippetLines(body, ''), ['a = 1', '  b = 2', '  c = 3', 'd = 4']);
  const { expand: ex } = fake({ 'x/CMakeLists.txt': 'project(x)\n# region r\nfind_package(ocx)\n# endregion\n', 'y/ocx.toml': '[tools]\n' });
  assert.equal(ex('<!-- snippet: x/CMakeLists.txt#r -->', 'p').text, '```cmake title="CMakeLists.txt"\nfind_package(ocx)\n```');
  assert.equal(ex('<!-- snippet: y/ocx.toml title="ocx.toml in the project" -->', 'p').text, '```toml title="ocx.toml in the project"\n[tools]\n```');
});

test('snippet: a backtick run in the file widens the fence', () => {
  const { expand: ex } = fake({ 'd.md': '```sh\nx\n```\n' });
  assert.match(ex('<!-- snippet: d.md -->', 'p').text, /^````markdown/);
});

test('snippet: missing file, region or endregion fails with the page name', () => {
  const { expand: ex } = fake({ 'f.cmake': '# region r\nx\n', 'g.cmake': 'x\n' });
  assert.throws(() => ex('<!-- snippet: nope.cmake -->', 'guides/a.md'), /guides\/a\.md: snippet: nope\.cmake does not exist/);
  assert.throws(() => ex('<!-- snippet: g.cmake#r -->', 'p'), /no "region r" marker/);
  assert.throws(() => ex('<!-- snippet: f.cmake#r -->', 'p'), /no endregion/);
});

test('cast: emits a Terminal, flags the page as mdx, checks script, header and key', () => {
  const key = 'tutorial/first-configure';
  const { expand: ex } = fake({ [castScript(key)]: CAST(key), 'site/casts/bad__doc.sh': CAST('other'), 'site/casts/plain__x.sh': '# doc: plain/x\n' });
  const r = ex(`text\n<!-- cast: ${key} -->\n`, 'p');
  assert.match(r.text, /^<Terminal src="\/casts\/tutorial\/first-configure\.cast" title="First configure" \/>$/m);
  assert.deepEqual([r.mdx, r.casts], [true, [key]]);
  assert.equal(ex('no directive', 'p').mdx, false);
  assert.throws(() => ex('<!-- cast: no/script -->', 'p'), /no script site\/casts\/no__script\.sh/);
  assert.throws(() => ex('<!-- cast: bad/doc -->', 'p'), /declares "# doc: other"/);
  assert.throws(() => ex('<!-- cast: plain/x -->', 'p'), /lacks "# cast: true"/);
});

test('mdx page: declarations become JSX comments after the front matter, Terminal is imported, code fences stay', () => {
  const key = 'tutorial/first-configure';
  const { expand: ex } = fake({ [castScript(key)]: CAST(key) });
  const page = buildPage(ex, 'tutorial.md', `---\ntitle: T\ndescription: D\n---\n<!-- doc_type: tutorial -->\n<!-- doc_tier: first-steps -->\n\n## Step {#step}\n\n<!-- cast: ${key} -->\n\n\`\`\`html\n<!-- keep -->\n\`\`\`\n`);
  assert.equal(page.dest, 'tutorial.mdx');
  assert.match(page.text, /^---\ntitle: T\ndescription: D\neditUrl: .+\n---\n\{\/\* doc_type: tutorial \*\/\}\n\{\/\* doc_tier: first-steps \*\/\}\n\nimport Terminal from '@ocx-sh\/theme\/components\/Terminal\.astro';\n/);
  assert.match(page.text, /<!-- keep -->/);
  assert.doesNotMatch(page.text.replace(/```html[\s\S]*?```/, ''), /<!--/);
  assert.equal(toMdx('---\nt: 1\n---\nbody\n').includes('{/*'), false);
});

test('page without a cast stays .md; legacy header form still converts; retired port directive fails', () => {
  const { expand: ex } = fake({});
  const legacy = '<!-- doc_type: explanation -->\n<!-- description: Why. -->\n# Title\n\nBody [link](../guides/ci.md#x).\n';
  const page = buildPage(ex, 'concepts/a.md', legacy);
  assert.equal(page.dest, 'concepts/a.md');
  assert.match(page.text, /^---\ntitle: "Title"\ndescription: "Why\."\neditUrl: .+\n---\n<!-- doc_type: explanation -->\n/);
  assert.match(page.text, /\/integrations\/cmake\/guides\/ci\/#x/);
  assert.throws(() => buildPage(ex, 'a.md', '<!-- port: index.rst "X" -->\n# T\n'), /retired directive/);
  assert.throws(() => frontMatter('---\ntitle: T\n---\nx', 'a.md'), /needs description/);
});
