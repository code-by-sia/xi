// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'index',
    'getting-started',
    'cli',
    'language-guide',
    'multi-file',
    'error-handling',
    'decisions',
    'interrupts',
    'atoms',
    'machines',
    'stdlib',
    'serialization',
    'events',
    'internals',
    {
      type: 'category',
      label: 'Proposals (draft)',
      items: ['proposals/event-system', 'proposals/state-machines', 'proposals/decision-tables'],
    },
  ],
};

module.exports = sidebars;
