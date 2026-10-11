// Fence languages: the Shiki aliases astro.config.mjs registers and the set the fence gate (scripts/check-fences.mjs) accepts.
// `*-run` / `*-norun` are the docs-quality tiers (DOC-EX-20); Shiki must still highlight them as their base language.
export const LANG_ALIAS = {
  'bash-run': 'bash',
  'bash-norun': 'bash',
  'cmake-run': 'cmake',
  'cmake-norun': 'cmake',
};

// Languages the site's fences may use; each one has a Shiki grammar that colours something.
// `log` is for diagnostics: it colours quoted strings, numbers and paths in message output.
export const HIGHLIGHTED = new Set(['bash', 'sh', 'cmake', 'toml', 'json', 'yaml', 'powershell', 'diff', 'ini', 'log', 'markdown', 'python', 'js']);
