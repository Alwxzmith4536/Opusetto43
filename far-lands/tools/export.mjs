// Render the beat, the final mix, the cover and the music video from the page itself.
//
//   python3 vocals.py      -> build/vocals.mp3, build/data.json
//   node export.mjs        -> build/beat.mp3, index.html, far-lands-protocol.mp3/.mp4, cover.png
//
// Needs Playwright (Chromium) and ffmpeg on PATH.
import { execSync, spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); }
catch { playwright = require(join(execSync("npm root -g").toString().trim(), "playwright")); }

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const build = join(root, "build");
const page_url = pathToFileURL(join(root, "index.html")).href;
const FPS = 30;

const run = (cmd, args) => execSync([cmd, ...args].map(a => JSON.stringify(a)).join(" "), { stdio: "inherit" });
const log = (...a) => console.log("[export]", ...a);

const browser = await playwright.chromium.launch();
// Fetch Google Fonts with curl (it honours the proxy settings) and hand them to the page,
// so frames never fall back to system fonts.
const fontCache = new Map();
async function open() {
  const page = await browser.newPage({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  page.on("pageerror", e => console.error("pageerror", e.stack || e.message));
  const ua = await page.evaluate(() => navigator.userAgent);
  await page.route(/fonts\.(googleapis|gstatic)\.com/, async route => {
    const url = route.request().url();
    if (!fontCache.has(url)) fontCache.set(url, execSync(`curl -sSL --max-time 60 -A ${JSON.stringify(ua)} ${JSON.stringify(url)}`));
    const css = url.includes("googleapis");
    await route.fulfill({ body: fontCache.get(url), contentType: css ? "text/css" : "font/woff2", headers: { "access-control-allow-origin": "*" } });
  });
  await page.goto(page_url);
  await page.evaluate(() => window.FLP.ready);
  const fonts = await page.evaluate(() => ['168px "Pirata One"', '26px "VT323"', '700 42px "Chakra Petch"'].map(f => document.fonts.check(f)));
  if (fonts.includes(false)) throw new Error("web fonts did not load: " + fonts);
  return page;
}

// 1. Synthesize the beat with the page's own Web Audio code and freeze it to MP3.
run("node", [join(here, "build.mjs"), "--synth"]);
let page = await open();
const beat = await page.evaluate(() => window.FLP.beatWav());
log(`beat peak ${beat.peak.toFixed(3)} rms ${beat.rms.toFixed(3)}`);
writeFileSync(join(build, "beat.wav"), Buffer.from(beat.b64, "base64"));
run("ffmpeg", ["-y", "-loglevel", "error", "-i", join(build, "beat.wav"), "-codec:a", "libmp3lame", "-b:a", "160k", join(build, "beat.mp3")]);
await page.close();

// 2. Rebuild the page with the frozen beat, then mix exactly what the page plays.
run("node", [join(here, "build.mjs")]);
page = await open();
const mix = await page.evaluate(() => window.FLP.mixWav());
log(`mix peak ${mix.peak.toFixed(3)} rms ${mix.rms.toFixed(3)}`);
const mixWav = join(build, "mix.wav");
writeFileSync(mixWav, Buffer.from(mix.b64, "base64"));
run("ffmpeg", ["-y", "-loglevel", "error", "-i", mixWav, "-codec:a", "libmp3lame", "-b:a", "192k",
  "-metadata", "title=Far Lands Protocol", "-metadata", "artist=Claude vs ChatGPT (fan parody)", join(root, "far-lands-protocol.mp3")]);

// 3. Cover image.
const poster = await page.evaluate(() => window.FLP.poster());
writeFileSync(join(root, "cover.png"), Buffer.from(poster.split(",")[1], "base64"));

// 4. Music video, frame by frame.
const dur = await page.evaluate(() => window.FLP.DUR);
const frames = Math.round(dur * FPS);
const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-c:v", "mjpeg", "-framerate", String(FPS), "-i", "-",
  "-i", mixWav, "-c:v", "libx264", "-preset", "slow", "-crf", "28", "-pix_fmt", "yuv420p",
  "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", join(root, "far-lands-protocol.mp4")], { stdio: ["pipe", "inherit", "inherit"] });
const done = new Promise((res, rej) => ff.on("close", code => code === 0 ? res() : rej(new Error("ffmpeg exited " + code))));
for (let i = 0; i < frames; i++) {
  const url = await page.evaluate(t => window.FLP.frame(t), i / FPS);
  const ok = ff.stdin.write(Buffer.from(url.split(",")[1], "base64"));
  if (!ok) await new Promise(r => ff.stdin.once("drain", r));
  if (i % 150 === 0) log(`frame ${i}/${frames}`);
}
ff.stdin.end();
await done;
await browser.close();
log("done");
