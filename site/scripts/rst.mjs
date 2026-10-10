// Converts the reStructuredText of the `#[=[.rst:` blocks in the CMake modules to Markdown. Pure: callers pass text
// and a context, nothing is read here. Anything it does not know throws, so a new directive or role in the
// sources fails the build instead of rendering wrong.

const ind = (l) => l.match(/^ */)[0].length;
const dedent = (lines) => {
  const min = Math.min(...lines.filter((l) => l.trim()).map(ind), Infinity);
  return lines.map((l) => (l.trim() ? l.slice(min) : ''));
};
const trimBlank = (lines) => {
  let a = 0;
  let b = lines.length;
  while (a < b && !lines[a].trim()) a++;
  while (b > a && !lines[b - 1].trim()) b--;
  return lines.slice(a, b);
};
const fence = (lang, lines, title) => ['```' + lang + (title ? ` title="${title}"` : ''), ...lines, '```', ''];

/** Anchor a heading gets from github-slugger for the names used here (lowercase, `_` kept). */
export const slug = (s) => s.toLowerCase().replace(/[^\w\- ]/g, '').replace(/ /g, '-');

const CMAKE_HELP = 'https://cmake.org/cmake/help/latest/';
/** What an unknown (not module-defined) role target must look like to link to the CMake manual; `ocx_`/`OCX_` names never do. */
const EXTERNAL = {
  command: [/^(?!ocx_)[a-z][a-z0-9_]*$/, 'command'],
  variable: [/^(?:CMAKE|CTEST|CPACK)_\w+$/, 'variable'],
  policy: [/^CMP\d{4}$/, 'policy'],
};

/** The id a heading or signature target gets; unique per command through `ctx.scope`. A target named like its scope is that scope's own heading. */
const idFor = (name, ctx) => (ctx.scope && slug(name) !== slug(ctx.scope) ? `${ctx.scope}-` : '') + slug(name);
const register = (name, ctx) => {
  const id = idFor(name, ctx);
  ctx.targets?.set(name.toLowerCase(), id);
  return id;
};
const reference = (ref, ctx) => {
  const id = ctx.targets?.get(ref.toLowerCase());
  if (!id && !ctx.collect) throw new Error(`rst: reference \`${ref}\`_ names no signature target or section`);
  return id ?? '';
};

