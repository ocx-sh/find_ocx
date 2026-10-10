import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { STUBS, writeStubs } from './stubs.mjs';

test('each old Sphinx page gets a stub that forwards to a page the site builds', () => {
  const dir = mkdtempSync(join(tmpdir(), 'stubs-'));
  writeStubs(dir);
  for (const [file, url] of Object.entries(STUBS)) {
    const html = readFileSync(join(dir, file), 'utf8');
    assert.match(html, new RegExp(`http-equiv="refresh" content="0; url=${url}"`));
    assert.ok(url.startsWith('https://ocx.sh/integrations/cmake/'));
    // The target must be a source page the site builds (the reference pages are real files under site/pages too).
    const path = url.slice('https://ocx.sh/integrations/cmake/'.length).replace(/\/$/, '') || 'index';
    const pages = fileURLToPath(new URL('../pages/', import.meta.url));
    assert.ok([`${path}.md`, `${path}/index.md`].some((p) => existsSync(join(pages, p))), `${url} has no page under site/pages`);
  }
  assert.deepEqual(Object.keys(STUBS), ['index.html', 'examples.html', 'reference.html']);
});
