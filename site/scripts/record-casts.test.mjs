import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { driver, leaks, parseScript, sanitize, scriptName } from './record-casts.mjs';

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
  assert.equal(scriptName('a/b'), 'a__b.sh');
});

test('driver types every block and runs the text around the region silently, into the log', () => {
  const d = driver(parseScript(script));
  assert.equal([...d.matchAll(/^__block <<'/gm)].length, 2);
  assert.match(d, /\{\n[\s\S]*set -e\n\n\} >>"\$CAST_TMP\/silent.log" 2>&1\n__block/);
  assert.match(d, /\{\ntest 1\n\n\} >>"\$CAST_TMP\/silent.log" 2>&1\n$/);
});

test('sanitize merges bursts, rewrites paths, shortens digests and timings, keeps typing events', () => {
  const dig = 'a'.repeat(64);
  const cast = [
    { version: 3, term: { cols: 100, rows: 40 }, timestamp: 1, command: '/home/u/x', env: { SHELL: '/bin/zsh' } },
    [2, 'o', 'built in /tmp/r/wor'], [0.001, 'o', 'k/build (0.0123s)\r\n'],
    [0.04, 'o', 'x'], [0.04, 'o', `@sha256:${dig}\r\n`], [9, 'o', 'slow\r\n'], [0.1, 'x', '0'],
  ].map((x) => JSON.stringify(x)).join('\n');
  const [hdr, ...ev] = sanitize(cast, [['/tmp/r/work', '~/p']], 'T').trim().split('\n').map((l) => JSON.parse(l));
  assert.deepEqual(Object.keys(hdr), ['version', 'term', 'idle_time_limit', 'title']);
  assert.equal(hdr.term.rows, 5);
  assert.equal(ev[0][0], 0.3);
  assert.equal(ev[0][2], 'built in ~/p/build (0.1s)\r\n');
  assert.equal(ev[2][2], `@sha256:${'a'.repeat(12)}\r\n`);
  assert.equal(ev[3][0], 2); // a nine second wait is capped at the idle limit
  assert.equal(ev.length, 5);
});

test('sanitize normalizes store paths, temp names, loopback ports and the cmake module path', () => {
  const hex = '0123456789abcdef0123456789abcdef';
  const out = sanitize([
    { version: 3, term: { cols: 100, rows: 40 } },
    [1, 'o', `packages/ocx.sh/sha256/91/${hex.slice(0, 30)}/content temp/${hex} http://127.0.0.1:41234/dist.json /opt/x/share/cmake-3.31/Modules/FindFoo.cmake`],
  ].map((x) => JSON.stringify(x)).join('\n'), [], 'T');
  const [, [, , data]] = out.trim().split('\n').map((l) => JSON.parse(l));
  assert.equal(data, 'packages/ocx.sh/sha256/91/0123456789/content temp/0123456789ab http://127.0.0.1:8080/dist.json /usr/share/cmake-3.31/Modules/FindFoo.cmake');
});

test('leaks reports the recording machine home and scratch directory', () => {
  assert.deepEqual(leaks('all clean ~/x', '/tmp/cast-1'), []);
  assert.deepEqual(leaks(`see ${homedir()}/x and /tmp/cast-1/run`, '/tmp/cast-1'), [homedir(), '/tmp/cast-1']);
});

// Every cast script is a ctest keyed by its "# doc:" line (tests/casts.cmake); the file name, the key and the headers must agree.
test('every cast script declares a doc key that matches its file name', () => {
  const dir = fileURLToPath(new URL('../casts/', import.meta.url));
  const files = readdirSync(dir).filter((f) => f.endsWith('.sh'));
  assert.ok(files.length > 0);
  for (const f of files) {
    const s = parseScript(readFileSync(dir + f, 'utf8'));
    assert.equal(s.meta.cast, 'true', f);
    assert.equal(scriptName(s.meta.doc), f);
    assert.ok(s.meta.title && s.meta.description && s.cast, f);
  }
});
