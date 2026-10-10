// Every `.. command::` / `.. variable::` the module sources document must exist as an id in the built reference
// pages, and no id may repeat. Every <Terminal> cast a built page embeds must exist under dist, and as many must be
// embedded as the pages cite. Every `{#id}` heading of a source page must be an id in its built page. Every source page
// is in the sidebar and every sidebar entry has a page.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { GROUPS } from '../sidebar.mjs';
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
// Each command has a page of its own, `reference/commands/<name>/`; its title is the page's h1, so the page itself is the anchor.
const commands = all.filter((e) => e.kind === 'command').map((e) => e.name);
for (const n of commands) if (!existsSync(new URL(`../dist/reference/commands/${n}/index.html`, import.meta.url))) (bad++, console.error(`commands: no page for ${n} in dist`));
console.log(`commands: ${commands.length} pages in the sources, ${commands.filter((n) => existsSync(new URL(`../dist/reference/commands/${n}/index.html`, import.meta.url))).length} in dist`);
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

// Source pages (site/pages): link, `{#id}` headings and cast directives.
const PAGES = new URL('../pages/', import.meta.url);
const sources = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? sources(new URL(`${d.name}/`, dir)) : d.name.endsWith('.md') ? [new URL(d.name, dir)] : []));
const linkOf = (file) => `/${file.pathname.slice(PAGES.pathname.length).replace(/\.md$/, '').replace(/(^|\/)index$/, '')}/`.replace(/^\/\/$/, '/');
const linked = new Set(GROUPS.flatMap((g) => g.items.map(([, link]) => link)));
let cites = 0;
const pages = sources(PAGES);
for (const file of pages) {
  const link = linkOf(file);
  const text = readFileSync(file, 'utf8');
  // The per-command pages are reached from the commands page, not the sidebar: each sidebar entry is a link in every page's DOM.
  if (!linked.has(link) && !link.startsWith('/reference/commands/')) (bad++, console.error(`sidebar: ${link} (${file.pathname.slice(PAGES.pathname.length)}) is in no sidebar group`));
  cites += [...text.matchAll(/^<!-- cast: /gm)].length;
  const built = new URL(`${link.slice(1)}index.html`, dist);
  if (!existsSync(built)) continue; // a missing built page is the sidebar check's job
  const have = new Set([...readFileSync(built, 'utf8').matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
  for (const m of text.matchAll(/^#{2,6} .*\{#([\w.:-]+)\}\s*$/gm)) if (!have.has(m[1])) (bad++, console.error(`${link}: heading anchor #${m[1]} is not an id in the built page`));
}
for (const link of linked) if (!pages.some((f) => linkOf(f) === link)) (bad++, console.error(`sidebar: ${link} has no page in site/pages`));
if (cites !== casts) (bad++, console.error(`casts: pages cite ${cites}, the built pages embed ${casts}`));
console.log(`pages: ${pages.length} in site/pages, ${linked.size} in the sidebar`);
process.exit(bad ? 1 : 0);
