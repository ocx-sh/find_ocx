// Builds the Starlight pages (site/src/content/docs, gitignored) from site/pages and the modules' rst blocks.
// Directives stand alone on a line; one that cannot resolve (file, region, cast script) fails the run:
//   <!-- snippet: <repo-path>[#<region>] [title="..."] -->  fenced code from a repo file or its marked region
//   <!-- cast: <key> -->  <Terminal> for site/casts/<key, / as __>.sh; the page becomes .mdx
//   <!-- cmake: commands|variables|findocx -->  reference body, converted from the modules' rst blocks
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join, posix, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { entries, rstBlocks, slug, toMarkdown } from './rst.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const BASE = '/integrations/cmake/';
const SOURCE = 'https://github.com/ocx-sh/find_ocx/blob/main/';
const URLS = { command: `${BASE}reference/commands/`, variable: `${BASE}reference/variables/` };
// Result variables written `OCX_<NAME>_RUN` in the prose are documented as part of ocx_project.
const ALIASES = { 'OCX_<NAME>_RUN': `${URLS.command}#ocx_project` };

// Generated pages edit their source, not the page stub.
const EDIT_URLS = {
  'reference/commands.md': `${SOURCE}ocx.cmake`,
  'reference/variables.md': `${SOURCE}ocx.cmake`,
  'reference/findocx.md': `${SOURCE}Findocx.cmake`,
};
/** Pages whose body is generated from the modules: the docs gate ratchets these instead of failing on them. */
export const GENERATED = Object.keys(EDIT_URLS);

const LANGS = { '.cmake': 'cmake', '.toml': 'toml', '.lock': 'toml', '.yml': 'yaml', '.yaml': 'yaml', '.sh': 'bash', '.json': 'json', '.py': 'python', '.md': 'markdown', '.mjs': 'js', '.js': 'js', '.txt': 'text' };
const langOf = (path) => (basename(path) === 'CMakeLists.txt' ? 'cmake' : (LANGS[extname(path)] ?? 'text'));

export function load(root = ROOT) {
  const rd = (rel) => readFileSync(join(root, rel), 'utf8');
  const modules = ['ocx.cmake', 'Findocx.cmake'].map((f) => ({ file: f, blocks: rstBlocks(rd(f)) }));
  const all = modules.flatMap((m) => m.blocks.flatMap((b) => entries(b)));
  return {
    rd,
    exists: (rel) => existsSync(join(root, rel)),
    modules,
    commands: all.filter((e) => e.kind === 'command'),
    variables: all.filter((e) => e.kind === 'variable'),
  };
}

