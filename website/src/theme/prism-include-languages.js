// Swizzled (override) to register additional Prism languages AND alias the X
// language to TypeScript, since Prism has no `x` grammar. X shares enough syntax
// (type/interface/class/let/import/export/namespace, etc.) for a good result.
import siteConfig from '@generated/docusaurus.config';

export default function prismIncludeLanguages(PrismObject) {
  const {
    themeConfig: {prism},
  } = siteConfig;
  const {additionalLanguages} = prism;

  const PrismBefore = globalThis.Prism;
  globalThis.Prism = PrismObject;

  additionalLanguages.forEach((lang) => {
    if (lang === 'php') {
      // eslint-disable-next-line global-require
      require('prismjs/components/prism-markup-templating.js');
    }
    // eslint-disable-next-line global-require, import/no-dynamic-require
    require(`prismjs/components/prism-${lang}`);
  });

  // ```x  blocks highlight using the TypeScript grammar.
  if (PrismObject.languages.typescript) {
    PrismObject.languages.x = PrismObject.languages.typescript;
  }

  delete globalThis.Prism;
  if (typeof PrismBefore !== 'undefined') {
    globalThis.Prism = PrismObject;
  }
}
