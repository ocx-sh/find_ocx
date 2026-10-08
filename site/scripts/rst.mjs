// Converts the reStructuredText that find_ocx documents itself in (docs/*.rst and the `#[=[.rst:`
// blocks of the CMake modules) to Markdown. Pure: callers pass text and a context, nothing is read here
// except `literalinclude` targets through ctx.readFile. Anything it does not know throws, so a new
// directive or role in the sources fails the build instead of rendering wrong.

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

/** ctx: { commands:Set, variables:Set, urls:{command, variable}, aliases:{name: url}, readFile(path)->string, lang } */
export function inline(text, ctx) {
  return text
    .split(/(``[^`]+``)/)
    .map((part, i) => {
      if (i % 2) return '`' + part.slice(2, -2) + '`';
      return part
        .replace(/:(command|variable):`([^`]+)`/g, (_m, role, name) => {
          const alias = ctx.aliases?.[name];
          if (alias) return `[\`${name}\`](${alias})`;
          const known = role === 'command' ? ctx.commands : ctx.variables;
          if (!known.has(name)) throw new Error(`rst: :${role}:\`${name}\` has no .. ${role}:: block`);
          return `[\`${name}\`](${ctx.urls[role]}#${slug(name)})`;
        })
        .replace(/:(\w+):`/g, (_m, role) => {
          throw new Error(`rst: unknown role :${role}:`);
        })
        .replace(/`([^`<]+?)\s*<([^>]+)>`_/g, (_m, label, url) => `[${label}](${url})`)
        .replace(/`([^`]+)`_/g, (_m, ref) => {
          if (!ctx.refs) throw new Error(`rst: internal reference \`${ref}\`_ outside a signature list`);
          return `[${ref}](#${slug(ref)})`;
        })
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
  const cell = (c) => inline(c, ctx).replace(/\|/g, '\\|');
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

function directive(name, arg, lines, ctx) {
  const { opts, rest } = options(lines);
  switch (name) {
    case 'toctree':
      return [];
    case 'code-block':
      return fence(arg || ctx.lang || 'text', rest);
    case 'parsed-literal':
      return fence(ctx.lang || 'text', rest.map((l) => l.replace(/`([^`]+)`_/g, '$1')));
    case 'warning':
    case 'note':
    case 'tip':
      return [`:::${name === 'warning' ? 'caution' : name}`, ...render(rest, ctx), ':::', ''];
    case 'literalinclude': {
      let src = ctx.readFile(arg).split('\n');
      if (opts['start-at']) {
        const at = src.findIndex((l) => l.includes(opts['start-at']));
        if (at < 0) throw new Error(`rst: literalinclude ${arg}: start-at "${opts['start-at']}" not found`);
        src = src.slice(at);
      }
      return fence(opts.language || ctx.lang || 'text', trimBlank(src), opts.caption);
    }
    case 'signature': {
      const sig = rest[0];
      const op = sig.match(/\(([A-Z_]+)/)?.[1];
      if (!op) throw new Error(`rst: signature without an operation: ${sig}`);
      return [`### ${op}`, '', ...fence('cmake', [sig]), ...render(trimBlank(rest.slice(1)), ctx)];
    }
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

export const toMarkdown = (text, ctx) => render(trimBlank(text.split('\n')), ctx).join('\n').replace(/\n{3,}/g, '\n\n').trim();

/** Split an rst file into { title, intro, sections: [{ title, lines }] } on `---`-underlined titles. */
export function sections(text) {
  const lines = text.split('\n');
  const out = { intro: [], sections: [] };
  let cur = out.intro;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i + 1] && /^-{3,}$/.test(lines[i + 1]) && lines[i].trim() && ind(lines[i]) === 0) {
      const s = { title: lines[i].trim(), lines: [] };
      out.sections.push(s);
      cur = s.lines;
      i++;
      continue;
    }
    cur.push(lines[i]);
  }
  return out;
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
