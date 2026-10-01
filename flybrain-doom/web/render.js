// Doom-style renderer for the browser: raycast walls, floor and ceiling,
// billboard sprites, a pistol, and a status bar with a fly's face.
// All art is generated procedurally at startup.

const VIEW_W = 320, VIEW_H = 168, SCALE = 3, BAR_H = 32;
const FOV = 75 * Math.PI / 180;
const TAN = Math.tan(FOV / 2);
const PROJ = (VIEW_W / 2) / TAN;

const rgba = (r, g, b, a = 255) => ((a << 24) | (b << 16) | (g << 8) | r) >>> 0;
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

function seeded(seed) { let s = seed >>> 0; return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296); }

// ---------- textures (64x64, Uint32 RGBA) ----------
function makeTexture(kind) {
  const N = 64, t = new Uint32Array(N * N), r = seeded(kind.charCodeAt(0) * 977);
  const put = (x, y, c) => { t[(y & 63) * N + (x & 63)] = c; };
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const n = r() * 0.18 - 0.09;
    let R, G, B;
    if (kind === 'T') { // tech panel: grey plates, dark seams, rivets, a lit strip
      const seam = (x % 32 === 0) || (y % 16 === 0);
      const v = 0.55 + n + (y % 16 < 2 ? 0.08 : 0);
      R = G = B = seam ? 0.28 : v; B += 0.04;
      if ((x % 32 === 4 || x % 32 === 27) && (y % 16 === 4 || y % 16 === 11)) R = G = B = 0.85;
      if (y >= 40 && y < 44 && x > 8 && x < 56) { R = 0.9; G = 0.75; B = 0.35; }
    } else if (kind === 'B') { // brown stone bricks
      const row = Math.floor(y / 12), off = row % 2 ? 16 : 0;
      const mortar = y % 12 === 0 || (x + off) % 32 === 0;
      const v = 0.45 + n + Math.sin((x + row * 7) * 0.9) * 0.03;
      [R, G, B] = mortar ? [0.22, 0.17, 0.12] : [v * 1.05, v * 0.74, v * 0.5];
    } else if (kind === '#') { // steel pillar: vertical ribs
      const rib = Math.sin(x / 64 * Math.PI * 8);
      const v = 0.45 + rib * 0.12 + n * 0.6;
      [R, G, B] = [v * 0.92, v * 0.96, v * 1.08];
      if (y % 32 < 2) [R, G, B] = [0.2, 0.2, 0.24];
    } else if (kind === 'S') { // slime-streaked stone
      const v = 0.38 + n;
      [R, G, B] = [v * 0.9, v * 0.85, v * 0.65];
      const drip = Math.sin(x * 0.7) * 6 + 20 + (x % 7) * 3;
      if (y < drip && (x % 9 < 4)) [R, G, B] = [0.25, 0.55 + n, 0.18];
    } else if (kind === 'floor') { // grey-brown tiles with cracks
      const seam = x % 32 === 0 || y % 32 === 0;
      const v = 0.36 + n * 0.8;
      [R, G, B] = seam ? [0.2, 0.18, 0.16] : [v * 1.02, v * 0.95, v * 0.85];
    } else { // ceiling: dark panels with a light
      const seam = x % 16 === 0 || y % 16 === 0;
      const v = 0.26 + n * 0.5;
      [R, G, B] = seam ? [0.15, 0.15, 0.17] : [v, v, v * 1.1];
      if (x > 20 && x < 44 && y > 26 && y < 38) [R, G, B] = [0.95, 0.92, 0.8];
    }
    put(x, y, rgba(clamp(R * 255, 0, 255) | 0, clamp(G * 255, 0, 255) | 0, clamp(B * 255, 0, 255) | 0));
  }
  return t;
}

