#!/usr/bin/env node
// Renders the Far Lands Feud video. Drives farlands/index.html in headless Chromium
// one frame at a time (the page exposes window.FL when window.__RENDER__ is set),
// writes JPEG frames from a few parallel pages, then muxes them with the mixed track.
//
//   node render_video.mjs --audio build/far-lands-feud.wav            full 1280x720 video
//   node render_video.mjs --stills 3,6.05,31 --out /tmp/stills          preview frames
//   node render_video.mjs --poster --out media                          cover art (1080x1080)
import { createRequire } from 'node:module';
import { execFileSync, execSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

const require = createRequire(import.meta.url);
function loadPlaywright() {
  try { return require('playwright'); } catch { /* fall back to a global install */ }
  const globalRoot = execSync('npm root -g').toString().trim();
  return require(path.join(globalRoot, 'playwright'));
}
const { chromium } = loadPlaywright();

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const opt = { fps: 30, dur: 60, w: 1280, h: 720, workers: Math.max(1, Math.min(4, os.cpus().length - 1)), out: path.join(root, 'media') };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const k = argv[i].replace(/^--/, '');
  if (['poster'].includes(k)) opt[k] = true;
  else opt[k] = argv[++i];
}
for (const k of ['fps', 'dur', 'w', 'h', 'workers']) opt[k] = Number(opt[k]);

// The page's Google Fonts. This container's Chromium doesn't trust the egress proxy's CA,
// so curl (which does) fetches the stylesheet and font files once, and the page gets
// them through request routing. TLS verification stays on everywhere.
function fontCache() {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const href = html.match(/href="(https:\/\/fonts\.googleapis\.com\/css2[^"]+)"/)[1].replace(/&amp;/g, '&');
  const dir = path.join(os.tmpdir(), 'farlands-fonts');
  fs.mkdirSync(dir, { recursive: true });
  const ua = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36';
  const cssPath = path.join(dir, createHash('sha1').update(href).digest('hex') + '.css');
  if (!fs.existsSync(cssPath)) execFileSync('curl', ['-sSfL', '-A', ua, '-o', cssPath, href]);
  const css = fs.readFileSync(cssPath, 'utf8');
  const files = new Map();
  for (const url of new Set(css.match(/https:\/\/fonts\.gstatic\.com\/[^)\s'"]+/g) || [])) {
    const f = path.join(dir, createHash('sha1').update(url).digest('hex') + path.extname(new URL(url).pathname));
    if (!fs.existsSync(f)) execFileSync('curl', ['-sSfL', '-o', f, url]);
    files.set(url, f);
  }
  return { css, files };
}
const fonts = fontCache();

async function openPage(browser, w, h, sceneScale = 0.5) {
  const page = await browser.newPage({ viewport: { width: Math.min(w, 1600), height: Math.min(h, 1000) } });
  page.on('console', m => { if (m.type() === 'error') console.error('[page]', m.text()); });
  page.on('pageerror', e => console.error('[page]', e.message));
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ status: 200, contentType: 'text/css; charset=utf-8', body: fonts.css }));
  await page.route('https://fonts.gstatic.com/**', route => {
    const f = fonts.files.get(route.request().url());
    return f ? route.fulfill({ status: 200, path: f, headers: { 'access-control-allow-origin': '*', 'content-type': 'font/woff2' } }) : route.abort();
  });
  await page.addInitScript(cfg => { window.__RENDER__ = cfg; }, { w, h, sceneScale });
  await page.goto(pathToFileURL(path.join(root, 'index.html')).href, { waitUntil: 'load' });
  await page.waitForFunction(() => window.FL, null, { timeout: 30000 });
  if (!(await page.evaluate(() => window.FL.ready))) throw new Error('WebGL 2 is not available in this browser');
  const missing = await page.evaluate(() => ['900 40px "Grenze Gotisch"', '900 40px "Big Shoulders Display"', '40px "Silkscreen"'].filter(f => !document.fonts.check(f)));
  if (missing.length) console.warn('fonts not loaded:', missing.join(', '));
  return page;
}

async function grab(page, js, arg) {
  const url = await page.evaluate(js, arg);
  return Buffer.from(url.slice(url.indexOf(',') + 1), 'base64');
}

const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
try {
  fs.mkdirSync(opt.out, { recursive: true });
  if (opt.poster) {
    const page = await openPage(browser, 1080, 1080, 0.5);
    fs.writeFileSync(path.join(opt.out, 'cover.jpg'), await grab(page, () => window.FL.poster()));
    const wide = await openPage(browser, opt.w, opt.h, 0.5);
    fs.writeFileSync(path.join(opt.out, 'poster.jpg'), await grab(wide, () => window.FL.poster()));
    console.log('wrote cover.jpg and poster.jpg');
  } else if (opt.stills) {
    const page = await openPage(browser, opt.w, opt.h);
    for (const t of String(opt.stills).split(',').map(Number)) {
      const t0 = Date.now();
      fs.writeFileSync(path.join(opt.out, `still-${t.toFixed(2)}.jpg`), await grab(page, ([t]) => window.FL.frame(t, 'image/jpeg', 0.9), [t]));
      console.log(`t=${t}s rendered in ${Date.now() - t0} ms`);
    }
  } else {
    if (!opt.audio) throw new Error('--audio <mix.wav> is required for the video');
    const frames = Math.round(opt.dur * opt.fps);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'farlands-frames-'));
    const pages = await Promise.all(Array.from({ length: opt.workers }, () => openPage(browser, opt.w, opt.h)));
    let done = 0;
    const started = Date.now();
    await Promise.all(pages.map(async (page, k) => {
      for (let i = k; i < frames; i += pages.length) {
        const jpg = await grab(page, ([t]) => window.FL.frame(t, 'image/jpeg', 0.95), [i / opt.fps]);
        fs.writeFileSync(path.join(dir, `f${String(i).padStart(5, '0')}.jpg`), jpg);
        if (++done % 150 === 0) console.log(`${done}/${frames} frames, ${((Date.now() - started) / done).toFixed(0)} ms/frame`);
      }
    }));
    const out = path.join(opt.out, 'far-lands-feud.mp4');
    const ff = spawnSync('ffmpeg', ['-y', '-v', 'error', '-framerate', String(opt.fps), '-i', path.join(dir, 'f%05d.jpg'),
      '-i', opt.audio, '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'slow', '-crf', String(opt.crf || 23),
      // the film grain and static would otherwise push this past 20 Mbps
      '-maxrate', '2800k', '-bufsize', '5600k',
      '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart',
      '-metadata', 'title=Far Lands Feud', '-metadata', 'artist=Claude vs ChatGPT (fan parody)', out], { stdio: 'inherit' });
    if (ff.status !== 0) throw new Error('ffmpeg failed');
    fs.rmSync(dir, { recursive: true, force: true });
    console.log(`wrote ${out} in ${((Date.now() - started) / 1000).toFixed(0)} s`);
  }
} finally {
  await browser.close();
}
