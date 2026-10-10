// Records site/casts/*.sh (those with `# cast: true`) into site/public/casts/<doc>.cast (asciicast v3, gitignored).
// A cast is a view on a script that already passes as a ctest: the recorder never gates anything (DOC-EX-11)
// and every recorded byte comes from a real run, only the typed command line is simulated (DOC-EX-12).
//
//   ocx exec -- node scripts/record-casts.mjs [--only <doc>] [--out <dir>]
//
// Needs asciinema (ocx.toml), cmake, ocx and network on PATH. Headless: asciinema --headless runs the
// driver in its own PTY, so no terminal is required (CI, ssh without -t, a pipe).
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE = fileURLToPath(new URL('..', import.meta.url));
const WIDTH = 100, ROWS = 40, TYPE_DELAY = 0.04, IDLE_LIMIT = 2; // recording window: tall enough that nothing scrolls; sanitize() shrinks the header to the used rows

/** `# key: value` header lines before the first non-comment line. */
export function parseScript(text) {
  const meta = {};
  for (const l of text.split('\n').slice(1)) {
    const m = l.match(/^# (\w+): (.*)$/);
    if (m) meta[m[1]] = m[2];
    else if (!l.startsWith('#')) break;
  }
  const region = (name) => {
    const m = text.match(new RegExp(`^# region ${name}\\n([\\s\\S]*?)^# endregion ${name}\\n`, 'm'));
    return m ? { start: m.index, end: m.index + m[0].length, body: m[1] } : null;
  };
  return { meta, cast: region('cast'), text };
}

/** Driver: pre silent, cast region typed then run, post silent. Blank lines split the region into commands. */
export function driver({ text, cast }) {
  const blocks = cast.body.trimEnd().split(/\n\s*\n/);
  const typed = blocks
    .map((b, i) => `__block <<'__CAST_EOF_${i}__'\n${b}\n__CAST_EOF_${i}__`)
    .join('\n');
  return `#!/usr/bin/env bash
set -euo pipefail
__block() {
  local b; b=$(cat)
  printf '\\033[1;32m$\\033[0m '
  for ((i = 0; i < \${#b}; i++)); do printf '%s' "\${b:i:1}"; sleep ${TYPE_DELAY}; done
  printf '\\n'; sleep 0.4
  eval "$b"; sleep 1
}
exec 3>&1 4>&2 >/dev/null 2>&1
${text.slice(text.indexOf('\n') + 1, cast.start)}
exec >&3 2>&4
${typed}
exec >/dev/null 2>&1
${text.slice(cast.end)}
`;
}

const asObjects = (t) => t.trim().split('\n').map((l) => JSON.parse(l));

/** Merge read-burst events (< 10 ms apart; typing is 30+ ms) so no path or digest is split across two events, then sanitize. */
export function sanitize(castText, subs, title) {
  const [hdr, ...ev] = asObjects(castText);
  const merged = [];
  for (const [dt, code, data] of ev) {
    const prev = merged.at(-1);
    if (prev && code === 'o' && prev[1] === 'o' && dt < 0.01) prev[2] += data;
    else merged.push([dt, code, data]);
  }
  const clean = (s) => {
    for (const [from, to] of subs) s = s.split(from).join(to);
    return s
      .replace(/sha256:([0-9a-f]{12})[0-9a-f]{52}/g, 'sha256:$1')  // keep 12 hex of a digest
      .replace(/\((\d+\.\d)\d*s\)/g, '(0.1s)')                      // "Configuring done (0.0s)"
      .replace(/\/tmp\/(?:tmp\.)?[\w.-]+/g, '/tmp/build');          // any stray mktemp path
  };
  merged[0][0] = Math.min(merged[0][0], 0.3); // the silent setup ran before the first byte
  const visible = merged.filter((e) => e[1] === 'o').map((e) => e[2]).join('').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
  const rows = visible.split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.replace(/\r/g, '').length / hdr.term.cols)), 0);
  const out = { version: 3, term: { cols: hdr.term.cols, rows: Math.max(rows + 1, 5) }, idle_time_limit: IDLE_LIMIT, title }; // auto height; drops timestamp, command, env
  return [out, ...merged.map(([dt, code, d]) => [Math.round(dt * 1000) / 1000, code, code === 'o' ? clean(d) : d])]
    .map((x) => JSON.stringify(x)).join('\n') + '\n';
}

function record(file, outDir) {
  const s = parseScript(readFileSync(file, 'utf8'));
  if (s.meta.cast !== 'true') return null;
  if (!s.cast || !s.meta.doc || !s.meta.title) throw new Error(`${file}: needs "# doc:", "# title:" and a "# region cast"`);
  const scratch = mkdtempSync(join(tmpdir(), 'cast-'));
  try {
    const drv = join(scratch, 'driver.sh');
    writeFileSync(drv, driver(s));
    const raw = join(scratch, 'raw.cast');
    const wrapper = join(SITE, 'scripts/run-cast-script.sh');
    const run = join(scratch, 'run'); // the wrapper's temp dir, known up front so its paths can be rewritten
    const r = spawnSync('asciinema', ['rec', '--headless', '--overwrite', '--return', '--quiet',
      '--window-size', `${WIDTH}x${ROWS}`, '--command', `${wrapper} ${drv}`, raw],
    { env: { ...process.env, CAST_TMP: run }, stdio: ['ignore', 'inherit', 'inherit'], encoding: 'utf8' });
    if (r.status !== 0) throw new Error(`${file}: recording failed (exit ${r.status}); the script must pass as a test first`);
    const text = readFileSync(raw, 'utf8');
    const subs = [
      [`${run}/work`, '~/hello-jq'], [`${run}/home/.ocx`, '~/.ocx'], [`${run}/home`, '~'],
      [homedir(), '~'],
    ];
    const dest = join(outDir, `${s.meta.doc}.cast`);
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, sanitize(text, subs, s.meta.title));
    return dest;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  const arg = (k) => process.argv[process.argv.indexOf(k) + 1];
  const only = process.argv.includes('--only') ? arg('--only') : null;
  const outDir = process.argv.includes('--out') ? arg('--out') : join(SITE, 'public/casts');
  const dir = join(SITE, 'casts');
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh')).sort()) {
    if (only && !f.startsWith(only.replace('/', '__'))) continue;
    const dest = record(join(dir, f), outDir);
    if (dest) console.log(`recorded ${dest}`);
  }
}
