// The sidebar of the site: six groups per docs/discovery/ia-plan.md. scripts/check-anchors.mjs asserts every page in site/pages
// is listed here and every entry has a page, so neither a page nor a link goes missing unnoticed.
export const GROUPS = [
  { label: 'Get started', items: [['Overview', '/'], ['Tutorial: run jq in a build', '/tutorial/']] },
  {
    label: 'Everyday',
    items: [
      ['Everyday guides', '/guides/'],
      ['Add or change a pinned tool', '/guides/add-a-tool/'],
      ['Pin and freeze tag resolution', '/guides/pin-and-freeze/'],
      ['Pin digests instead of a snapshot', '/guides/pin-digests/'],
      ['Make the build find provisioned content', '/guides/find-package/'],
      ['Use an ocx you already installed', '/guides/use-system-ocx/'],
      ['Update the vendored files', '/guides/update-vendored/'],
      ['Move from 0.3 to 0.4', '/guides/migrate-04/'],
    ],
  },
  {
    label: 'Integrate',
    items: [
      ['Reproduce the build in CI', '/guides/ci/'],
      ['Build behind a mirror or offline', '/guides/mirror/'],
      ['Route package pulls through a mirror', '/guides/mirror-packages/'],
      ['Cross-build with foreign-platform content', '/guides/cross-build/'],
      ['Apply organisation-wide download rules', '/guides/policy-and-config/'],
    ],
  },
  {
    label: 'Concepts',
    items: [
      ['How find_ocx works', '/concepts/how-it-works/'],
      ['Two entry points', '/concepts/entry-points/'],
      ['Reproducible first', '/concepts/reproducible-first/'],
      ['Lazy versus eager', '/concepts/lazy-vs-eager/'],
      ['Environment and config', '/concepts/env-and-config/'],
    ],
  },
  {
    label: 'Troubleshooting',
    items: [['Configure errors', '/troubleshooting/configure-errors/'], ['Module conflicts', '/troubleshooting/module-conflicts/'], ['Exit codes', '/troubleshooting/exit-codes/']],
  },
  {
    label: 'Reference',
    items: [['Commands', '/reference/commands/'], ['Variables', '/reference/variables/'], ['Findocx.cmake', '/reference/findocx/']],
  },
];

