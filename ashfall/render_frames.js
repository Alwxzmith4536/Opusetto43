// usage: node render_frames.js <outDir> <startFrame> <endFrame> [scale] [jpgQuality]
// Renders frames [start,end) of ASHFALL to JPEG files in headless Chromium.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const [outDir, a, b, sc, q] = process.argv.slice(2);
const start = +a, end = +b, scale = +(sc || 1), quality = +(q || 0.93);
(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const br = await chromium.launch();
  const p = await br.newPage({ viewport: { width: 400, height: 300 } });
  p.on('pageerror', e => { console.error('PAGEERROR', e); process.exit(2); });
  await p.setContent('<body style="margin:0"><canvas id=c></canvas></body>');
  for (const f of ['core.js', 'poses.js', 'sim.js', 'story.js', 'render.js']) await p.addScriptTag({ content: fs.readFileSync(path.join(__dirname, f), 'utf8') });
  await p.evaluate(s => { window.R = createRenderer(document.getElementById('c'), s); }, scale);
  const t0 = Date.now();
  for (let i = start; i < end; i++) {
    const url = await p.evaluate(({ i, quality }) => { R.frame(i); return R.canvas.toDataURL('image/jpeg', quality); }, { i, quality });
    fs.writeFileSync(path.join(outDir, `f${String(i).padStart(5, '0')}.jpg`), Buffer.from(url.slice(url.indexOf(',') + 1), 'base64'));
    if ((i - start) % 25 === 0) console.log(`frame ${i} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
  }
  await br.close();
  console.log('done', start, end, ((Date.now() - t0) / 1000).toFixed(1) + 's');
})();
