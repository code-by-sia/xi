// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'index',
    'getting-started',
    'cli',
    'skill',
    'language-guide',
    'dependency-injection',
    'config',
    'testing',
    'multi-file',
    'error-handling',
    'decisions',
    'interrupts',
    'atoms',
    'machines',
    'stdlib',
    'collections',
    'serialization',
    'events',
    'web',
    'threading',
    'ffi',
    'wasm',
    'internals',
    {
      type: 'category',
      label: 'Proposals (draft)',
      items: ['proposals/closures', 'proposals/memory-management'],
    },
  ],
};

module.exports = sidebars;
