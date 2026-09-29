// Render still frames at chosen timestamps: node snap.mjs <outdir> t1 t2 ...
import { createRequire } from 'module';
import path from 'path';
import { routeFonts } from './fonts.mjs';
import { fileURLToPath } from 'url';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const [outDir, ...times] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errors.push(m.text()); });
page.on('pageerror', e => errors.push('PAGEERROR ' + e.message));
await routeFonts(page);
await page.goto('file://' + path.resolve(here, '../index.html') + '#record');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
for (const t of times) {
  const t0 = Date.now();
  await page.evaluate(v => window.__frame(v), Number(t));
  await page.screenshot({ path: path.join(outDir, `t${String(t).padStart(6, '0')}.png`) });
  console.log(t, 'ms', Date.now() - t0);
}
console.log('errors:', errors.slice(0, 20));
await browser.close();
