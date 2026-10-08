// Builds the Starlight pages from committed sources, never editing them:
//   site/pages/**/*.md      hand-written pages; `--8<-- "path" from=RE to=RE`, `<!-- port: ... -->` and `<!-- cmake: ... -->` pull in the real sources
//   docs/*.rst              the Sphinx pages (read, converted, kept until the Pages flip)
//   ocx.cmake, Findocx.cmake  the `.. command::` / `.. variable::` blocks
//   examples/**             the tested example projects, included verbatim
// Output goes to site/src/content/docs (gitignored). Unknown rst roles/directives, a missing include, an
// rst section no page uses, or a variable the docs never mention all fail the run.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { entries, rstBlocks, sections, toMarkdown } from './rst.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const BASE = '/integrations/cmake/';
const SOURCE = 'https://github.com/ocx-sh/find_ocx/blob/main/';
const URLS = { command: `${BASE}reference/commands/`, variable: `${BASE}reference/variables/` };
// Result variables written `OCX_<NAME>_RUN` in the prose are documented as part of ocx_project.
const ALIASES = { 'OCX_<NAME>_RUN': `${URLS.command}#ocx_project` };

// rst sections that no page ports: the page that restates them in its own words. The port still checks that every
// OCX_* name the section mentions appears on those pages.
const COVERED_BY = {
  'index.rst': {
    'Quick start': ['tutorial.md', 'guides/workspace-tools.md'],
    'Corporate mirrors': ['guides/mirror.md', 'guides/nested-builds.md'],
  },
  'examples.rst': {},
};

// Generated pages edit their source, not the page stub.
const EDIT_URLS = {
  'reference/commands.md': `${SOURCE}ocx.cmake`,
  'reference/variables.md': `${SOURCE}ocx.cmake`,
  'reference/findocx.md': `${SOURCE}Findocx.cmake`,
  'reference/examples.md': `${SOURCE.replace('/blob/', '/tree/')}examples`,
  'reference/examples-packages.md': `${SOURCE.replace('/blob/', '/tree/')}examples`,
  'reference/examples-discovery.md': `${SOURCE.replace('/blob/', '/tree/')}examples`,
};


export function load(root = ROOT) {
  const rd = (rel) => readFileSync(join(root, rel), 'utf8');
  const modules = ['ocx.cmake', 'Findocx.cmake'].map((f) => ({ file: f, blocks: rstBlocks(rd(f)) }));
  const all = modules.flatMap((m) => m.blocks.flatMap((b) => entries(b)));
  return {
    rd,
    modules,
    commands: all.filter((e) => e.kind === 'command'),
    variables: all.filter((e) => e.kind === 'variable'),
    docs: { 'index.rst': sections(rd('docs/index.rst')), 'examples.rst': sections(rd('docs/examples.rst')) },
  };
}

const attrs = (s) => Object.fromEntries([...s.matchAll(/(\w+)=(?:"([^"]*)"|(\S+))/g)].map((m) => [m[1], m[2] ?? m[3]]));

export function expander(src) {
  const used = new Set();
  const ctx = {
    commands: new Set(src.commands.map((c) => c.name)),
    variables: new Set(src.variables.map((v) => v.name)),
    urls: URLS,
    aliases: ALIASES,
    lang: 'cmake',
    // literalinclude paths are relative to docs/
    readFile: (p) => src.rd(join('docs', p)),
  };
  const md = (lines) => toMarkdown(lines.join('\n'), ctx);

  const handlers = {
    port(arg) {
      const m = arg.match(/^(\S+) "(.+)"$/);
      if (!m) throw new Error(`port: expected  <file.rst> "Section", got: ${arg}`);
      const sec = src.docs[m[1]]?.sections.find((s) => s.title === m[2] || s.title.startsWith(m[2]));
      if (!sec) throw new Error(`port: no section "${m[2]}" in ${m[1]}`);
      used.add(`${m[1]}#${sec.title}`);
      return md(sec.lines);
    },
    include(arg) {
      const [path, ...rest] = arg.split(/\s+/);
      const a = attrs(rest.join(' '));
      let lines = src.rd(path).split('\n');
      while (lines.at(-1) === '') lines.pop();
      if (a.from) {
        const at = lines.findIndex((l) => new RegExp(a.from).test(l));
        if (at < 0) throw new Error(`include ${path}: from=${a.from} not found`);
        lines = lines.slice(at);
      }
      if (a.to) {
        const at = lines.findIndex((l) => new RegExp(a.to).test(l));
        if (at < 0) throw new Error(`include ${path}: to=${a.to} not found`);
        lines = lines.slice(0, at + 1);
      }
      const min = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length));
      const lang = a.lang ?? (path.endsWith('.toml') ? 'toml' : path.endsWith('.yml') ? 'yaml' : 'cmake');
      return ['```' + lang + ` title="${a.title ?? path}"`, ...lines.map((l) => l.slice(min)), '```'].join('\n');
    },
    cmake(arg) {
      if (arg === 'commands') {
        return src.commands.map((c) => `## ${c.name}\n\n${md(c.lines)}`).join('\n\n');
      }
      if (arg === 'variables') {
        // First block of ocx.cmake: overview text, the 14 variables, then the passthrough/credentials text.
        return entries(src.modules[0].blocks[0])
          .map((e, i) => (e.kind === 'variable' ? `## ${e.name}\n\n${md(e.lines)}` : i === 0 ? md(e.lines.slice(2)) : `## Passthrough and credentials\n\n${md(e.lines)}`))
          .join('\n\n');
      }
      if (arg === 'findocx') return entries(src.modules[1].blocks[0]).map((e) => md(e.lines.slice(2))).join('\n\n');
      throw new Error(`cmake: unknown part ${arg}`);
    },
  };

  const expand = (text, file) =>
    text.replace(/^(?:<!-- (port|cmake): (.*) -->|--8<-- "([^"]+)"(.*))$/gm, (_m, kind, arg, path, rest) => {
      try {
        return kind ? handlers[kind](arg) : handlers.include(`${path}${rest}`);
      } catch (e) {
        throw new Error(`${file}: ${e.message}`);
      }
    });
  return { expand, used, ctx };
}

