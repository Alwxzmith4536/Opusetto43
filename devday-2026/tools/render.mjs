// Renders the parody stream to an MP4, frame by frame, then adds the synthesized soundtrack.
//   FFMPEG=/path/to/ffmpeg node render.mjs [--fps 30] [--workers 4] [--seconds 20] [--out ../devday-2026-rtx-on.mp4]
// The page exposes window.__frame(t), so every frame is drawn at an exact timestamp
// and the result does not depend on how fast the machine is.
import { createRequire } from 'module';
import { spawn, execFileSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import { routeFonts } from './fonts.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || '/opt/node22/lib/node_modules/playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (name, dflt) => { const i = argv.indexOf('--' + name); return i >= 0 ? argv[i + 1] : dflt; };
const FPS = Number(arg('fps', 30));
const WORKERS = Number(arg('workers', 4));
const FF = process.env.FFMPEG || 'ffmpeg';
const PY = process.env.PYTHON || 'python3';
const OUT = path.resolve(arg('out', path.join(here, '..', 'devday-2026-rtx-on.mp4')));
const TMP = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'devday-'));
const PAGE = 'file://' + path.resolve(here, '../index.html') + '#record';

const browser = await chromium.launch();
async function open() {
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1.2 });
  await routeFonts(page);
  await page.goto(PAGE);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  return page;
}

const probe = await open();
const meta = await probe.evaluate(() => window.__meta);
await probe.close();
const metaPath = path.join(TMP, 'meta.json');
fs.writeFileSync(metaPath, JSON.stringify(meta));
const DUR = Number(arg('seconds', meta.DUR));
const total = Math.round(DUR * FPS);
const per = Math.ceil(total / WORKERS);
let done = 0;
const started = Date.now();

async function worker(i) {
  const f0 = i * per, f1 = Math.min(total, f0 + per);
  if (f0 >= f1) return null;
  const page = await open();
  const file = path.join(TMP, `seg${i}.mp4`);
  const ff = spawn(FF, ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', String(FPS), file], { stdio: ['pipe', 'inherit', 'inherit'] });
  const closed = new Promise((res, rej) => ff.on('close', c => (c === 0 ? res() : rej(new Error(`ffmpeg exited with ${c}`)))));
  for (let f = f0; f < f1; f++) {
    await page.evaluate(t => window.__frame(t), f / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (++done % 300 === 0) console.log(`${done}/${total} frames, ${Math.round((Date.now() - started) / 1000)}s`);
  }
  ff.stdin.end();
  await closed;
  await page.close();
  return file;
}

const segs = (await Promise.all(Array.from({ length: WORKERS }, (_, i) => worker(i)))).filter(Boolean);
await browser.close();

const list = path.join(TMP, 'list.txt');
fs.writeFileSync(list, segs.map(f => `file '${f}'`).join('\n'));
const video = path.join(TMP, 'video.mp4');
execFileSync(FF, ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', video]);

const wav = path.join(TMP, 'audio.wav');
execFileSync(PY, [path.join(here, 'soundtrack.py'), metaPath, wav, String(DUR)], { stdio: 'inherit' });
execFileSync(FF, ['-v', 'error', '-y', '-i', video, '-i', wav, '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', OUT]);
fs.rmSync(TMP, { recursive: true, force: true });
console.log('wrote', OUT);
