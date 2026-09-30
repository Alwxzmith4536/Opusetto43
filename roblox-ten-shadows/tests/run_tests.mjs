// Offline checks (no Roblox Studio needed):
//   1. every .luau file compiles with the real Luau compiler (luau-web, WASM build of Luau)
//   2. unit tests for DamageRules + Adaptation (tests/unit.luau)
//   3. cross-reference checks: hotbar keys, damage types, model names, FX names
// Run:  cd tests && npm install && npm test
import { LuauState } from "luau-web";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(ROOT, "src");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");
let failures = 0;
const fail = (msg) => { failures++; console.log("  FAIL  " + msg); };

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : e.name.endsWith(".luau") ? [path.join(dir, e.name)] : []);
}

// ------------------------------------------------------------------ 1. compile
console.log("compile:");
const state = await LuauState.createAsync({ print: (...args) => console.log(args.join("\t")) });
const files = walk(SRC);
for (const f of files) {
  const r = state.loadstring(fs.readFileSync(f, "utf8"), path.relative(ROOT, f), false);
  if (typeof r === "string") fail(`${path.relative(ROOT, f)}: ${r}`);
  else console.log("  ok    " + path.relative(ROOT, f));
}

// ------------------------------------------------------------------ 2. unit tests
console.log("\nunit tests:");
const stubs = `
local Color3 = { fromRGB = function(r, g, b) return { r, g, b } end, new = function(r, g, b) return { r, g, b } end }
local Vector3 = { new = function(x, y, z) return { x, y, z } end }
`;
const mod = (name) => `local ${name} = (function()\n${read(`src/ReplicatedStorage/TenShadows/${name}.luau`)}\nend)()\n`;
const chunk = stubs + mod("Config") + mod("DamageRules") + mod("Adaptation") + read("tests/unit.luau");
try {
  const fn = state.loadstring(chunk, "unit", true);
  await fn();
} catch (e) {
  fail("unit tests: " + e.message);
}

// ------------------------------------------------------------------ 3. cross references
console.log("\ncross references:");
const config = read("src/ReplicatedStorage/TenShadows/Config.luau");
const vfx = read("src/ReplicatedStorage/TenShadows/VFX.luau");
const server = files.filter((f) => f.includes("ServerScriptService")).map((f) => fs.readFileSync(f, "utf8")).join("\n");
const client = read("src/StarterPlayer/StarterPlayerScripts/TenShadowsClient.client.luau");
const models = JSON.parse(read("assets/models.json"));

const keys = [...config.matchAll(/Key = "(\w+)"/g)].map((m) => m[1]);
const dupKeys = keys.filter((k, i) => keys.indexOf(k) !== i);
dupKeys.length ? fail("duplicate keys: " + dupKeys) : console.log(`  ok    ${keys.length} key bindings, no duplicates`);

const damageTypes = new Set([...config.matchAll(/^\t(\w+) = \{ Color = /gm)].map((m) => m[1]));
const usedTypes = new Set([...config.matchAll(/DamageType = "(\w+)"/g)].map((m) => m[1]));
for (const m of server.matchAll(/Combat\.Damage\(\w+, [^,\n]+, "(\w+)"/g)) usedTypes.add(m[1]);
const missingTypes = [...usedTypes].filter((t) => !damageTypes.has(t));
missingTypes.length ? fail("unknown damage types: " + missingTypes) : console.log(`  ok    ${usedTypes.size} damage types all defined`);

const order = [...config.match(/AbilityOrder = \{([^}]*)\}/)[1].matchAll(/"(\w+)"/g)].map((m) => m[1]);
const handlers = new Set([...server.matchAll(/function H\.(\w+)\(/g)].map((m) => m[1]));
const noHandler = order.filter((a) => !handlers.has(a));
noHandler.length ? fail("hotbar abilities without a server handler: " + noHandler) : console.log(`  ok    ${order.length} hotbar abilities all have server handlers`);

const modelRefs = new Set();
for (const src of [vfx, server]) {
  for (const m of src.matchAll(/(?:emerge|Build|strikeFromShadow|Height)\(\s*"(\w+)"/g)) modelRefs.add(m[1]);
  for (const m of src.matchAll(/Name = "(DivineDog\w+)"/g)) modelRefs.add(m[1]);
}
const missingModels = [...modelRefs].filter((m) => !models[m]);
missingModels.length ? fail("unknown models: " + missingModels) : console.log(`  ok    ${modelRefs.size} model references all exist in models.json`);

const effects = new Set([...vfx.matchAll(/function E\.(\w+)\(/g)].map((m) => m[1]));
const uiHandlers = new Set([...client.matchAll(/function UI\.(\w+)\(/g)].map((m) => m[1]));
const fired = new Set([...server.matchAll(/Combat\.FX(?:To)?\((?:[^,()]+,\s*)?"(\w+)"/g)].map((m) => m[1]));
const unhandled = [...fired].filter((f) => !effects.has(f) && !uiHandlers.has(f));
unhandled.length ? fail("FX fired by the server with no client handler: " + unhandled) : console.log(`  ok    ${fired.size} FX/UI events fired by the server, all handled on the client`);

console.log(failures ? `\n${failures} check(s) FAILED` : "\nall checks passed");
process.exit(failures ? 1 : 0);
