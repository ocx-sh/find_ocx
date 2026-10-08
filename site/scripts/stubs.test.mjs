import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { STUBS, writeStubs } from './stubs.mjs';

test('each old Sphinx page gets a stub that forwards to a page the site builds', () => {
  const dir = mkdtempSync(join(tmpdir(), 'stubs-'));
  writeStubs(dir);
  for (const [file, url] of Object.entries(STUBS)) {
    const html = readFileSync(join(dir, file), 'utf8');
    assert.match(html, new RegExp(`http-equiv="refresh" content="0; url=${url}"`));
    assert.ok(url.startsWith('https://ocx.sh/integrations/cmake/'));
  }
  assert.deepEqual(Object.keys(STUBS), ['index.html', 'examples.html', 'reference.html']);
});