/** Throws when an rst section is neither ported nor covered, or a covering page forgets an OCX_* name. */
export function checkCoverage(src, used, pages) {
  const problems = [];
  for (const [file, doc] of Object.entries(src.docs)) {
    for (const sec of doc.sections) {
      const key = `${file}#${sec.title}`;
      const cover = COVERED_BY[file]?.[sec.title];
      if (used.has(key)) continue;
      if (!cover) {
        problems.push(`${key}: no page ports it and COVERED_BY does not list it`);
        continue;
      }
      const text = cover.map((p) => pages[p] ?? (problems.push(`${key}: covering page ${p} missing`), '')).join('\n');
      for (const tok of new Set(sec.lines.join('\n').match(/OCX_[A-Z]+(?:_[A-Z]+)*/g) ?? [])) {
        if (!text.includes(tok)) problems.push(`${key}: ${tok} is not mentioned on ${cover.join(' or ')}`);
      }
    }
  }
  const varsDocumented = src.variables.map((v) => v.name);
  if (varsDocumented.length !== new Set(varsDocumented).size) problems.push('a .. variable:: block appears twice');
  return problems;
}

// Source pages: declaration comments, `<!-- description: ... -->`, then `# Title`.
// Starlight renders the title itself, so the H1 moves into the front matter.
const siteUrl = (rel, target) => {
  const path = posix.normalize(posix.join(posix.dirname(rel), target)).replace(/\.md$/, '');
  return path === 'index' ? BASE : `${BASE}${path}/`;
};
const rewriteLinks = (rel, text) => text.replace(/\]\((?![a-z]+:)([^)#]+\.md)(#[^)]*)?\)/g, (_m, target, hash = '') => `](${siteUrl(rel, target)}${hash})`);

export function frontMatter(text, rel) {
  const h1 = text.match(/^# (.+)\n+/m);
  const description = text.match(/^<!-- description: (.+) -->$/m)?.[1];
  if (!h1 || !description) throw new Error(`${rel}: needs a "# Title" and a "<!-- description: ... -->" line`);
  const editUrl = EDIT_URLS[rel] ?? `${SOURCE}site/pages/${rel}`;
  const meta = ['title', 'description', 'editUrl'].map((k, i) => `${k}: ${i === 2 ? editUrl : JSON.stringify([h1[1], description][i])}`);
  const body = text.replace(/^<!-- (description): .+ -->\n/gm, '').replace(h1[0], '');
  const decl = body.match(/^(<!-- doc_(?:type|tier): .+ -->\n)+/m)?.[0] ?? '';
  return `---\n${meta.join('\n')}\n---\n${decl}\n${body.replace(decl, '').trimStart()}`;
}

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? walk(join(dir, d.name)) : [join(dir, d.name)]));
}

function main() {
  const src = load();
  const { expand, used } = expander(src);
  const pagesDir = join(ROOT, 'site/pages');
  const out = join(ROOT, 'site/src/content/docs');
  rmSync(out, { recursive: true, force: true });
  const built = {};
  const raw = {};
  for (const file of walk(pagesDir).filter((f) => f.endsWith('.md'))) {
    const rel = relative(pagesDir, file);
    raw[rel] = readFileSync(file, 'utf8');
    let text = expand(raw[rel], rel);
    if (/^(<!-- (port|cmake):|--8<--)/m.test(text)) throw new Error(`${rel}: unexpanded directive`);
    built[rel] = rewriteLinks(rel, frontMatter(text, rel));
  }
  const problems = checkCoverage(src, used, raw);
  if (problems.length) {
    console.error(problems.join('\n'));
    process.exit(1);
  }
  for (const [rel, text] of Object.entries(built)) {
    const dest = join(out, rel);
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, text);
  }
  console.log(`ported ${Object.keys(built).length} pages (${src.commands.length} commands, ${src.variables.length} variables)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
