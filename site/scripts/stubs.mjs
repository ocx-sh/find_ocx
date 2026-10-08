// Plan for the Pages flip (D6), NOT wired into any workflow yet. The last GitHub Pages build writes one
// meta-refresh stub per old Sphinx page, then pages.yml is removed:
//
//   1. in pages.yml, after `task docs`:  node site/scripts/stubs.mjs docs/_build/html
//   2. let that build publish, verify the three old URLs forward,
//   3. delete pages.yml, docs/conf.py, docs/pyproject.toml, docs/uv.lock.
//
// Old URLs get no Bunny redirect rule. The Sphinx `objects.inv` is dropped on purpose.
import { mkdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const NEW = 'https://ocx.sh/integrations/cmake/';
export const STUBS = {
  'index.html': NEW,
  'examples.html': `${NEW}reference/examples/`,
  'reference.html': `${NEW}reference/commands/`,
};

export const stub = (url) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>find_ocx has moved</title>
<link rel="canonical" href="${url}">
<meta http-equiv="refresh" content="0; url=${url}">
<meta name="robots" content="noindex">
</head>
<body>
<p>find_ocx has moved to <a href="${url}">${url}</a>.</p>
</body>
</html>
`;

export function writeStubs(dir) {
  mkdirSync(dir, { recursive: true });
  for (const [file, url] of Object.entries(STUBS)) writeFileSync(new URL(file, pathToFileURL(`${dir}/`)), stub(url));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const dir = process.argv[2];
  if (!dir) (console.error('usage: node stubs.mjs <dir>'), process.exit(2));
  writeStubs(dir);
  console.log(`wrote ${Object.keys(STUBS).length} stubs to ${dir}`);
}
