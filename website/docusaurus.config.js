// @ts-check
const {themes} = require('prism-react-renderer');
const fs = require('fs');
const path = require('path');

// Single source of truth for the language version: the compiler's xcVersion().
// Read at build time so the navbar badge tracks releases with no extra bump.
let xiVersion = '';
try {
  const drv = fs.readFileSync(path.join(__dirname, '../compiler/driver.xi'), 'utf8');
  const m = drv.match(/xcVersion\(\)\s*->\s*String\s*\{\s*return\s*"([^"]+)"/);
  if (m) xiVersion = m[1];
} catch (e) { /* leave blank if unreadable */ }

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'The Ξ Programming Language',
  tagline: 'Statically-typed, AOT-compiled, with first-class dependency injection',
  favicon: 'img/logo.svg',

  url: 'https://code-by-sia.github.io',
  baseUrl: '/xi/',
  organizationName: 'code-by-sia',
  projectName: 'x',

  onBrokenLinks: 'warn',

  // .md files are CommonMark (so `<...>` in prose is safe); .mdx is MDX.
  // Mermaid renders ```mermaid code blocks via @docusaurus/theme-mermaid.
  markdown: {
    mermaid: true,
    format: 'detect',
    hooks: {onBrokenMarkdownLinks: 'warn'},
  },
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          path: '../docs',
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: 'https://github.com/code-by-sia/xi/edit/main/',
        },
        blog: false,
        theme: {customCss: require.resolve('./src/css/custom.css')},
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'The Ξ Programming Language',
        logo: {alt: 'Xi logo', src: 'img/logo.svg', srcDark: 'img/logo-white.svg'},
        items: [
          ...(xiVersion ? [{
            href: 'https://github.com/code-by-sia/xi/releases',
            label: `v${xiVersion}`,
            position: 'right',
            className: 'navbar-version-badge',
          }] : []),
          {href: 'https://github.com/code-by-sia/xi', label: 'GitHub', position: 'right'},
        ],
      },
      footer: {
      },
      prism: {
        theme: themes.oneLight,
        darkTheme: themes.oneDark,
        // typescript is loaded so `x` can be aliased to it (see
        // src/theme/prism-include-languages.js).
        additionalLanguages: ['typescript', 'bash', 'json', 'c'],
      },
      colorMode: {respectPrefersColorScheme: true},
    }),
};

module.exports = config;