const attrs = (s) => Object.fromEntries([...s.matchAll(/(\w+)=(?:"([^"]*)"|(\S+))/g)].map((m) => [m[1], m[2] ?? m[3]]));

const REGION = (name) => new RegExp(`^\\s*(?:#|//|;)\\s*region\\s+${name}\\s*$`);
const ANY_MARKER = /^\s*(?:#|\/\/|;)\s*(?:end)?region(?:\s+\S+)?\s*$/;
const END = /^\s*(?:#|\/\/|;)\s*endregion(?:\s+\S+)?\s*$/;

/** The lines of `text` between `region <name>` and the next `endregion` (all marker lines dropped, common indent removed); the whole file when `region` is empty. */
export function snippetLines(text, region, path = 'file') {
  let lines = text.replace(/\n$/, '').split('\n');
  if (region) {
    const start = lines.findIndex((l) => REGION(region.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).test(l));
    if (start < 0) throw new Error(`snippet ${path}: no "region ${region}" marker`);
    const stop = lines.findIndex((l, i) => i > start && END.test(l));
    if (stop < 0) throw new Error(`snippet ${path}: region ${region} has no endregion`);
    lines = lines.slice(start + 1, stop);
  }
  lines = lines.filter((l) => !ANY_MARKER.test(l));
  while (lines.length && !lines[0].trim()) lines.shift();
  while (lines.length && !lines.at(-1).trim()) lines.pop();
  if (!lines.length) throw new Error(`snippet ${path}${region ? `#${region}` : ''}: empty`);
  const min = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length));
  return lines.map((l) => l.slice(min));
}

const fenced = (lang, title, lines) => {
  const ticks = '`'.repeat(Math.max(3, ...lines.flatMap((l) => [...l.matchAll(/`+/g)].map((m) => m[0].length + 1))));
  return [`${ticks}${lang}${title ? ` title="${title}"` : ''}`, ...lines, ticks].join('\n');
};

/** The JSX attribute for a string: plain when safe, an expression otherwise. */
const jsxAttr = (name, value) => (/^[\w .,:;!?()'/+-]*$/.test(value) ? `${name}="${value}"` : `${name}={${JSON.stringify(value)}}`);

export const castScript = (key) => `site/casts/${key.replaceAll('/', '__')}.sh`;

/** Header value of a cast script (`# title: ...`), read before the first non-comment line. */
function castMeta(text) {
  const meta = {};
  for (const l of text.split('\n').slice(1)) {
    const m = l.match(/^# (\w+): (.*)$/);
    if (m) meta[m[1]] = m[2];
    else if (!l.startsWith('#')) break;
  }
  return meta;
}

export function expander(src) {
  const ctx = {
    commands: new Set(src.commands.map((c) => c.name)),
    variables: new Set(src.variables.map((v) => v.name)),
    urls: URLS,
    aliases: ALIASES,
    lang: 'cmake',
  };
  const md = (lines, extra) => toMarkdown(lines.join('\n'), { ...ctx, ...extra });
  const casts = new Set();

  const handlers = {
    snippet(arg) {
      const m = arg.match(/^(\S+?)(?:#(\S+))?(?:\s+(.*))?$/);
      const [, path, region, rest = ''] = m;
      if (!src.exists(path)) throw new Error(`snippet: ${path} does not exist`);
      const title = attrs(rest).title ?? (extname(path) === '.sh' ? '' : basename(path)); // a script name is no title for shell commands
      return fenced(langOf(path), title, snippetLines(src.rd(path), region, path));
    },
    cast(key) {
      const script = castScript(key);
      if (!src.exists(script)) throw new Error(`cast: no script ${script} for key "${key}"`);
      const meta = castMeta(src.rd(script));
      if (meta.cast !== 'true') throw new Error(`cast: ${script} lacks "# cast: true"`);
      if (meta.doc !== key) throw new Error(`cast: ${script} declares "# doc: ${meta.doc}", the page cites "${key}"`);
      if (!meta.title) throw new Error(`cast: ${script} lacks "# title:"`);
      casts.add(key);
      return `<Terminal src="/casts/${key}.cast" ${jsxAttr('title', meta.title)} />`;
    },
    cmake(arg) {
      // Drop the `Title` + `-----` heading lines a module block opens with.
      const body = (lines) => (/^[-=]{3,}$/.test(lines[1] ?? '') ? lines.slice(2) : lines);
      // Explicit ids (DOC-NAV-07): pages link to these headings by name.
      const head = (name) => `## ${name} {#${slug(name)}}`;
      if (arg === 'commands') {
        // The module overview (first block) and every command render with one target map, so the synopsis may reference any command.
        const parts = [{ lines: body(entries(src.modules[0].blocks[0])[0].lines), extra: { depth: 1 } }, ...src.commands.map((c) => ({ lines: c.lines, extra: { scope: c.name }, name: c.name }))];
        const targets = new Map(src.commands.map((c) => [c.name.toLowerCase(), slug(c.name)]));
        const run = (p, extra) => md(p.lines, { ...p.extra, targets, ...extra });
        for (const p of parts) run(p, { collect: true });
        return parts.map((p) => (p.name ? `${head(p.name)}\n\n${run(p)}` : run(p))).join('\n\n');
      }
      if (arg === 'variables') {
        // The blocks with `.. variable::` entries: opening text, the variables, then the closing text (each with its own headings).
        const blocks = src.modules[0].blocks.filter((b) => /^\.\. variable:: /m.test(b));
        return blocks
          .flatMap((b) => entries(b))
          .map((e, i) => (e.kind === 'variable' ? `${head(e.name)}\n\n${md(e.lines, { scope: e.name })}` : md(i === 0 ? body(e.lines) : e.lines, { depth: 1 })))
          .join('\n\n');
      }
      if (arg === 'findocx') return entries(src.modules[1].blocks[0]).map((e) => md(body(e.lines), { depth: 1 })).join('\n\n');
      throw new Error(`cmake: unknown part ${arg}`);
    },
  };

  /** Expands every directive line; `mdx` is true when the page now needs MDX (a <Terminal>). */
  const expand = (text, file) => {
    casts.clear();
    const out = text.replace(/^<!-- (snippet|cast|cmake): (.*?) -->$/gm, (_m, kind, arg) => {
      try {
        return handlers[kind](arg);
      } catch (e) {
        throw new Error(`${file}: ${e.message}`);
      }
    });
    return { text: out, mdx: casts.size > 0, casts: [...casts] };
  };
  return { expand, ctx };
}

/** Applies `fn` to every line outside fenced code. */
function outsideFences(text, fn) {
  let open = '';
  return text
    .split('\n')
    .map((line) => {
      const m = line.match(/^\s*(`{3,}|~{3,})/);
      if (open) {
        if (m && m[1][0] === open[0] && m[1].length >= open.length && line.trim() === m[1]) open = '';
        return line;
      }
      if (m) {
        open = m[1];
        return line;
      }
      return fn(line);
    })
    .join('\n');
}

// Source pages: YAML front matter (title, description) followed by the declaration comments, or the older form
// (declaration comments, `<!-- description: ... -->`, `# Title`). Starlight renders the title itself, so the H1 moves
// into the front matter.
const siteUrl = (rel, target) => {
  const path = posix.normalize(posix.join(posix.dirname(rel), target)).replace(/\.md$/, '').replace(/(^|\/)index$/, '');
  return path === '' ? BASE : `${BASE}${path}/`;
};
const rewriteLinks = (rel, text) => text.replace(/\]\((?![a-z]+:)([^)#]+\.md)(#[^)]*)?\)/g, (_m, target, hash = '') => `](${siteUrl(rel, target)}${hash})`);

/** Starlight renders the title itself: a first heading that repeats it (after the declaration comments) goes. */
function dropTitleH1(body, title) {
  const lines = body.split('\n');
  const at = lines.findIndex((l) => l.trim() && !/^(?:<!--.*-->|\{\/\*.*\*\/\})$/.test(l.trim()));
  if (at < 0 || lines[at].trim() !== `# ${title}`) return body;
  lines.splice(at, lines[at + 1] === '' ? 2 : 1);
  return lines.join('\n');
}

export function frontMatter(text, rel) {
  const editUrl = EDIT_URLS[rel] ?? `${SOURCE}site/pages/${rel}`;
  if (text.startsWith('---\n')) {
    const end = text.indexOf('\n---\n', 3);
    if (end < 0) throw new Error(`${rel}: front matter is not closed`);
    const head = text.slice(4, end);
    for (const key of ['title', 'description']) if (!new RegExp(`^${key}:\\s*\\S`, 'm').test(head)) throw new Error(`${rel}: front matter needs ${key}`);
    const title = head.match(/^title:\s*(.+?)\s*$/m)[1].replace(/^(["'])(.*)\1$/, '$2');
    return `---\n${head}\neditUrl: ${editUrl}\n---\n${dropTitleH1(text.slice(end + 5).replace(/^\n+/, ''), title)}`;
  }
  const h1 = text.match(/^# (.+)\n+/m);
  const description = text.match(/^<!-- description: (.+) -->$/m)?.[1];
  if (!h1 || !description) throw new Error(`${rel}: needs front matter with title and description`);
  const meta = ['title', 'description', 'editUrl'].map((k, i) => `${k}: ${i === 2 ? editUrl : JSON.stringify([h1[1], description][i])}`);
  const body = text.replace(/^<!-- (description): .+ -->\n/gm, '').replace(h1[0], '');
  const decl = body.match(/^(<!-- doc_(?:type|tier): .+ -->\n)+/m)?.[0] ?? '';
  return `---\n${meta.join('\n')}\n---\n${decl}\n${body.replace(decl, '').trimStart()}`;
}

const IMPORT_TERMINAL = "import Terminal from '@ocx-sh/theme/components/Terminal.astro';";

// MDX rejects HTML comments: standalone ones become JSX comments, then the Terminal import follows the declaration block.
export function toMdx(text) {
  const out = outsideFences(text, (l) => l.replace(/^(\s*)<!--\s*(.*?)\s*-->\s*$/, '$1{/* $2 */}'));
  const lines = out.split('\n');
  const fmEnd = lines.indexOf('---', 1) + 1;
  let at = fmEnd;
  while (at < lines.length && /^\{\/\* doc_(type|tier):/.test(lines[at])) at++;
  lines.splice(at, 0, '', IMPORT_TERMINAL);
  return lines.join('\n');
}

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? walk(join(dir, d.name)) : [join(dir, d.name)]));
}

/** Source page text to { dest, text }; the one place a page is built. */
export function buildPage(expand, rel, raw) {
  const { text: expanded, mdx, casts } = expand(raw, rel);
  const left = expanded.match(/^<!-- (?:snippet|cast|cmake|port): .*$|^--8<--.*$/m);
  if (left) throw new Error(`${rel}: unexpanded or retired directive: ${left[0]}`);
  const page = rewriteLinks(rel, frontMatter(expanded, rel));
  return { dest: mdx ? rel.replace(/\.md$/, '.mdx') : rel, text: mdx ? toMdx(page) : page, casts };
}

/** Cast scripts (`{ file, doc }`) that no page cites. A recorded cast nobody embeds is dead weight at build time. */
export const uncitedCasts = (built, scripts) => {
  const cited = new Set(built.flatMap((b) => b.casts));
  return scripts.filter((s) => s.doc && !cited.has(s.doc));
};

// `--check-dir DIR` writes the expanded pages for the docs gate instead of the site: same text, minus the MDX Terminal
// import (the prose checks would read it as a sentence).
function main() {
  const checkDir = process.argv[2] === '--check-dir' ? process.argv[3] : '';
  const src = load();
  const { expand } = expander(src);
  const pagesDir = join(ROOT, 'site/pages');
  const out = checkDir ? join(process.cwd(), checkDir) : join(ROOT, 'site/src/content/docs');
  rmSync(out, { recursive: true, force: true });
  const built = [];
  for (const file of walk(pagesDir).filter((f) => f.endsWith('.md'))) {
    const rel = relative(pagesDir, file);
    built.push(buildPage(expand, rel, readFileSync(file, 'utf8')));
  }
  for (const { dest, text } of built) {
    mkdirSync(dirname(join(out, dest)), { recursive: true });
    writeFileSync(join(out, dest), checkDir ? text.replace(`\n${IMPORT_TERMINAL}\n`, '').replace(/\n{3,}/g, '\n\n') : text);
  }
  const scriptsDir = join(ROOT, 'site/casts');
  const scripts = (existsSync(scriptsDir) ? readdirSync(scriptsDir).filter((n) => n.endsWith('.sh')) : []).map((file) => ({
    file,
    doc: readFileSync(join(scriptsDir, file), 'utf8').match(/^# doc: (.+)$/m)?.[1],
  }));
  const dead = uncitedCasts(built, scripts);
  if (dead.length) throw new Error(`port-docs: cast script cited by no page: ${dead.map((d) => `${d.doc} (site/casts/${d.file})`).join(', ')}`);
  console.log(`ported ${built.length} pages (${src.commands.length} commands, ${src.variables.length} variables, ${built.flatMap((b) => b.casts).length} casts)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
