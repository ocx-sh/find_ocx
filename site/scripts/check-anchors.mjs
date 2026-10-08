// Every `.. command::` / `.. variable::` the module sources document must exist as an id in the built reference
// pages, and no id may repeat.
import { readFileSync } from 'node:fs';
import { entries, rstBlocks, slug } from './rst.mjs';

const ROOT = new URL('../../', import.meta.url);
const names = (file) => rstBlocks(readFileSync(new URL(file, ROOT), 'utf8')).flatMap((b) => entries(b)).filter((e) => e.name);
const ids = (page) => [...readFileSync(new URL(`../dist/reference/${page}/index.html`, import.meta.url), 'utf8').matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);

let bad = 0;
const check = (page, wanted) => {
  const all = ids(page);
  const built = new Set(all);
  for (const id of built) if (all.filter((i) => i === id).length > 1) (bad++, console.error(`${page}: id ${id} appears twice`));
  for (const n of wanted) if (!built.has(slug(n))) (bad++, console.error(`${page}: anchor #${slug(n)} (${n}) missing from dist`));
  console.log(`${page}: ${wanted.length} anchors in the sources, ${wanted.filter((n) => built.has(slug(n))).length} in dist`);
};
const all = names('ocx.cmake');
check('commands', all.filter((e) => e.kind === 'command').map((e) => e.name));
check('variables', all.filter((e) => e.kind === 'variable').map((e) => e.name));
process.exit(bad ? 1 : 0);
