// The docs-quality gate (.claude/skills/docs-instrument): the rule set's checks over the pages as the site builds them.
// Page-level checks read the port-docs output (directives expanded, so a snippet or cast counts as a command block);
// links_raw reads the source pages (its authoring half). Pages written by hand must be clean. The three reference pages
// are generated from the in-source rst blocks of the modules, so they only ratchet: the count of findings per check may
// never rise above site/docs-baseline.json (`--update-baseline` lowers it). Exit 1 on any finding above that.
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { delimiter, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isGenerated as generated } from './port-docs.mjs';

const SITE = fileURLToPath(new URL('../', import.meta.url));
const CHECKS = '../.claude/rules/docs-quality/checks';
const EXPANDED = '.docs-check';
const BASELINE = join(SITE, 'docs-baseline.json');
// The checks are standard library only and need 3.11; `uv` (ocx.toml) finds or fetches one.
const PY = ['uv', 'run', '--no-project', '--quiet', '--python', '>=3.11', 'python', '-I'];
const FINDING = /^\S.*:\d+(?::\d+)?:? (?:DOC-[A-Z]+-\d+|MD\d+\/)/m;

// markdownlint-cli2 is always on PATH: prose.py leaves heading hygiene to it when it is, so the counts do not depend on how the gate is started.
const env = { ...process.env, PATH: `${join(SITE, 'node_modules/.bin')}${delimiter}${process.env.PATH}` };
const sh = (cmd, args) => {
  const r = spawnSync(cmd, args, { cwd: SITE, encoding: 'utf8', env });
  if (r.error) throw r.error;
  return { code: r.status, lines: `${r.stdout}\n${r.stderr}`.split('\n').filter((l) => FINDING.test(l)), out: `${r.stdout}${r.stderr}` };
};
const py = (script, args) => sh(PY[0], [...PY.slice(1), `${CHECKS}/${script}.py`, ...args]);

const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((d) => (d.isDirectory() ? walk(join(dir, d.name)) : [join(dir, d.name)]));

// `file` is the page set a check reads; `root` its resolution base. links_raw reads the sources, the rest the expansion.
const PAGE_CHECKS = ['doc_declaration', 'prose', 'page_type', 'landing_check', 'doc_examples'];

export function main(argv = process.argv.slice(2)) {
  const update = argv.includes('--update-baseline');
  const port = spawnSync(process.execPath, ['scripts/port-docs.mjs', '--check-dir', EXPANDED], { cwd: SITE, encoding: 'utf8' });
  if (port.status !== 0) throw new Error(`port-docs failed:\n${port.stderr}`);

  const pages = walk(join(SITE, EXPANDED)).map((f) => relative(SITE, f)).filter((f) => /\.mdx?$/.test(f));
  const isGenerated = (f) => generated(relative(EXPANDED, f).replace(/\.mdx$/, '.md'));
  const sets = { written: pages.filter((f) => !isGenerated(f)), generated: pages.filter(isGenerated) };
  if (!sets.written.length || !sets.generated.length) throw new Error('docs-gate: no pages found in the expansion');

  const results = {}; // name -> { written: lines[], generated: lines[] }
  const record = (name, set, r) => ((results[name] ??= { written: [], generated: [] })[set].push(...r.lines), r);
  const broken = [];
  for (const [set, files] of Object.entries(sets)) {
    for (const name of PAGE_CHECKS) {
      const r = record(name, set, py(name, ['--root', EXPANDED, ...files]));
      if (r.code > 1) broken.push(`${name}: exit ${r.code}\n${r.out}`);
    }
    const md = record('markdownlint', set, sh('markdownlint-cli2', ['--config', '.markdownlint.jsonc', ...files]));
    if (md.code > 1) broken.push(`markdownlint: exit ${md.code}\n${md.out}`);
  }
  const raw = record('links_raw', 'written', py('links_raw', ['--root', 'pages']));
  if (raw.code > 1) broken.push(`links_raw: exit ${raw.code}\n${raw.out}`);
  // The checks prove themselves against their own fixtures (docs-instrument stop condition 1).
  for (const name of [...PAGE_CHECKS, 'links_raw', 'strip_prose']) {
    const r = py(name, ['--self-test']);
    if (r.code !== 0) broken.push(`${name} --self-test: exit ${r.code}\n${r.out}`);
  }
  if (broken.length) throw new Error(`docs-gate: a check did not run\n${broken.join('\n')}`);

  const counts = Object.fromEntries(Object.entries(results).map(([k, v]) => [k, v.generated.length]));
  if (update) {
    writeFileSync(BASELINE, `${JSON.stringify({ generated: counts }, null, 2)}\n`);
    console.log(`docs-gate: baseline written to site/docs-baseline.json`);
  }
  const baseline = JSON.parse(readFileSync(BASELINE, 'utf8')).generated;
  let bad = 0;
  for (const [name, r] of Object.entries(results)) {
    for (const l of r.written) (bad++, console.error(l));
    const allowed = baseline[name] ?? 0;
    if (r.generated.length > allowed) {
      bad += r.generated.length - allowed;
      for (const l of r.generated) console.error(l);
      console.error(`docs-gate: ${name} found ${r.generated.length} in the generated reference pages, baseline is ${allowed}`);
    }
    const note = r.generated.length < allowed ? ` (baseline ${allowed}: run \`pnpm run docs:baseline\` to lower it)` : '';
    console.log(`${name}: ${r.written.length} in written pages, ${r.generated.length} in generated pages${note}`);
  }
  console.log(`docs-gate: ${sets.written.length} written and ${sets.generated.length} generated pages`);
  return bad ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main();