/** ctx: { commands:Set, variables:Set, urls:{command, variable}, each a page URL or a function of the name, aliases:{name: url}, lang, scope, depth } */
export function inline(text, ctx) {
  return text
    .split(/(``[^`]+``)/)
    .map((part, i) => {
      if (i % 2) return '`' + part.slice(2, -2) + '`';
      return part
        .replace(/:(command|variable|policy):`([^`]+)`/g, (_m, role, name) => {
          const alias = ctx.aliases?.[name];
          if (alias) return `[\`${name}\`](${alias})`;
          const known = { command: ctx.commands, variable: ctx.variables }[role];
          if (known?.has(name)) return `[\`${name}\`](${typeof ctx.urls[role] === 'function' ? ctx.urls[role](name) : `${ctx.urls[role]}#${slug(name)}`})`;
          const [shape, dir] = EXTERNAL[role];
          if (!shape.test(name)) throw new Error(`rst: :${role}:\`${name}\` has no .. ${role}:: block and is no CMake ${role}`);
          return `[\`${name}\`](${CMAKE_HELP}${dir}/${name}.html)`;
        })
        .replace(/:(\w+):`/g, (_m, role) => {
          throw new Error(`rst: unknown role :${role}:`);
        })
        .replace(/`([^`<]+?)\s*<([^>]+)>`_/g, (_m, label, url) => `[${label}](${url})`)
        .replace(/`([^`]+)`_/g, (_m, ref) => `[${ref}](${/\//.test(reference(ref, ctx)) ? '' : '#'}${reference(ref, ctx)})`)
        // The theme has no italics (an italic face costs a font download past the page budget): plain.
        .replace(/(?<![*\w])\*(?!\*)([^*\n]+?)\*(?![*\w])/g, '$1');
    })
    .join('');
}

const para = (lines, ctx) => inline(lines.map((l) => l.trim()).join(' '), ctx);

/** Split a table border line into [start, end) column spans. */
const spans = (border) => {
  const cols = [...border.matchAll(/=+/g)].map((m) => [m.index, m.index + m[0].length]);
  cols[cols.length - 1][1] = Infinity;
  return cols;
};

function table(lines, i, ctx) {
  const cols = spans(lines[i]);
  const cut = (l) => cols.map(([a, b]) => l.slice(a, b === Infinity ? undefined : b + 1).trim());
  const rows = [];
  let j = i + 1;
  let borders = 1;
  for (; j < lines.length && borders < 3; j++) {
    const l = lines[j];
    if (/^=+(\s+=+)+$/.test(l)) {
      borders++;
      continue;
    }
    const cells = cut(l);
    if (!cells[0] && rows.length) cells.forEach((c, k) => c && (rows.at(-1)[k] = `${rows.at(-1)[k]} ${c}`.trim()));
    else rows.push(cells);
  }
  // Adjacent literals (`a` `b`) become one code element: a long variable list would otherwise cost one DOM element each.
  const merge = (t) => (/`[^`]+` `[^`]+`/.test(t) ? merge(t.replace(/`([^`]+)` `([^`]+)`/, '`$1 $2`')) : t);
  const cell = (c) => merge(inline(c, ctx)).replace(/\|/g, '\\|');
  const md = [`| ${rows[0].map(cell).join(' | ')} |`, `| ${cols.map(() => '---').join(' | ')} |`];
  for (const r of rows.slice(1)) md.push(`| ${r.map(cell).join(' | ')} |`);
  return { md: [...md, ''], next: j };
}

/** Lines of a directive body: everything indented (or blank) after the directive line. */
function body(lines, i) {
  const out = [];
  let j = i + 1;
  for (; j < lines.length; j++) {
    if (lines[j].trim() && ind(lines[j]) === 0) break;
    out.push(lines[j]);
  }
  return { lines: trimBlank(dedent(out)), next: j };
}

const options = (lines) => {
  const opts = {};
  let k = 0;
  for (; k < lines.length && /^:[\w-]+:/.test(lines[k]); k++) {
    const m = lines[k].match(/^:([\w-]+):\s*(.*)$/);
    opts[m[1]] = m[2];
  }
  return { opts, rest: trimBlank(lines.slice(k)) };
};

/** `.. signature:: <text>` with `:target:`/`:break:` options: the first block (to a blank line) is signature and options, the rest is the description. */
function signature(arg, lines, ctx) {
  const at = lines.findIndex((l) => !l.trim());
  const head = [...(arg ? [arg] : []), ...(at < 0 ? lines : lines.slice(0, at))];
  const opts = {};
  const sig = [];
  for (const l of head) {
    const m = l.match(/^:([\w-]+):\s*(.*)$/);
    if (m) opts[m[1]] = m[2];
    else sig.push(l);
  }
  for (const k of Object.keys(opts)) if (!['target', 'break'].includes(k)) throw new Error(`rst: unknown .. signature:: option :${k}:`);
  if (opts.break && opts.break !== 'verbatim') throw new Error(`rst: .. signature:: :break: ${opts.break} (only verbatim is rendered)`);
  if (!sig.length) throw new Error('rst: .. signature:: without a signature');
  const targets = opts.target ? opts.target.split(/\s+/) : [sig[0].match(/\(([A-Z_]+)/)?.[1]];
  if (!targets[0]) throw new Error(`rst: signature without an operation or :target: ${sig[0]}`);
  const ids = targets.map((t) => register(t, ctx));
  // A single-form command names itself: the page already has its heading, so only the fence follows.
  const own = slug(targets[0]) === slug(ctx.scope ?? '');
  const heading = own ? [] : [`${'#'.repeat((ctx.depth ?? 2) + 1)} ${targets[0]} {#${ids[0]}}`, ''];
  return [...heading, ...fence('cmake', sig), ...render(at < 0 ? [] : trimBlank(lines.slice(at)), ctx)];
}

const VERSION = /^\d+(?:\.\d+)*$/;
const STARTS_BLOCK = /^(?:[-*] |\d+\. |`{3}|\||:::|#)/;

function directive(name, arg, lines, ctx) {
  const { rest } = options(lines);
  switch (name) {
    case 'code-block':
      return fence(arg || ctx.lang || 'text', rest);
    case 'parsed-literal':
      // The fence cannot carry links; every `NAME`_ must still name a target, so a renamed signature breaks the build.
      return fence(ctx.lang || 'text', rest.map((l) => l.replace(/`([^`]+)`_/g, (_m, ref) => (reference(ref, ctx), ref))));
    case 'warning':
    case 'note':
    case 'tip':
      return [`:::${name === 'warning' ? 'caution' : name}`, ...render(trimBlank(arg ? [arg, ...rest] : rest), ctx), ':::', ''];
    case 'versionadded':
    case 'versionchanged': {
      if (!VERSION.test(arg)) throw new Error(`rst: .. ${name}:: needs a version, got "${arg}"`);
      const lead = `**${name === 'versionadded' ? 'New' : 'Changed'} in version ${arg}.**`;
      const body = render(rest, ctx);
      if (!body.length) return [lead, ''];
      return STARTS_BLOCK.test(body[0]) ? [lead, '', ...body] : [`${lead} ${body[0]}`, ...body.slice(1)];
    }
    case 'signature':
      return signature(arg, lines, ctx);
    default:
      throw new Error(`rst: unknown directive .. ${name}::`);
  }
}

/** Render dedented rst lines to Markdown lines. */
export function render(lines, ctx) {
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i++;
      continue;
    }
    const d = line.match(/^\.\. ([\w-]+)::\s*(.*)$/);
    if (d) {
      const b = body(lines, i);
      out.push(...directive(d[1], d[2], b.lines, ctx));
      i = b.next;
      continue;
    }
    if (/^=+(\s+=+)+$/.test(line)) {
      const t = table(lines, i, ctx);
      out.push(...t.md);
      i = t.next;
      continue;
    }
    if (/^[*-] /.test(line) || /^\d+\. /.test(line)) {
      const ordered = /^\d+\. /.test(line);
      let n = 1;
      while (i < lines.length && (ordered ? /^\d+\. / : /^[*-] /).test(lines[i])) {
        const w = lines[i].match(/^(?:[*-]|\d+\.) /)[0].length;
        const item = [lines[i].slice(w)];
        i++;
        while (i < lines.length && (ind(lines[i]) >= w || (!lines[i].trim() && ind(lines[i + 1] ?? '') >= w))) item.push(lines[i++].slice(w));
        const md = render(dedent(item), ctx).filter((l, k, a) => !(l === '' && k === a.length - 1));
        out.push(`${ordered ? `${n++}.` : '-'} ${md[0]}`, ...md.slice(1).map((l) => (l ? `   ${l}` : l)));
        while (i < lines.length && !lines[i].trim()) i++;
      }
      out.push('');
      continue;
    }
    const under = lines[i + 1]?.match(/^([\^~])\1{2,}$/);
    if (under && ind(line) === 0) {
      const title = line.trim();
      if (under[0].length < title.length) throw new Error(`rst: heading underline too short for "${title}"`);
      out.push(`${'#'.repeat((ctx.depth ?? 2) + (under[1] === '^' ? 1 : 2))} ${inline(title, ctx)} {#${register(title, ctx)}}`, '');
      i += 2;
      continue;
    }
    if (lines[i + 1] && /^([-=~^])\1{2,}$/.test(lines[i + 1])) throw new Error(`rst: unexpected heading "${line}"`);
    if (lines[i + 1]?.trim() && ind(lines[i + 1]) > 0) {
      // definition list item: term, then its indented definition
      const def = [];
      let j = i + 1;
      for (; j < lines.length; j++) {
        if (lines[j].trim() && ind(lines[j]) === 0) break;
        def.push(lines[j]);
      }
      out.push(`**${inline(line.trim(), ctx)}**`, '', ...render(trimBlank(dedent(def)), ctx));
      i = j;
      continue;
    }
    const p = [];
    while (i < lines.length && lines[i].trim() && ind(lines[i]) === 0) p.push(lines[i++]);
    const literal = p.at(-1).endsWith('::');
    if (literal) {
      const last = p.at(-1);
      p[p.length - 1] = last === '::' ? '' : last.endsWith(' ::') ? last.slice(0, -3) : last.slice(0, -1);
    }
    const text = para(p.filter((l) => l.trim()), ctx);
    if (text) out.push(text, '');
    if (literal) {
      const lit = [];
      while (i < lines.length && (!lines[i].trim() || ind(lines[i]) > 0)) lit.push(lines[i++]);
      out.push(...fence(ctx.lang || 'text', trimBlank(dedent(lit))));
    }
  }
  return out;
}

/** Two passes: the first collects signature and heading targets, so a reference may precede its target. A caller may pass a shared `ctx.targets` map (references across texts) and `ctx.collect` to run the first pass only. */
export function toMarkdown(text, ctx) {
  const lines = trimBlank(text.split('\n'));
  const targets = ctx.targets ?? new Map();
  render(lines, { ...ctx, targets, collect: true });
  if (ctx.collect) return '';
  return render(lines, { ...ctx, targets }).join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

/** The `#[=[.rst:` blocks of a CMake module. */
export const rstBlocks = (cmake) => [...cmake.matchAll(/^#\[=\[\.rst:\n([\s\S]*?)\n#\]=\]/gm)].map((m) => m[1]);

/** Split a module rst block into text chunks and `.. command::`/`.. variable::` entries, in source order. */
export function entries(block) {
  const lines = block.split('\n');
  const out = [];
  let text = [];
  let i = 0;
  const flush = () => {
    if (trimBlank(text).length) out.push({ kind: 'text', lines: trimBlank(text) });
    text = [];
  };
  while (i < lines.length) {
    const m = lines[i].match(/^\.\. (command|variable):: (\S+)$/);
    if (!m) {
      text.push(lines[i++]);
      continue;
    }
    flush();
    const b = body(lines, i);
    out.push({ kind: m[1], name: m[2], lines: b.lines });
    i = b.next;
  }
  flush();
  return out;
}
