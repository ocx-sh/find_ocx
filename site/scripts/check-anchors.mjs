// Every `.. command::` / `.. variable::` the module sources document must exist as an id in the built reference
// pages, and no id may repeat. Every <Terminal> cast a built page embeds must exist under dist.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
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

const BASE = '/integrations/cmake/';
const dist = new URL('../dist/', import.meta.url);
const html = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? html(new URL(`${d.name}/`, dir)) : d.name.endsWith('.html') ? [new URL(d.name, dir)] : []));
let casts = 0;
for (const page of html(dist)) {
  for (const m of readFileSync(page, 'utf8').matchAll(/data-src="([^"]+)"/g)) {
    casts++;
    if (!m[1].startsWith(BASE) || !existsSync(new URL(m[1].slice(BASE.length), dist))) (bad++, console.error(`${page.pathname}: cast ${m[1]} is not in dist`));
  }
}
console.log(`casts: ${casts} embedded`);
process.exit(bad ? 1 : 0);
