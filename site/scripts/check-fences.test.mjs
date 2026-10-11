import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fenceFindings } from './check-fences.mjs';

const pre = (lang) => `<pre${lang === null ? '' : ` data-language="${lang}"`}><code>x</code></pre>`;

test('highlighted languages and the run/norun tiers pass', () => {
  for (const l of ['cmake', 'bash', 'log', 'cmake-norun', 'bash-run']) assert.deepEqual(fenceFindings(pre(l)), [], l);
});

test('missing, plain-text and unknown languages are findings', () => {
  for (const l of [null, '', 'text', 'txt', 'plaintext', 'console-norun']) assert.equal(fenceFindings(pre(l)).length, 1, String(l));
});

test('an allowlisted page may carry plain blocks', () => {
  assert.deepEqual(fenceFindings(pre('text'), 'a/index.html', { 'a/index.html': 'raw tool output' }), []);
});
