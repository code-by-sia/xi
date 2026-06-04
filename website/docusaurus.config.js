// @ts-check
const {themes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'The X Programming Language',
  tagline: 'Statically-typed, AOT-compiled, with first-class dependency injection',
  favicon: 'img/logo.svg',

  url: 'https://code-by-sia.github.io',
  baseUrl: '/x/',
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
          editUrl: 'https://github.com/code-by-sia/x/edit/main/',
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
        title: 'X',
        logo: {alt: 'X logo', src: 'img/logo.svg', srcDark: 'img/logo-white.svg'},
        items: [
          {href: 'https://github.com/code-by-sia/x', label: 'GitHub', position: 'right'},
        ],
      },
      footer: {
        style: 'dark',
        copyright:
          'The X programming language — Apache-2.0. Built with Docusaurus.',
      },
      prism: {theme: themes.github, darkTheme: themes.dracula},
      colorMode: {respectPrefersColorScheme: true},
    }),
};

module.exports = config;