// ---------- sprites (drawn with canvas, read back as pixels) ----------
function spriteFrom(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d'); g.imageSmoothingEnabled = false;
  draw(g, w, h);
  const d = g.getImageData(0, 0, w, h);
  return { w, h, px: new Uint32Array(d.data.buffer.slice(0)) };
}
function drawImp(g, w, h, pose) {
  const body = '#7a4a2a', dark = '#4a2a16', light = '#a8703f';
  if (pose === 'dead') {
    g.fillStyle = '#6a1010'; g.fillRect(4, h - 10, w - 8, 8);
    g.fillStyle = body; g.fillRect(8, h - 14, w - 16, 7);
    g.fillStyle = '#ff3a1a'; g.fillRect(12, h - 12, 2, 2); g.fillRect(20, h - 12, 2, 2);
    return;
  }
  const cx = w / 2;
  // legs
  g.fillStyle = dark; g.fillRect(cx - 9, h - 18, 6, 18); g.fillRect(cx + 3, h - 18, 6, 18);
  // torso
  g.fillStyle = body; g.fillRect(cx - 11, h - 40, 22, 24);
  g.fillStyle = light; g.fillRect(cx - 7, h - 36, 14, 4); g.fillRect(cx - 6, h - 30, 12, 3);
  // spikes on shoulders
  g.fillStyle = '#d8c8a0';
  for (const sx of [-12, -8, 8, 12]) { g.beginPath(); g.moveTo(cx + sx - 2, h - 40); g.lineTo(cx + sx, h - 47); g.lineTo(cx + sx + 2, h - 40); g.fill(); }
  // head
  g.fillStyle = body; g.fillRect(cx - 7, h - 52, 14, 13);
  g.fillStyle = '#ff3a1a'; g.fillRect(cx - 5, h - 48, 3, 3); g.fillRect(cx + 2, h - 48, 3, 3);
  g.fillStyle = '#2a0a04'; g.fillRect(cx - 4, h - 43, 8, 2);
  // arms
  g.fillStyle = body;
  if (pose === 'attack') {
    g.fillRect(cx - 17, h - 56, 6, 20); g.fillRect(cx + 11, h - 56, 6, 20);
    const gr = g.createRadialGradient(cx, h - 58, 1, cx, h - 58, 8);
    gr.addColorStop(0, '#fff3b0'); gr.addColorStop(0.5, '#ff8a20'); gr.addColorStop(1, 'rgba(255,60,0,0)');
    g.fillStyle = gr; g.fillRect(cx - 9, h - 66, 18, 16);
  } else {
    g.fillRect(cx - 17, h - 40, 6, 20); g.fillRect(cx + 11, h - 40, 6, 20);
  }
  if (pose === 'pain') { g.fillStyle = 'rgba(255,40,40,0.45)'; g.fillRect(cx - 12, h - 52, 24, 52); }
}
function makeSprites() {
  const s = {};
  for (const pose of ['idle', 'attack', 'pain', 'dead']) s['imp_' + pose] = spriteFrom(40, 60, (g, w, h) => drawImp(g, w, h, pose));
  const orb = (c1, c2) => (g, w, h) => {
    const gr = g.createRadialGradient(w * 0.4, h * 0.38, 1, w / 2, h / 2, w / 2);
    gr.addColorStop(0, '#ffffff'); gr.addColorStop(0.25, c1); gr.addColorStop(0.8, c2); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.beginPath(); g.arc(w / 2, h / 2, w / 2 - 1, 0, 7); g.fill();
  };
  s.orb_blue = spriteFrom(24, 24, orb('#7fb0ff', '#1f3fd8'));
  s.orb_green = spriteFrom(24, 24, orb('#8dff9a', '#119a2a'));
  s.fireball = spriteFrom(20, 20, (g, w, h) => {
    const gr = g.createRadialGradient(w / 2, h / 2, 1, w / 2, h / 2, w / 2);
    gr.addColorStop(0, '#fffbd0'); gr.addColorStop(0.35, '#ffb030'); gr.addColorStop(0.7, '#e2401a'); gr.addColorStop(1, 'rgba(120,0,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
  });
  const burst = (cols) => (g, w, h) => {
    const r = seeded(cols.length * 31);
    for (let i = 0; i < 28; i++) { g.fillStyle = cols[i % cols.length]; const a = r() * 7, d = r() * w / 2; g.fillRect(w / 2 + Math.cos(a) * d - 1, h / 2 + Math.sin(a) * d - 1, 2, 2); }
  };
  s.puff = spriteFrom(10, 10, burst(['#d8d0c0', '#9a9488']));
  s.blood = spriteFrom(12, 12, burst(['#c01010', '#7a0606']));
  s.boom = spriteFrom(26, 26, burst(['#ffd040', '#ff7020', '#ffffff']));
  s.heal = spriteFrom(22, 22, burst(['#ffffff', '#ffe680', '#b8ffcc']));
  s.burn = spriteFrom(22, 22, burst(['#b6ff3a', '#3a8a10', '#ffffff']));
  return s;
}

// pistol, drawn at full resolution
function drawPistol(g, x, y, s, flash) {
  if (flash) {
    const gr = g.createRadialGradient(x, y - 40 * s, 2, x, y - 40 * s, 26 * s);
    gr.addColorStop(0, '#fffde0'); gr.addColorStop(0.4, '#ffc040'); gr.addColorStop(1, 'rgba(255,120,0,0)');
    g.fillStyle = gr; g.fillRect(x - 30 * s, y - 70 * s, 60 * s, 60 * s);
  }
  g.fillStyle = '#2b2b30'; g.fillRect(x - 6 * s, y - 40 * s, 12 * s, 26 * s);
  g.fillStyle = '#4a4a52'; g.fillRect(x - 5 * s, y - 40 * s, 3 * s, 24 * s);
  g.fillStyle = '#c99a72'; // hand
  g.fillRect(x - 12 * s, y - 16 * s, 24 * s, 16 * s);
  g.fillStyle = '#a77a55'; g.fillRect(x - 12 * s, y - 16 * s, 24 * s, 3 * s);
}

// The fly's face for the status bar. look: -1..1, hurt: 0..1, hp: 0..200
function drawFlyFace(g, cx, cy, s, look, hurt, hp) {
  g.save();
  g.translate(cx, cy);
  // antennae
  g.strokeStyle = '#3a2a1a'; g.lineWidth = 2 * s;
  g.beginPath(); g.moveTo(-4 * s, -12 * s); g.lineTo(-8 * s, -20 * s); g.moveTo(4 * s, -12 * s); g.lineTo(8 * s, -20 * s); g.stroke();
  // head capsule
  g.fillStyle = hp < 40 ? '#8a5a40' : '#a8784e';
  g.beginPath(); g.ellipse(0, 0, 16 * s, 14 * s, 0, 0, 7); g.fill();
  // compound eyes
  for (const side of [-1, 1]) {
    const ex = side * 10 * s + look * 2 * s;
    const gr = g.createRadialGradient(ex - 2 * s, -3 * s, 1, ex, 0, 10 * s);
    const c = hurt > 0.5 ? ['#ffd0d0', '#ff4040'] : ['#ff8070', '#a01810'];
    gr.addColorStop(0, c[0]); gr.addColorStop(1, c[1]);
    g.fillStyle = gr;
    g.beginPath(); g.ellipse(ex, 0, 9 * s, (hurt > 0.5 ? 7 : 11) * s, 0, 0, 7); g.fill();
    g.fillStyle = 'rgba(0,0,0,0.18)'; // ommatidia hint
    for (let i = -3; i <= 3; i++) for (let j = -4; j <= 4; j++) if ((i + j) % 2 === 0) g.fillRect(ex + i * 2.4 * s, j * 2.4 * s, 0.9 * s, 0.9 * s);
  }
  // mouthparts
  g.fillStyle = '#5a3a22'; g.fillRect(-3 * s, 9 * s, 6 * s, 6 * s);
  if (hp < 60) { g.fillStyle = '#b01010'; g.fillRect(-12 * s, 6 * s, 4 * s, 2 * s); g.fillRect(9 * s, -9 * s, 3 * s, 2 * s); }
  g.restore();
}

class Renderer {
  constructor(canvas) {
    this.cv = canvas;
    canvas.width = VIEW_W * SCALE;
    canvas.height = (VIEW_H + BAR_H) * SCALE;
    this.g = canvas.getContext('2d');
    this.view = document.createElement('canvas');
    this.view.width = VIEW_W; this.view.height = VIEW_H;
    this.vg = this.view.getContext('2d');
    this.img = this.vg.createImageData(VIEW_W, VIEW_H);
    this.px = new Uint32Array(this.img.data.buffer);
    this.z = new Float32Array(VIEW_W);
    this.tex = {};
    for (const k of ['T', 'B', '#', 'S', 'floor', 'ceil']) this.tex[k] = makeTexture(k);
    this.sprites = makeSprites();
    this.bob = 0;
  }

  shade(c, f) {
    const r = (c & 255) * f, g = ((c >> 8) & 255) * f, b = ((c >> 16) & 255) * f;
    return ((255 << 24) | ((b > 255 ? 255 : b) << 16) | ((g > 255 ? 255 : g) << 8) | (r > 255 ? 255 : r)) >>> 0;
  }

  draw(world, info = {}) {
    const p = world.player, px = this.px, W = VIEW_W, H = VIEW_H, half = H / 2;
    const dirX = Math.cos(p.angle), dirY = Math.sin(p.angle);
    const plX = Math.sin(p.angle) * TAN, plY = -Math.cos(p.angle) * TAN; // points left
    px.fill(0xff0a0a0a);
    // floor & ceiling
    const fl = this.tex.floor, ce = this.tex.ceil;
    const r0x = dirX + plX, r0y = dirY + plY, r1x = dirX - plX, r1y = dirY - plY;
    for (let y = half + 1; y < H; y++) {
      const rowDist = (0.5 * PROJ) / (y - half);
      const sx = rowDist * (r1x - r0x) / W, sy = rowDist * (r1y - r0y) / W;
      let fx = p.x + rowDist * r0x, fy = p.y + rowDist * r0y;
      const light = clamp(1.25 - rowDist / 11, 0.12, 1);
      const yc = H - 1 - y + 0; // mirrored ceiling row
      for (let x = 0; x < W; x++) {
        const tx = ((fx * 64) | 0) & 63, ty = ((fy * 64) | 0) & 63;
        px[y * W + x] = this.shade(fl[ty * 64 + tx], light);
        px[yc * W + x] = this.shade(ce[ty * 64 + tx], light * 0.9);
        fx += sx; fy += sy;
      }
    }
    // walls
    for (let x = 0; x < W; x++) {
      const k = 1 - 2 * (x + 0.5) / W;
      const rx = dirX + plX * k, ry = dirY + plY * k;
      let mx = Math.floor(p.x), my = Math.floor(p.y);
      const ddx = Math.abs(1 / rx), ddy = Math.abs(1 / ry);
      let stepX, stepY, sdx, sdy;
      if (rx < 0) { stepX = -1; sdx = (p.x - mx) * ddx; } else { stepX = 1; sdx = (mx + 1 - p.x) * ddx; }
      if (ry < 0) { stepY = -1; sdy = (p.y - my) * ddy; } else { stepY = 1; sdy = (my + 1 - p.y) * ddy; }
      let side = 0, cell = 0, dist = 30;
      for (let i = 0; i < 80; i++) {
        if (sdx < sdy) { dist = sdx; sdx += ddx; mx += stepX; side = 0; } else { dist = sdy; sdy += ddy; my += stepY; side = 1; }
        cell = world.cellAt(mx, my);
        if (cell) break;
      }
      this.z[x] = dist;
      let u = side === 0 ? p.y + dist * ry : p.x + dist * rx;
      u -= Math.floor(u);
      const t = this.tex[String.fromCharCode(cell)] || this.tex.T;
      const tx = (u * 64) | 0;
      const lineH = PROJ / dist;
      const top = half - lineH / 2;
      const y0 = Math.max(0, Math.floor(top)), y1 = Math.min(H, Math.ceil(top + lineH));
      const light = clamp(1.3 - dist / 12, 0.12, 1) * (side ? 0.8 : 1);
      for (let y = y0; y < y1; y++) {
        const ty = (((y - top) / lineH) * 64) & 63;
        px[y * W + x] = this.shade(t[ty * 64 + tx], light);
      }
    }
    // sprites
    const list = [];
    for (const e of world.entities) {
      let key, wz = 0, hgt;
      if (e.kind === 'imp') {
        if (!e.alive) { if (world.time - (e.diedAt ?? -9) > IMP_CORPSE) continue; key = 'imp_dead'; }
        else key = e.pain > 0 ? 'imp_pain' : world.time - e.attackAt < 0.35 ? 'imp_attack' : 'imp_idle';
        hgt = 0.95;
      } else if (e.kind === 'orb') { if (!e.alive) continue; key = 'orb_' + e.color; hgt = 0.32; wz = 0.18 + 0.05 * Math.sin(world.time * 3 + e.id); }
      else if (e.kind === 'fireball') { key = 'fireball'; hgt = 0.34; wz = 0.3; }
      list.push({ x: e.x, y: e.y, key, hgt, wz });
    }
    for (const f of world.fx) list.push({ x: f.x, y: f.y, key: f.kind, hgt: f.kind === 'boom' ? 0.6 : 0.3, wz: f.kind === 'boom' ? 0.2 : 0.35 });
    for (const s of list) {
      const dx = s.x - p.x, dy = s.y - p.y;
      s.f = dx * dirX + dy * dirY;
      s.l = dx * Math.sin(p.angle) - dy * Math.cos(p.angle);
    }
    list.sort((a, b) => b.f - a.f);
    for (const s of list) {
      if (s.f < 0.15) continue;
      const spr = this.sprites[s.key];
      if (!spr) continue;
      const sxc = W / 2 - (s.l / s.f) * PROJ;
      const sh = (s.hgt / s.f) * PROJ, sw = sh * spr.w / spr.h;
      const floorY = half + (0.5 / s.f) * PROJ;
      const bottom = floorY - (s.wz / s.f) * PROJ;
      const top = bottom - sh, left = sxc - sw / 2;
      const x0 = Math.max(0, Math.floor(left)), x1 = Math.min(W, Math.ceil(left + sw));
      const y0 = Math.max(0, Math.floor(top)), y1 = Math.min(H, Math.ceil(bottom));
      const light = s.key.startsWith('orb') || s.key === 'fireball' || s.key === 'boom' || s.key === 'heal' || s.key === 'burn' ? 1 : clamp(1.3 - s.f / 12, 0.15, 1);
      for (let x = x0; x < x1; x++) {
        if (this.z[x] < s.f) continue;
        const tx = (((x - left) / sw) * spr.w) | 0;
        for (let y = y0; y < y1; y++) {
          const ty = (((y - top) / sh) * spr.h) | 0;
          const c = spr.px[ty * spr.w + tx];
          if ((c >>> 24) < 128) continue;
          px[y * W + x] = this.shade(c, light);
        }
      }
    }
    this.vg.putImageData(this.img, 0, 0);

    // compose at full resolution
    const g = this.g, S = SCALE;
    g.imageSmoothingEnabled = false;
    g.drawImage(this.view, 0, 0, W * S, H * S);
    // pistol with bob
    const speed = Math.hypot(p.vx, p.vy);
    this.bob += speed * 0.05;
    const flash = world.lastShot && world.time - world.lastShot.t < 0.09;
    drawPistol(g, W * S / 2 + Math.sin(this.bob) * 10, H * S + Math.abs(Math.cos(this.bob)) * 8 + 6, 2.4, flash);
    // damage / heal tint
    const sinceHurt = world.time - p.hurtAt, sinceHeal = world.time - p.healAt;
    if (p.hurtAt >= 0 && sinceHurt < 0.35) { g.fillStyle = `rgba(200,20,10,${0.4 * (1 - sinceHurt / 0.35)})`; g.fillRect(0, 0, W * S, H * S); }
    if (p.healAt >= 0 && sinceHeal < 0.35) { g.fillStyle = `rgba(255,230,120,${0.25 * (1 - sinceHeal / 0.35)})`; g.fillRect(0, 0, W * S, H * S); }
    if (!p.alive) { g.fillStyle = 'rgba(120,0,0,0.45)'; g.fillRect(0, 0, W * S, H * S); }
    if (info.banner) {
      g.fillStyle = 'rgba(10,8,6,0.72)'; g.fillRect(0, H * S / 2 - 34, W * S, 68);
      g.fillStyle = '#f3e6cf'; g.font = `700 34px ${FONT_DISPLAY}`; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(info.banner, W * S / 2, H * S / 2 + 2);
    }
    this.drawBar(world, info);
  }

  drawBar(world, info) {
    const g = this.g, S = SCALE, W = VIEW_W * S, y0 = VIEW_H * S, h = BAR_H * S, p = world.player;
    g.fillStyle = '#3a342d'; g.fillRect(0, y0, W, h);
    g.fillStyle = '#2a2520'; for (let i = 0; i < W; i += 6) g.fillRect(i, y0 + ((i * 7) % 11), 3, 2);
    g.fillStyle = '#5a5146'; g.fillRect(0, y0, W, 3);
    const cells = [
      { label: 'HEALTH', value: String(Math.max(0, Math.round(p.health))), w: 190 },
      { label: 'AMMO', value: String(p.ammo), w: 150 },
      { label: 'FACE', w: 140 },
      { label: 'KILLS', value: String(world.stats.kills), w: 130 },
      { label: 'ORBS +/−', value: `${world.stats.good}/${world.stats.bad}`, w: 190 },
      { label: 'TIME', value: (world.duration - world.time).toFixed(0), w: W - 800 },
    ];
    let x = 0;
    g.textAlign = 'center';
    for (const c of cells) {
      g.fillStyle = '#26211c'; g.fillRect(x + 4, y0 + 8, c.w - 8, h - 14);
      if (c.label === 'FACE') {
        const hurt = p.hurtAt >= 0 ? clamp(1 - (world.time - p.hurtAt) / 0.5, 0, 1) : 0;
        drawFlyFace(g, x + c.w / 2, y0 + h / 2 + 6, 2.2, clamp(info.turn || 0, -1, 1), hurt, p.health);
      } else {
        g.fillStyle = '#d23a20'; g.font = `800 46px ${FONT_DISPLAY}`; g.textBaseline = 'alphabetic';
        g.fillText(c.value, x + c.w / 2, y0 + h - 30);
        g.fillStyle = '#c9b89c'; g.font = `600 15px ${FONT_BODY}`;
        g.fillText(c.label, x + c.w / 2, y0 + h - 12);
      }
      x += c.w;
    }
  }
}

const IMP_CORPSE = 2.5;
const FONT_DISPLAY = '"Big Shoulders Display", Impact, "Arial Narrow", sans-serif';
const FONT_BODY = '"Libre Franklin", "Segoe UI", system-ui, sans-serif';

// Compound-eye mosaic: 32 columns of hexagonal facets coloured by what each
// ommatidial column sees. Left eye on the left (130° → -10°), right eye on the right.
function drawEyes(canvas, optics) {
  const g = canvas.getContext('2d'), W = canvas.width, H = canvas.height;
  g.fillStyle = '#100d0b'; g.fillRect(0, 0, W, H);
  if (!optics) return;
  const n = optics.view.rgb[0].length / 3, rows = 7, gap = 18;
  const colW = (W - gap) / (2 * n), r = Math.min(colW * 0.56, (H - 8) / (rows * 1.7));
  for (let s = 0; s < 2; s++) {
    const rgb = optics.view.rgb[s];
    for (let i = 0; i < n; i++) {
      // left eye drawn far-left = most lateral (column n-1); right eye mirrored
      const c = s === 0 ? n - 1 - i : i;
      const cx = (s === 0 ? 0 : (W + gap) / 2) + (i + 0.5) * colW;
      const R = rgb[c * 3] * 255, G = rgb[c * 3 + 1] * 255, B = rgb[c * 3 + 2] * 255;
      for (let j = 0; j < rows; j++) {
        const cy = 6 + r + j * r * 1.65 + (i % 2) * r * 0.82;
        if (cy + r > H) continue;
        const f = 0.75 + 0.25 * Math.sin(j * 1.3 + i);
        g.fillStyle = `rgb(${(R * f) | 0},${(G * f) | 0},${(B * f) | 0})`;
        g.beginPath();
        for (let k = 0; k < 6; k++) { const a = Math.PI / 6 + k * Math.PI / 3; g.lineTo(cx + Math.cos(a) * r * 0.92, cy + Math.sin(a) * r * 0.92); }
        g.fill();
      }
    }
  }
}
