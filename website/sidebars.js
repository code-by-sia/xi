// @ts-check

// Learning-oriented order: a new developer can read top to bottom to go from
// "what is Xi" through the core language, how to structure programs, and on to
// the domain features, concurrency/memory, and the standard library. The
// headline domain features — Collections, Events, Web and Query — sit at the
// sidebar root, just above the Reference section.

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'index',
    {
      type: 'category',
      label: 'Getting started',
      collapsed: false,
      items: ['getting-started', 'cli'],
    },
    {
      type: 'category',
      label: 'The language',
      collapsed: false,
      items: ['language-guide', 'error-handling', 'decisions'],
    },
    {
      type: 'category',
      label: 'Dependency injection & projects',
      collapsed: false,
      items: ['dependency-injection', 'multi-file', 'config', 'testing'],
    },
    {
      type: 'category',
      label: 'State & interrupts',
      items: ['atoms', 'machines', 'interrupts'],
    },
    {
      type: 'category',
      label: 'Concurrency & memory',
      items: ['threading', 'memory'],
    },
    {
      type: 'category',
      label: 'Standard library & interop',
      items: ['stdlib', 'serialization', 'ffi', 'wasm'],
    },
    'collections',
    'events',
    'web',
    'query',
    'data',
    {
      type: 'category',
      label: 'Reference',
      items: ['skill', 'internals'],
    },
  ],
};

module.exports = sidebars;
