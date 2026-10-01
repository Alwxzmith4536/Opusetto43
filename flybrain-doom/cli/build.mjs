#!/usr/bin/env node
// Bundle the engine and the web app into one self-contained HTML file.
//   node cli/build.mjs
// Writes index.html (open it straight from disk) and dist/artifact.html
// (the same page without the document wrapper, for hosting as an artifact).

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const MODULES = ['rng', 'maps', 'world', 'eye', 'connectome', 'brain', 'agent', 'stats', 'experiment'];

function bundleCore() {
  const names = [];
  const seen = new Map();
  const parts = MODULES.map((m) => {
    let src = readFileSync(join(root, 'src', `${m}.js`), 'utf8');
    src = src.replace(/^import [^;]+;\s*$/gm, '');
    src = src.replace(/^export (function\*?|const|let|class) ([A-Za-z_$][\w$]*)/gm, (_, kind, name) => { names.push(name); return `${kind} ${name}`; });
    if (/^export /m.test(src)) throw new Error(`${m}.js: unsupported export form`);
    for (const [, name] of src.matchAll(/^(?:function\*?|const|let|class) ([A-Za-z_$][\w$]*)/gm)) {
      if (seen.has(name)) throw new Error(`top-level name '${name}' defined in both ${seen.get(name)}.js and ${m}.js`);
      seen.set(name, m);
    }
    return `// ---- ${m}.js ----\n${src.trim()}\n`;
  });
  return `var FlyCore = (function () {\n'use strict';\n${parts.join('\n')}\nreturn { ${names.join(', ')} };\n})();`;
}

const core = bundleCore();
const render = `(function () {\n${readFileSync(join(root, 'web', 'render.js'), 'utf8')}\nwindow.Renderer = Renderer;\nwindow.drawEyes = drawEyes;\n})();`;
const app = `(function () {\n${readFileSync(join(root, 'web', 'app.js'), 'utf8')}\n})();`;
const refPath = join(root, 'results', 'reference.json');
if (!existsSync(refPath)) throw new Error('results/reference.json is missing: run `node cli/run.mjs` first');
const reference = readFileSync(refPath, 'utf8').trim();
const guard = (s) => s.replace(/<\/script/gi, '<\\/script');

const page = readFileSync(join(root, 'web', 'template.html'), 'utf8')
  .replace('/*CORE*/', () => guard(core))
  .replace('/*RENDER*/', () => guard(render))
  .replace('/*REFERENCE*/', () => guard(reference))
  .replace('/*APP*/', () => guard(app));

mkdirSync(join(root, 'dist'), { recursive: true });
writeFileSync(join(root, 'dist', 'artifact.html'), page);
const doc = `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n<style>body{margin:0}</style>\n</head>\n<body>\n${page}\n</body>\n</html>\n`;
writeFileSync(join(root, 'index.html'), doc);
console.log(`Built index.html (${(doc.length / 1024).toFixed(0)} KB) and dist/artifact.html`);
