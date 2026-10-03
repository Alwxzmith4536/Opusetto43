// Renders index.html frame-by-frame in headless Chromium and encodes the MP4.
// usage: node render.cjs [--stills 6,20,30] [--fps 24]
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs'), { spawn } = require('child_process');
const args = process.argv.slice(2);
const arg = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const FPS = +arg('--fps', 24), STILLS = arg('--stills'), OUT = arg('--out', path.join(__dirname, 'seek-pov-part3.mp4'));
const THREE_JS = arg('--three', path.join(path.dirname(require.resolve('three', { paths: [process.cwd(), __dirname] })), 'three.module.js'));

(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('console', m => { if (m.type() === 'error') console.error('[page]', m.text()); });
  page.on('pageerror', e => console.error('[pageerror]', e.message));
  // fonts go through curl (it trusts the environment's proxy CA)
  await page.route(/fonts\.(googleapis|gstatic)\.com/, r => {
    try {
      const body = require('child_process').execFileSync('curl', ['-sS', '-A', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36', r.request().url()]);
      r.fulfill({ body, contentType: /googleapis/.test(r.request().url()) ? 'text/css' : 'font/woff2' });
    } catch { r.abort(); }
  });
  await page.route(/three@0\.170\.0\/build\/three\.module\.js$/, r => r.fulfill({ path: THREE_JS, contentType: 'text/javascript' }));
  await page.goto('file://' + path.join(__dirname, 'index.html') + '?render=1');
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  const tl = await page.evaluate(() => window.TIMELINE);
  fs.writeFileSync(path.join(__dirname, 'timeline.json'), JSON.stringify(tl, null, 1));
  if (STILLS) {
    for (const s of STILLS.split(',').map(Number)) {
      const url = await page.evaluate(t => window.renderFrame(t), s);
      fs.writeFileSync(arg('--dir', '.') + `/still_${s}.jpg`, Buffer.from(url.split(',')[1], 'base64'));
    }
    await browser.close(); return;
  }
  const audio = arg('--audio');
  const ff = spawn('ffmpeg', ['-y', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    ...(audio ? ['-i', audio] : []),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '19', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
    ...(audio ? ['-c:a', 'aac', '-b:a', '160k', '-shortest'] : []), OUT], { stdio: ['pipe', 'inherit', 'inherit'] });
  const N = Math.round(tl.DUR * FPS), t0 = Date.now();
  for (let f = 0; f < N; f++) {
    const url = await page.evaluate(t => window.renderFrame(t), f / FPS);
    if (!ff.stdin.write(Buffer.from(url.split(',')[1], 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 120 === 0) console.log(`frame ${f}/${N}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  await browser.close();
  console.log('wrote', OUT);
})();
