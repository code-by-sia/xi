// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'index',
    'getting-started',
    'cli',
    'language-guide',
    'dependency-injection',
    'multi-file',
    'error-handling',
    'decisions',
    'interrupts',
    'atoms',
    'machines',
    'stdlib',
    'serialization',
    'events',
    'web',
    'threading',
    'internals',
    {
      type: 'category',
      label: 'Proposals (draft)',
      items: ['proposals/memory-management', 'proposals/typed-events', 'proposals/state-machines'],
    },
  ],
};

module.exports = sidebars;
