// The GitHub Pages site (ocx-sh.github.io/find_ocx/) is now only these meta-refresh stubs, one per old Sphinx page,
// built by .github/workflows/pages.yml: `node site/scripts/stubs.mjs <dir>`. The docs live at
// https://ocx.sh/integrations/cmake/. Old URLs get no Bunny redirect rule; the Sphinx `objects.inv` is dropped on purpose.
import { mkdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const NEW = 'https://ocx.sh/integrations/cmake/';
export const STUBS = {
  'index.html': NEW,
  'examples.html': NEW, // reference/examples was deleted; the landing page links the worked examples
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
