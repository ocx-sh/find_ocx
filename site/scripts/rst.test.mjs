import assert from 'node:assert/strict';
import { test } from 'node:test';
import { toMarkdown } from './rst.mjs';

const ctx = {
  commands: new Set(['ocx_project', 'ocx_index']),
  variables: new Set(['OCX_INDEX']),
  urls: { command: '/b/commands/', variable: '/b/variables/' },
  lang: 'cmake',
  scope: 'ocx_index',
};
const md = (rst, extra) => toMarkdown(rst, { ...ctx, ...extra });

// A page in the shape of CMake's own file.rst.
const FILE_RST = `Reading
^^^^^^^

.. parsed-literal::

  \`Reading\`_
    ocx_index(\`FIND\`_ [REQUIRED])
    ocx_index(\`UPDATE_COMMAND\`_ <out-var>)

.. signature:: ocx_index(FIND [REQUIRED])
  :target: FIND
  :break: verbatim

  .. versionadded:: 0.4

  Locates the snapshot, see :variable:\`OCX_INDEX\`.

  .. versionchanged:: 0.5
    The search stops at :variable:\`CMAKE_SOURCE_DIR\`.

.. signature::
  ocx_index(UPDATE_COMMAND <out-var>)

  Composes the command.

Details
~~~~~~~

\`\`--index\`\`
  Names the directory. See :command:\`ocx_project\` and :command:\`find_package\`.
\`\`--quiet\`\`
  Silences it; see :policy:\`CMP0135\`.

.. note::
  Careful.

.. warning::

  Really careful.
`;

test('file.rst constructs: headings, signature options, version notes, definition lists, roles, admonitions', () => {
  const out = md(FILE_RST);
  assert.match(out, /^### Reading \{#ocx_index-reading\}$/m);
  assert.match(out, /^#### Details \{#ocx_index-details\}$/m);
  assert.match(out, /^### FIND \{#ocx_index-find\}\n\n```cmake\nocx_index\(FIND \[REQUIRED\]\)\n```$/m);
  assert.match(out, /^\*\*New in version 0\.4\.\*\*$/m);
  assert.match(out, /^\*\*Changed in version 0\.5\.\*\* The search stops at \[`CMAKE_SOURCE_DIR`\]\(https:\/\/cmake\.org\/cmake\/help\/latest\/variable\/CMAKE_SOURCE_DIR\.html\)\.$/m);
  assert.match(out, /\[`OCX_INDEX`\]\(\/b\/variables\/#ocx_index\)/);
  assert.match(out, /^\*\*`--index`\*\*\n\nNames the directory\. See \[`ocx_project`\]\(\/b\/commands\/#ocx_project\) and \[`find_package`\]\(https:\/\/cmake\.org\/cmake\/help\/latest\/command\/find_package\.html\)\.$/m);
  assert.match(out, /\[`CMP0135`\]\(https:\/\/cmake\.org\/cmake\/help\/latest\/policy\/CMP0135\.html\)/);
  assert.match(out, /^:::note\nCareful\.\n\n:::$/m);
  assert.match(out, /^:::caution\nReally careful\.\n\n:::$/m);
});

test('parsed-literal synopsis keeps its indentation and drops the link markup', () => {
  assert.match(md(FILE_RST), /```cmake\nReading\n {2}ocx_index\(FIND \[REQUIRED\]\)\n {2}ocx_index\(UPDATE_COMMAND <out-var>\)\n```/);
});

test('a reference resolves to a later signature target or section, in prose too', () => {
  const out = md('See `READ`_ and `Notes`_.\n\n.. signature:: ocx_index(READ <f>)\n  :target: READ\n\n  Reads.\n\nNotes\n^^^^^\n\nx.');
  assert.match(out, /\[READ\]\(#ocx_index-read\)/);
  assert.match(out, /\[Notes\]\(#ocx_index-notes\)/);
});

test('depth moves the headings, scope prefixes the ids, a signature defaults to its operation', () => {
  const out = md('.. signature::\n  ocx_index(UPDATE_COMMAND <v>)\n\nHeading\n^^^^^^^\n', { depth: 1, scope: '' });
  assert.match(out, /^## UPDATE_COMMAND \{#update_command\}$/m);
  assert.match(out, /^## Heading \{#heading\}$/m);
});

test('unknown constructs fail loudly', () => {
  assert.throws(() => md('.. frobnicate:: x\n\n   y'), /unknown directive \.\. frobnicate::/);
  assert.throws(() => md(':ref:`x`'), /unknown role :ref:/);
  assert.throws(() => md(':command:`ocx_nope`'), /no \.\. command:: block/);
  assert.throws(() => md(':variable:`OCX_NOPE`'), /no \.\. variable:: block/);
  assert.throws(() => md(':policy:`not-a-policy`'), /no \.\. policy:: block/);
  assert.throws(() => md('`Nowhere`_'), /names no signature target or section/);
  assert.throws(() => md('.. parsed-literal::\n\n  x(`GONE`_)'), /names no signature target/);
  assert.throws(() => md('.. signature:: ocx_index(X)\n  :target: X\n  :break: all\n\n  t'), /only verbatim/);
  assert.throws(() => md('.. signature:: ocx_index(X)\n  :colour: red\n\n  t'), /unknown \.\. signature:: option :colour:/);
  assert.throws(() => md('.. signature:: ocx_index(lower)\n\n  t'), /without an operation or :target:/);
  assert.throws(() => md('.. versionadded:: soon\n'), /needs a version/);
  assert.throws(() => md('Title\n=====\n'), /unexpected heading/);
  assert.throws(() => md('Long title here\n^^^^\n'), /underline too short/);
});
