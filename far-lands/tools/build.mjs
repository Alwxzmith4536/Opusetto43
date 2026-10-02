// Inline the vocal stem and its timing data into the page.
// Usage: node build.mjs   (after python3 vocals.py)
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const build = join(here, "..", "build");
const template = readFileSync(join(here, "template.html"), "utf8");
const data = readFileSync(join(build, "data.json"), "utf8").trim();
const vocals = readFileSync(join(build, "vocals.mp3")).toString("base64");
// beat.mp3 comes from export.mjs; without it the page synthesizes the beat on load.
const beatPath = join(build, "beat.mp3");
const beat = existsSync(beatPath) && !process.argv.includes("--synth") ? readFileSync(beatPath).toString("base64") : "";

const html = template.replace("/*DATA*/null", () => data).replace("__VOCALS__", () => vocals).replace("__BEAT__", () => beat);
writeFileSync(join(here, "..", "index.html"), html);
console.log(`index.html: ${(html.length / 1024 / 1024).toFixed(2)} MB`);
