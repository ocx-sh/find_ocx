import assert from 'node:assert/strict';
import { test } from 'node:test';
import { driver, parseScript, sanitize } from './record-casts.mjs';

const script = `#!/usr/bin/env bash
# cast: true
# doc: a/b
# title: T
set -e
# region cast
echo one

echo two
# endregion cast
test 1
`;

test('parseScript reads headers and the cast region', () => {
  const s = parseScript(script);
  assert.deepEqual([s.meta.cast, s.meta.doc, s.meta.title], ['true', 'a/b', 'T']);
  assert.equal(s.cast.body, 'echo one\n\necho two\n');
});

test('driver types every block and runs pre and post silently', () => {
  const d = driver(parseScript(script));
  assert.equal([...d.matchAll(/^__block <<'/gm)].length, 2);
  assert.match(d, /exec 3>&1 4>&2 >\/dev\/null 2>&1\n[\s\S]*set -e[\s\S]*exec >&3 2>&4/);
  assert.match(d, /exec >\/dev\/null 2>&1\ntest 1/);
});

test('sanitize merges bursts, rewrites paths, shortens digests and timings, keeps typing events', () => {
  const dig = 'a'.repeat(64);
  const cast = [
    { version: 3, term: { cols: 100, rows: 40 }, timestamp: 1, command: '/home/u/x', env: { SHELL: '/bin/zsh' } },
    [2, 'o', 'built in /tmp/r/wor'], [0.001, 'o', 'k/build (0.0123s)\r\n'],
    [0.04, 'o', 'x'], [0.04, 'o', `@sha256:${dig}\r\n`], [0.1, 'x', '0'],
  ].map((x) => JSON.stringify(x)).join('\n');
  const [hdr, ...ev] = sanitize(cast, [['/tmp/r/work', '~/p']], 'T').trim().split('\n').map((l) => JSON.parse(l));
  assert.deepEqual(Object.keys(hdr), ['version', 'term', 'idle_time_limit', 'title']);
  assert.equal(hdr.term.rows, 5);
  assert.equal(ev[0][0], 0.3);
  assert.equal(ev[0][2], 'built in ~/p/build (0.1s)\r\n');
  assert.equal(ev[2][2], `@sha256:${'a'.repeat(12)}\r\n`);
  assert.equal(ev.length, 4);
});
