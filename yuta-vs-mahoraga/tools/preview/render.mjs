// Renders tools/preview/out/scenes.json to PNGs with three.js in headless Chromium.
// Usage (from yuta-vs-mahoraga/tools/preview):  npm install && node render.mjs [outDir] [sceneFilter]
import { createServer } from "node:http";
import { readFile, mkdir } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { chromium } from "playwright";

const here = resolve(".");
const outDir = resolve(process.argv[2] ?? "../../docs/previews");
const filter = process.argv[3];
const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json" };

const server = createServer(async (req, res) => {
  try {
    const path = join(here, decodeURIComponent(new URL(req.url, "http://x").pathname));
    const body = await readFile(path);
    res.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;

const { scenes } = JSON.parse(await readFile(join(here, "out/scenes.json"), "utf8"));
await mkdir(outDir, { recursive: true });

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
page.on("console", (m) => { if (m.type() === "error") console.error("page:", m.text()); });
page.on("pageerror", (e) => console.error("page error:", e.message));
await page.goto(`http://localhost:${port}/render.html`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });

for (const scene of scenes) {
  if (filter && !scene.name.includes(filter)) continue;
  const t0 = Date.now();
  await page.evaluate((s) => window.renderScene(s), scene);
  // Scenes named "_..." are intermediate images (e.g. the HUD background).
  // Scenes named "_..." are intermediate images kept as PNG; previews ship as JPEG.
  const file = scene.name.startsWith("_") ? join(here, "out", `${scene.name}.png`) : join(outDir, `${scene.name}.jpg`);
  await page.locator("#frame").screenshot(file.endsWith(".jpg") ? { path: file, type: "jpeg", quality: 90 } : { path: file });
  console.log(`${scene.name}  (${Date.now() - t0} ms)`);
}

// HUD preview: the real HUD tree (hud_export.luau) over the fight background.
if (!filter || "hud".includes(filter) || filter === "hud") {
  try {
    const hud = JSON.parse(await readFile(join(here, "out/hud.json"), "utf8"));
    await page.goto(`http://localhost:${port}/hud.html`);
    await page.waitForFunction(() => window.ready === true);
    await page.evaluate(([h, bg]) => window.renderHud(h, bg), [hud, "out/_hud_bg.png"]);
    await page.waitForTimeout(300);
    await page.locator("#frame").screenshot({ path: join(outDir, "19_hud.jpg"), type: "jpeg", quality: 90 });
    console.log("19_hud");
  } catch (e) {
    console.log("skipping HUD preview:", e.message);
  }
}
// Overview sheet of every preview.
if (!filter) {
  const shots = [...scenes.filter((s) => !s.name.startsWith("_")).map((s) => ({ file: `${s.name}.jpg`, title: s.title })),
    { file: "19_hud.jpg", title: "HUD: hotbar, boss bar with adaptation wheel" }];
  const images = await Promise.all(shots.map(async (s) => ({ ...s, data: (await readFile(join(outDir, s.file))).toString("base64") })));
  const cells = images.map((s) => `<figure><img src="data:image/jpeg;base64,${s.data}"><figcaption>${s.title}</figcaption></figure>`).join("");
  await page.setViewportSize({ width: 2000, height: 1200 });
  await page.setContent(`<!doctype html><meta charset="utf-8"><style>
    body{margin:0;background:#0b0911;color:#eee;font:14px "Liberation Sans",sans-serif}
    h1{font:700 30px "Liberation Sans",sans-serif;margin:22px 26px 4px} p{margin:0 26px 16px;color:#b9b0cc}
    main{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;padding:0 26px 26px}
    figure{margin:0;background:#16121f;border:1px solid #2a2438;border-radius:8px;overflow:hidden}
    img{display:block;width:100%} figcaption{padding:8px 10px;font-size:13px;color:#d9d2ea}
  </style><h1>Yuta Okkotsu vs Mahoraga: asset previews</h1>
  <p>Rendered from the Roblox parts built by the kit's own Luau code (tools/preview). In game these are lit by Roblox and animated.</p>
  <main>${cells}</main>`);
  await page.locator("body").screenshot({ path: join(outDir, "00_overview.jpg"), type: "jpeg", quality: 88 });
  console.log("00_overview");
}
await browser.close();
server.close();
