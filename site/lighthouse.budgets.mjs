/**
 * Lighthouse budgets and page discovery for `task site:lighthouse`. Every page of this site is the
 * `content` class of ocx-sh/website `tests/budgets.mjs`; a value here never exceeds the one there.
 * Sizes are gzip of the response body, in bytes.
 */
import { existsSync, readdirSync } from 'node:fs';

const KB = 1024;

/** Base path of the site, as in astro.config.mjs. */
export const BASE = '/integrations/cmake/';

/** Gated budget of every page (website `BUDGETS.content`). */
export const BUDGET = {
  /** Lighthouse `resource-summary:script:size`. */
  jsBytes: 11 * KB,
  /** Lighthouse `total-byte-weight`. */
  totalBytes: 147 * KB,
  /** Lighthouse `dom-size`. */
  domElements: 800,
};

/** One page's HTML, gzipped (website `HTML_GZ_MAX`): past it the document costs one more round trip. */
export const HTML_GZ_MAX = 14_200;

export const CATEGORIES = ['performance', 'accessibility', 'best-practices', 'seo'];

/** lhci assert matrix: score 1 in all four categories plus the JS, weight and DOM budgets. */
export const ASSERT_MATRIX = [
  {
    matchingUrlPattern: '.*',
    assertions: {
      ...Object.fromEntries(CATEGORIES.map((c) => [`categories:${c}`, ['error', { minScore: 1 }]])),
      'resource-summary:script:size': ['error', { maxNumericValue: BUDGET.jsBytes }],
      'total-byte-weight': ['error', { maxNumericValue: BUDGET.totalBytes }],
      'dom-size': ['error', { maxNumericValue: BUDGET.domElements }],
    },
  },
];

/**
 * Served path of every built HTML page, sorted, under `base` (`index.html` -> `<base>`,
 * `x/index.html` -> `<base>x/`). `404.html` is left out: the server answers it with status 404,
 * which Lighthouse refuses to audit. Throws `missing dist: <dir>` when the site is not built.
 * @param {string} [distDir]
 * @param {string} [base]
 * @returns {string[]}
 */
export function sitePages(distDir = 'dist', base = BASE) {
  if (!existsSync(distDir)) throw new Error(`missing dist: ${distDir}`);
  return readdirSync(distDir, { recursive: true, encoding: 'utf8' })
    .map((f) => f.split('\\').join('/'))
    .filter((f) => f.endsWith('.html') && f !== '404.html')
    .map((f) => `${base}${f.replace(/index\.html$/, '')}`)
    .sort();
}
