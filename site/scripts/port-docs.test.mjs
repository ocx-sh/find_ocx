import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkCoverage, expander, load } from './port-docs.mjs';
import { toMarkdown } from './rst.mjs';

const src = load();
const { expand, used, ctx } = expander(src);

test('module blocks yield 4 commands and 14 variables', () => {
  assert.deepEqual(src.commands.map((c) => c.name), ['ocx_bootstrap', 'ocx_project', 'ocx_package', 'ocx_index']);
  assert.equal(src.variables.length, 14);
});

test('reference pages convert and keep every entry as a heading', () => {
  const cmds = expand('<!-- cmake: commands -->', 't');
  for (const c of src.commands) assert.match(cmds, new RegExp(`^## ${c.name}$`, 'm'));
  assert.match(cmds, /^### FIND$/m);
  const vars = expand('<!-- cmake: variables -->', 't');
  for (const v of src.variables) assert.match(vars, new RegExp(`^## ${v.name}$`, 'm'));
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

test('every rst section is ported or covered', () => {
  const pages = { 'tutorial.md': 'OCX_PULL OCX_BOOTSTRAP', 'guides/mirror.md': '', 'guides/nested-builds.md': '' };
  const problems = checkCoverage(src, used, pages);
  assert.ok(problems.some((p) => p.includes('Two entry points')), 'unported sections are reported');
});
