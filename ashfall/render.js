// render.js — draws one frame of ASHFALL at output time o (story time s = warp(o)). Canvas 2D only.
(function (root) {
'use strict';
const C = root.CORE, SIM = root.SIM;
const { clamp, lerp, smooth, rng, hash, vnoise, BODY, D2R, toWorld } = C;
const W = 1280, H = 720, HZ = 130, BAR = 46;
const FONT = '"DejaVu Sans","FreeSans",Arial,sans-serif';
const SCARF = { G: '#17a049', B: '#2159c9', Y: '#e0a800' };
const RIM = { G: '#0d8f38', B: '#1260cf', Y: '#cc9300' };
const PAL = { skyTop: '#ffffff', skyMid: '#ffffff', skyLow: '#f6f4ef' };

// ------------------------------------------------------------------ static scenery (seeded)
function genSkyline(seed, x0, x1, hmin, hmax, wmin, wmax, gap) {
  const R = rng(seed), out = []; let x = x0;
  while (x < x1) {
    const w = wmin + R() * (wmax - wmin), h = hmin + Math.pow(R(), 1.6) * (hmax - hmin);
    const kind = R();
    const pts = [[0, 0]];
    const steps = 3 + Math.floor(R() * 4);
    let top = h;
    pts.push([0, top * (0.55 + R() * 0.45)]);
    for (let i = 1; i <= steps; i++) {
      const px = w * i / steps;
      let ty = h * (0.45 + R() * 0.55); if (kind < 0.25) ty = h * (0.75 + R() * 0.25);
      pts.push([px - w / steps * 0.5 * R(), ty]); pts.push([px, ty * (0.7 + R() * 0.3)]);
    }
    pts.push([w, 0]);
    out.push({ x, w, h, pts, ant: R() < 0.3 ? 20 + R() * 50 : 0, lean: (R() - 0.5) * 0.12 });
    x += w * (0.55 + R() * 0.5) + (R() < 0.25 ? gap * R() : 0);
  }
  return out;
}
const SKY = [
  { f: 0.06, col: '#e9e6e0', haze: 0.55, list: genSkyline(11, -2600, 2600, 40, 150, 26, 70, 40), base: HZ - 4 },
  { f: 0.14, col: '#d6d2c9', haze: 0.42, list: genSkyline(23, -2600, 2600, 60, 210, 34, 90, 120), base: HZ - 6 },
  { f: 0.27, col: '#bcb7ad', haze: 0.30, list: genSkyline(37, -2800, 2800, 70, 250, 50, 120, 380), base: HZ - 10 },
];
const NEAR_RUINS = genSkyline(51, -2600, 2600, 50, 190, 60, 150, 650);
const PLUMES = [{ x: -900, f: 0.04, h: 330, s: 1.0, sd: 3 }, { x: 1000, f: 0.05, h: 380, s: 1.1, sd: 7 }, { x: 420, f: 0.04, h: 230, s: 0.7, sd: 9 }];
const FG = [];
{ const R = rng(77); let x = -2300; while (x < 2300) { const h = 30 + Math.pow(R(), 2.2) * 230, w = 14 + R() * 46; FG.push({ x, w, h, lean: (R() - 0.5) * 0.7, kind: R() < 0.35 ? 1 : 0, pts: Array.from({ length: 5 }, () => R()) }); x += 240 + R() * 520; } }
const ROCKS = [];
{ const R = rng(5); for (let i = 0; i < 90; i++) ROCKS.push({ x: -1500 + R() * 3000, y: -110 + R() * 190, r: 4 + R() * 16, k: R() }); }
const CRATERS = [{ x: -380, y: -30, rx: 190, ry: 26 }, { x: 140, y: -70, rx: 260, ry: 34 }, { x: 700, y: -20, rx: 160, ry: 22 }, { x: -980, y: -40, rx: 220, ry: 30 }];
const BEAMS = [{ x: -640, y: 20, len: 200, a: 18 }, { x: 330, y: 44, len: 150, a: -24 }, { x: 860, y: -10, len: 230, a: 12 }, { x: -120, y: 62, len: 120, a: 40 }];
const FLAKES = [];
{ const R = rng(1234); for (let l = 0; l < 3; l++) { const n = [170, 110, 34][l]; for (let i = 0; i < n; i++) FLAKES.push({ l, u: R(), v: R(), r: [1.1, 2.0, 5.5][l] * (0.6 + R() * 0.8), ph: R() * 6.28, sp: 0.6 + R() * 0.8 }); } }

function createRenderer(canvas, S) {
  S = S || 1;
  canvas.width = W * S; canvas.height = H * S;
  const out = canvas.getContext('2d');
  const mk = () => { const c = document.createElement('canvas'); c.width = W * S; c.height = H * S; return c; };
  const sceneC = mk(), accC = mk();
  const sx = sceneC.getContext('2d'), ax = accC.getContext('2d');
  // vignette
  const vigC = mk(); { const g = vigC.getContext('2d'); g.scale(S, S); const rg = g.createRadialGradient(W / 2, H / 2, H * 0.32, W / 2, H / 2, H * 1.0); rg.addColorStop(0, 'rgba(30,22,12,0)'); rg.addColorStop(1, 'rgba(30,22,12,0.26)'); g.fillStyle = rg; g.fillRect(0, 0, W, H); }

  // ---------------------------------------------------------------- scene
  function scene(ctx, s, o, sc0, oc0) {
    // camera + shake are evaluated at the frame's centre time so the background stays crisp; actors/FX use the sub-sample time
    const cam = SIM.camAt(sc0);
    const [shx, shy, zp] = SIM.shakeAt(sc0, oc0);
    cam.zoom *= 1 + zp; const zoom = cam.zoom;
    ctx.setTransform(S, 0, 0, S, 0, 0);
    ctx.save();
    const rz = 1 + Math.abs(cam.roll) * 0.02;
    ctx.translate(W / 2 + shx, H / 2 + shy); ctx.rotate(cam.roll * D2R); ctx.scale(rz, rz); ctx.translate(-W / 2, -H / 2);
    const X = (wx, f) => W / 2 + zoom * (wx - cam.x * (f === undefined ? 1 : f));
    const Y = wy => H / 2 - zoom * (wy - cam.y);
    const hy = Y(HZ);
    const env = { cam, zoom, X, Y, hy, s, o };

    // sky
    let g = ctx.createLinearGradient(0, Math.min(0, hy - 400), 0, hy);
    g.addColorStop(0, PAL.skyTop); g.addColorStop(0.55, PAL.skyMid); g.addColorStop(1, PAL.skyLow);
    ctx.fillStyle = g; ctx.fillRect(-60, -60, W + 120, Math.max(hy, 0) + 60 + 4);
    drawPlumes(ctx, env);
    // horizon glow
    g = ctx.createLinearGradient(0, hy - 150 * zoom, 0, hy);
    g.addColorStop(0, 'rgba(240,190,140,0)'); g.addColorStop(1, 'rgba(240,176,120,0.14)');
    ctx.fillStyle = g; ctx.fillRect(-60, hy - 150 * zoom, W + 120, 150 * zoom + 2);
    // skyline layers
    for (const L of SKY) { drawSkyline(ctx, env, L); }
    drawShip(ctx, env);
    drawWalker(ctx, env);
    drawGround(ctx, env);
    drawSetPieces(ctx, env, true);
    // fighters + fx
    drawActors(ctx, env);
    drawFX(ctx, env);
    drawForeground(ctx, env);
    drawFlakes(ctx, env);
    ctx.restore();
  }

  function drawPlumes(ctx, e) {
    const { X, Y, zoom, s } = e;
    for (const P of PLUMES) {
      for (let i = 0; i < 16; i++) {
        const u = i / 15, r = (34 + u * 120) * P.s * zoom;
        const drift = Math.sin(s * 0.18 + P.sd + u * 3) * 24 * u + u * u * 140 * P.s;
        const px = X(P.x + drift, P.f), py = Y(HZ + u * P.h * P.s * 0.9 - 10);
        const a = 0.07 * (1 - u * 0.5);
        const rg = ctx.createRadialGradient(px, py, 0, px, py, r);
        rg.addColorStop(0, `rgba(78,70,62,${a})`); rg.addColorStop(1, 'rgba(78,70,62,0)');
        ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, r * 2, r * 2);
      }
    }
  }
  function poly(ctx, pts, ox, oy, e, f, sc, lean) {
    ctx.beginPath();
    for (let i = 0; i < pts.length; i++) {
      let px = pts[i][0] * sc, py = pts[i][1] * sc;
      if (lean) px += py * lean;
      const X = e.X(ox + px / 1, f), Y = e.Y(oy + py);
      // zoom is applied through X/Y relative to world units; scale 'sc' keeps shapes in world units
      i ? ctx.lineTo(X, Y) : ctx.moveTo(X, Y);
    }
    ctx.closePath();
  }
  function drawSkyline(ctx, e, L) {
    ctx.fillStyle = L.col;
    const view = 900 / e.zoom + 200;
    const cx = e.cam.x * L.f;
    for (const b of L.list) {
      if (b.x + b.w < cx - view || b.x > cx + view) continue;
      poly(ctx, b.pts, b.x, L.base, e, L.f, 1, b.lean); ctx.fill();
      if (b.ant) { ctx.strokeStyle = L.col; ctx.lineWidth = 2 * e.zoom; ctx.beginPath(); ctx.moveTo(e.X(b.x + b.w * 0.5, L.f), e.Y(L.base + b.h)); ctx.lineTo(e.X(b.x + b.w * 0.5, L.f), e.Y(L.base + b.h + b.ant)); ctx.stroke(); }
    }
    // atmospheric haze over the base of this layer
    const g = ctx.createLinearGradient(0, e.Y(HZ + 230), 0, e.Y(HZ - 8));
    g.addColorStop(0, 'rgba(250,249,246,0)'); g.addColorStop(1, `rgba(247,245,240,${L.haze})`);
    ctx.fillStyle = g; ctx.fillRect(-60, e.Y(HZ + 230), W + 120, e.Y(HZ - 8) - e.Y(HZ + 230));
  }
  function drawShip(ctx, e) {
    const f = 0.32, ox = 380, oy = HZ - 14;
    const T = (px, py) => { const a = -9 * D2R, c = Math.cos(a), s2 = Math.sin(a); return [e.X(ox + px * c - py * s2, f), e.Y(oy + px * s2 + py * c)]; };
    const hull = [[-560, -4], [-540, 20], [-420, 36], [-60, 72], [250, 100], [430, 108], [470, 70], [446, 30], [468, -4]];
    const tower = [[230, 96], [246, 168], [272, 172], [284, 214], [318, 216], [326, 176], [356, 172], [366, 100]];
    ctx.fillStyle = '#c9c5bc';
    for (const P of [hull, tower]) { ctx.beginPath(); P.forEach((p, i) => { const t = T(p[0], p[1]); i ? ctx.lineTo(t[0], t[1]) : ctx.moveTo(t[0], t[1]); }); ctx.closePath(); ctx.fill(); }
    // broken ribs & panel lines
    ctx.strokeStyle = 'rgba(90,84,76,0.45)'; ctx.lineWidth = 2 * e.zoom;
    for (let i = 0; i < 14; i++) { const x = -640 + i * 80, a = T(x, 16 + (i % 3) * 6), b = T(x + 50, 62 + i * 2.4); ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); }
    ctx.fillStyle = 'rgba(90,84,76,0.55)';
    for (let i = 0; i < 9; i++) { const t = T(260 + (i % 3) * 20, 120 + Math.floor(i / 3) * 14); ctx.fillRect(t[0], t[1], 10 * e.zoom, 4 * e.zoom); }
    // glowing fires in the wreck
    for (let i = 0; i < 4; i++) {
      const t = T(-420 + i * 260, 40 + i * 12), r = (40 + 10 * Math.sin(e.s * 5 + i)) * e.zoom;
      const rg = ctx.createRadialGradient(t[0], t[1], 0, t[0], t[1], r); rg.addColorStop(0, 'rgba(255,170,70,0.55)'); rg.addColorStop(1, 'rgba(255,120,40,0)');
      ctx.fillStyle = rg; ctx.fillRect(t[0] - r, t[1] - r, r * 2, r * 2);
    }
    const g = ctx.createLinearGradient(0, e.Y(HZ + 120), 0, e.Y(HZ - 10)); g.addColorStop(0, 'rgba(250,249,246,0)'); g.addColorStop(1, 'rgba(246,244,238,0.4)');
    ctx.fillStyle = g; ctx.fillRect(-60, e.Y(HZ + 120), W + 120, e.Y(HZ - 10) - e.Y(HZ + 120));
  }
  function drawWalker(ctx, e) {
    const f = 0.5, ox = -430, oy = HZ - 22, z = e.zoom;
    const P = (px, py) => [e.X(ox + px, f), e.Y(oy + py)];
    ctx.fillStyle = '#c1bdb4'; ctx.strokeStyle = '#c1bdb4'; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const body = [[-60, 100], [60, 100], [66, 140], [-50, 150], [-70, 128]], head = [[60, 124], [138, 116], [150, 134], [136, 150], [64, 150]];
    for (const q of [body, head]) { ctx.beginPath(); q.forEach((p, i) => { const t = P(p[0], p[1]); i ? ctx.lineTo(t[0], t[1]) : ctx.moveTo(t[0], t[1]); }); ctx.closePath(); ctx.fill(); }
    const legs = [[[-40, 100], [-52, 54], [-62, 0]], [[-20, 100], [-8, 52], [-2, 0]], [[34, 100], [58, 56], [90, 0]], [[52, 100], [84, 54], [132, 14]]];
    ctx.lineWidth = 15 * z;
    for (const l of legs) { ctx.beginPath(); l.forEach((p, i) => { const t = P(p[0], p[1]); i ? ctx.lineTo(t[0], t[1]) : ctx.moveTo(t[0], t[1]); }); ctx.stroke(); }
    // dangling cable
    ctx.lineWidth = 3 * z; ctx.beginPath(); let t = P(-70, 128); ctx.moveTo(t[0], t[1]); t = P(-120, 70); ctx.quadraticCurveTo(t[0], t[1], ...P(-110, 20)); ctx.stroke();
    const g = ctx.createLinearGradient(0, e.Y(HZ + 100), 0, e.Y(HZ - 24)); g.addColorStop(0, 'rgba(248,246,242,0)'); g.addColorStop(1, 'rgba(244,241,235,0.3)');
    ctx.fillStyle = g; ctx.fillRect(-60, e.Y(HZ + 100), W + 120, e.Y(HZ - 24) - e.Y(HZ + 100));
  }

  function ridge(ctx, e, f, base, amp, k1, k2, ph, c0, c1) {
    const step = 28; ctx.beginPath();
    const x0 = e.cam.x * f - 900 / e.zoom - 80, x1 = e.cam.x * f + 900 / e.zoom + 80;
    ctx.moveTo(e.X(x0, f), H + 80);
    for (let x = Math.floor(x0 / step) * step; x <= x1; x += step) {
      const y = base + amp * Math.sin(x * k1 + ph) + amp * 0.5 * Math.sin(x * k2 + ph * 2.1);
      ctx.lineTo(e.X(x, f), e.Y(y));
    }
    ctx.lineTo(e.X(x1, f), H + 80); ctx.closePath();
    const g = ctx.createLinearGradient(0, e.Y(base + amp), 0, e.Y(base - 160));
    g.addColorStop(0, c0); g.addColorStop(1, c1); ctx.fillStyle = g; ctx.fill();
  }
  function drawGround(ctx, e) {
    const { X, Y, zoom } = e;
    let g = ctx.createLinearGradient(0, e.hy, 0, Y(-330));
    g.addColorStop(0, '#b4aea3'); g.addColorStop(0.14, '#8f897f'); g.addColorStop(0.5, '#59554e'); g.addColorStop(1, '#2b2825');
    ctx.fillStyle = g; ctx.fillRect(-60, e.hy, W + 120, H - e.hy + 80);
    // near ruins sitting on the plain
    ctx.fillStyle = '#8c867c';
    const cx = e.cam.x * 0.55, view = 900 / zoom + 200;
    for (const b of NEAR_RUINS) { if (b.x + b.w < cx - view || b.x > cx + view) continue; poly(ctx, b.pts, b.x, HZ - 30, e, 0.55, 1.0, b.lean); ctx.fill(); }
    const hz = ctx.createLinearGradient(0, Y(HZ + 90), 0, Y(HZ - 40)); hz.addColorStop(0, 'rgba(214,208,196,0)'); hz.addColorStop(1, 'rgba(214,208,196,0.30)');
    ctx.fillStyle = hz; ctx.fillRect(-60, Y(HZ + 90), W + 120, Y(HZ - 40) - Y(HZ + 90));
    ridge(ctx, e, 0.45, 96, 12, 0.0042, 0.011, 0.6, '#9d978c', '#7d776d');
    ridge(ctx, e, 0.65, 70, 14, 0.0036, 0.0095, 2.2, '#8a847a', '#6b655d');
    ridge(ctx, e, 0.85, 44, 12, 0.0045, 0.012, 4.1, '#77716a', '#55504a');
    // arena floor details
    for (const c of CRATERS) {
      const px = X(c.x), py = Y(c.y - 30);
      ctx.fillStyle = 'rgba(40,36,32,0.22)'; ctx.beginPath(); ctx.ellipse(px, py, c.rx * zoom, c.ry * zoom, 0, 0, 7); ctx.fill();
      ctx.strokeStyle = 'rgba(210,204,194,0.35)'; ctx.lineWidth = 3 * zoom; ctx.beginPath(); ctx.ellipse(px, py - 2 * zoom, c.rx * zoom, c.ry * zoom, 0, Math.PI * 1.05, Math.PI * 1.95); ctx.stroke();
    }
    for (const r of ROCKS) {
      const px = X(r.x), py = Y(r.y - 40); if (px < -40 || px > W + 40) continue;
      ctx.fillStyle = r.k < 0.5 ? '#46423d' : '#5e5a53';
      ctx.beginPath(); ctx.ellipse(px, py, r.r * 1.5 * zoom, r.r * 0.7 * zoom, 0, 0, 7); ctx.fill();
      ctx.fillStyle = 'rgba(210,204,194,0.25)'; ctx.beginPath(); ctx.ellipse(px - r.r * 0.3 * zoom, py - r.r * 0.25 * zoom, r.r * 0.8 * zoom, r.r * 0.3 * zoom, 0, 0, 7); ctx.fill();
    }
    ctx.strokeStyle = '#2c2926'; ctx.lineCap = 'round';
    for (const b of BEAMS) {
      const a = b.a * D2R, px = X(b.x), py = Y(b.y - 40);
      ctx.lineWidth = 11 * zoom; ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px + Math.cos(a) * b.len * zoom, py - Math.sin(a) * b.len * zoom); ctx.stroke();
      ctx.lineWidth = 4 * zoom; ctx.strokeStyle = '#4c4843'; ctx.beginPath(); ctx.moveTo(px, py - 4 * zoom); ctx.lineTo(px + Math.cos(a) * b.len * zoom * 0.9, py - 4 * zoom - Math.sin(a) * b.len * zoom * 0.9); ctx.stroke(); ctx.strokeStyle = '#2c2926';
    }
    // wind-blown ash streaks on the floor
    ctx.strokeStyle = 'rgba(205,198,186,0.10)'; ctx.lineWidth = 2 * zoom;
    for (let i = 0; i < 26; i++) {
      const wx = ((i * 197 + 40) % 2400) - 1200, wy = -90 + (i * 53) % 150;
      const px = X(wx + 40 * Math.sin(e.s * 0.3 + i)), py = Y(wy);
      ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px + (60 + (i % 5) * 30) * zoom, py); ctx.stroke();
    }
  }

  // collapsible column + standing arch (set pieces on the arena)
  function drawSetPieces(ctx, e, behind) {
    const { X, Y, zoom, s } = e;
    for (const sp of (SIM.setpieces || [])) {
      const gy = C.groundY(sp.z), sc = C.depthScale(sp.z);
      let ang = 0, fallen = false, t0 = sp.topple;
      if (t0 !== undefined && s >= t0) { const u = clamp((s - t0) / 1.05, 0, 1); ang = sp.dir * 84 * (u * u * u); fallen = u >= 1; }
      const bx = X(sp.x), by = Y(gy - 40 * 0);
      ctx.save(); ctx.translate(bx, by + 40 * zoom * 0); ctx.rotate(ang * D2R * 1);
      const w = sp.w * sc * zoom, h = sp.h * sc * zoom;
      const col = sp.col || '#4b4741';
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.moveTo(-w * 0.62, 0); ctx.lineTo(-w * 0.5, -h * 0.08); ctx.lineTo(-w * 0.42, -h * 0.7); ctx.lineTo(-w * 0.5, -h * 0.84); ctx.lineTo(-w * 0.18, -h * 0.9); ctx.lineTo(w * 0.05, -h * 0.99); ctx.lineTo(w * 0.22, -h * 0.86); ctx.lineTo(w * 0.46, -h * 0.92); ctx.lineTo(w * 0.42, -h * 0.08); ctx.lineTo(w * 0.62, 0); ctx.closePath(); ctx.fill();
      ctx.fillStyle = 'rgba(214,208,198,0.2)'; ctx.fillRect(-w * 0.42, -h * 0.84, w * 0.2, h * 0.76);
      ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(w * 0.18, -h * 0.9, w * 0.24, h * 0.82);
      ctx.strokeStyle = 'rgba(20,18,16,0.55)'; ctx.lineWidth = 2 * zoom;
      for (let i = 1; i < 5; i++) { ctx.beginPath(); ctx.moveTo(-w * 0.43, -h * i / 5.2); ctx.lineTo(w * 0.43, -h * i / 5.2 + (i % 2 ? 4 : -3) * zoom); ctx.stroke(); }
      ctx.fillStyle = col; ctx.fillRect(-w * 0.64, -h * 0.06, w * 1.28, h * 0.06);
      ctx.restore();
    }
  }

  // ---------------------------------------------------------------- actors
  function limb(ctx, e, st, pts, w, col) {
    ctx.strokeStyle = col; ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.beginPath();
    for (let i = 0; i < pts.length; i++) { const p = toWorld(st, pts[i]); const x = e.X(p[0]), y = e.Y(p[1]); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
    ctx.stroke();
  }
  function drawBody(ctx, e, st, name, alpha, tint) {
    const sk = st.sk, z = e.zoom * st.sc, lw = 9.5 * z, ol = lw + 5.5 * z;
    const col = tint || SIM.colors[name].body;
    ctx.globalAlpha = alpha === undefined ? 1 : alpha;
    const parts = () => [
      [[sk.S, sk.e2, sk.hand2]], [[[0, 0], sk.k2, sk.foot2]], [[[0, 0], sk.N]], [[[0, 0], sk.k1, sk.foot1]], [[sk.S, sk.e1, sk.hand1]],
    ];
    const hp = toWorld(st, sk.head), hx = e.X(hp[0]), hyy = e.Y(hp[1]);
    // outline pass
    for (const grp of parts()) limb(ctx, e, st, grp[0], ol, '#14110f');
    ctx.fillStyle = '#14110f'; ctx.beginPath(); ctx.arc(hx, hyy, BODY.head * z + 2.8 * z, 0, 7); ctx.fill();
    // colour pass (back arm slightly darker)
    limb(ctx, e, st, [sk.S, sk.e2, sk.hand2], lw, shade(col, 0.82));
    limb(ctx, e, st, [[0, 0], sk.k2, sk.foot2], lw, shade(col, 0.82));
    limb(ctx, e, st, [[0, 0], sk.N], lw * 1.05, col);
    limb(ctx, e, st, [[0, 0], sk.k1, sk.foot1], lw, col);
    ctx.fillStyle = col; ctx.beginPath(); ctx.arc(hx, hyy, BODY.head * z, 0, 7); ctx.fill();
    // highlight
    ctx.strokeStyle = 'rgba(255,255,255,0.28)'; ctx.lineWidth = lw * 0.28; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.arc(hx, hyy, BODY.head * z * 0.62, Math.PI * 1.1, Math.PI * 1.55); ctx.stroke();
    ctx.globalAlpha = 1;
    return { hx, hyy, z, lw };
  }
  function drawScarf(ctx, e, name, s, alpha) {
    const M = SIM.scarfM, i = clamp(Math.round(s * SIM.RATE), 0, SIM.N - 1), buf = SIM.scarf[name];
    const pts = []; for (let k = 0; k < M; k++) pts.push([e.X(buf[(i * M + k) * 2]), e.Y(buf[(i * M + k) * 2 + 1])]);
    const st = SIM.stateAt(name, s), z = e.zoom * st.sc;
    ctx.globalAlpha = alpha === undefined ? 1 : alpha; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (const pass of [0, 1]) {
      for (let k = 1; k < M; k++) {
        const w = (7.6 - k * 0.78) * z + (pass ? 0 : 4.2 * z);
        ctx.strokeStyle = pass ? SCARF[name] : '#14110f'; ctx.lineWidth = Math.max(0.5, w);
        ctx.beginPath(); ctx.moveTo(pts[k - 1][0], pts[k - 1][1]); ctx.lineTo(pts[k][0], pts[k][1]); ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
  }
  function shade(hex, k) { const n = parseInt(hex.slice(1), 16), r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255; return `rgb(${Math.round(r * k)},${Math.round(g * k)},${Math.round(b * k)})`; }
  function drawSaber(ctx, e, st, name, alpha) {
    const sk = st.sk, z = e.zoom * st.sc, c = SIM.colors[name];
    const h0 = toWorld(st, sk.hilt0), h1 = toWorld(st, sk.hilt1);
    ctx.globalAlpha = alpha === undefined ? 1 : alpha; ctx.lineCap = 'round';
    ctx.strokeStyle = '#2b2927'; ctx.lineWidth = 6 * z; ctx.beginPath(); ctx.moveTo(e.X(h0[0]), e.Y(h0[1])); ctx.lineTo(e.X(h1[0]), e.Y(h1[1])); ctx.stroke();
    ctx.strokeStyle = '#a7a39b'; ctx.lineWidth = 3 * z; ctx.beginPath(); ctx.moveTo(e.X(h0[0]), e.Y(h0[1])); ctx.lineTo(e.X(h1[0]), e.Y(h1[1])); ctx.stroke();
    if (st.on > 0.01) {
      const [a, b] = SIM.blade(st); const ax_ = e.X(a[0]), ay = e.Y(a[1]), bx = e.X(b[0]), by = e.Y(b[1]);
      const flick = 0.92 + 0.08 * Math.sin(e.o * 90 + name.charCodeAt(0));
      const L = (w, col, al) => { ctx.strokeStyle = col; ctx.globalAlpha = (alpha === undefined ? 1 : alpha) * al; ctx.lineWidth = w * z; ctx.beginPath(); ctx.moveTo(ax_, ay); ctx.lineTo(bx, by); ctx.stroke(); };
      L(46 * flick, c.glow + '0.10)', 1); L(30, c.glow + '0.17)', 1); L(20, c.glow + '0.28)', 1);
      L(13.5, RIM[name], 1); L(9.5, c.saber, 1); L(4.2, '#ffffff', 1);
      // pommel glow
      ctx.globalAlpha = 1;
    }
    ctx.globalAlpha = 1;
  }
  function drawTrail(ctx, e, name, s) {
    const dt = 1 / 150; let prev = null; const n = 9;
    const cur = SIM.stateAt(name, s); if (cur.on < 0.3) return;
    const c = SIM.colors[name];
    const pts = [];
    for (let j = 0; j <= n; j++) {
      const st = SIM.stateAt(name, s - j * dt), b = SIM.blade(st);
      pts.push([b[0], b[1]]);
    }
    // use points along the blade from 45%..100%
    const seg = [];
    for (let j = 0; j <= n; j++) {
      const st = SIM.stateAt(name, s - j * dt), b = SIM.blade(st);
      seg.push([[lerp(b[0][0], b[1][0], 0.38), lerp(b[0][1], b[1][1], 0.38)], b[1]]);
    }
    for (let j = 0; j < n; j++) {
      const A = seg[j], B = seg[j + 1];
      const d = Math.hypot(A[1][0] - B[1][0], A[1][1] - B[1][1]);
      if (d < 3) continue;
      const al = clamp(d / 40, 0, 1) * 0.5 * (1 - j / n);
      ctx.fillStyle = c.glow + al + ')';
      ctx.beginPath(); ctx.moveTo(e.X(A[0][0]), e.Y(A[0][1])); ctx.lineTo(e.X(A[1][0]), e.Y(A[1][1])); ctx.lineTo(e.X(B[1][0]), e.Y(B[1][1])); ctx.lineTo(e.X(B[0][0]), e.Y(B[0][1])); ctx.closePath(); ctx.fill();
    }
  }

  function drawActors(ctx, e) {
    const { s } = e;
    const sts = SIM.names.map(n => SIM.stateAt(n, s));
    sts.sort((a, b) => b.gy - a.gy);
    // shadows
    for (const st of sts) {
      const tr = SIM.F[st.name]; if (s > tr.deathT + 2.4) continue;
      const k = 1 / (1 + Math.max(0, st.h) / 140);
      const px = e.X(st.x), py = e.Y(st.gy - 3);
      ctx.fillStyle = `rgba(20,16,12,${0.28 * k})`; ctx.beginPath(); ctx.ellipse(px, py, 42 * st.sc * e.zoom * (0.7 + 0.3 * k), 8 * st.sc * e.zoom * k, 0, 0, 7); ctx.fill();
    }
    for (const st of sts) {
      const name = st.name, tr = SIM.F[name], c = SIM.colors[name];
      const dead = s >= tr.deathT, dtDead = s - tr.deathT;
      if (dead && dtDead > 2.6) continue;
      // saber light on the ground / glow around fighter
      if (st.on > 0.05 && !dead) {
        const b = SIM.blade(st), mid = [(b[0][0] + b[1][0]) / 2, (b[0][1] + b[1][1]) / 2];
        const px = e.X(mid[0]), py = e.Y(mid[1]), r = 150 * e.zoom * st.on;
        const rg = ctx.createRadialGradient(px, py, 0, px, py, r); rg.addColorStop(0, c.glow + '0.20)'); rg.addColorStop(1, c.glow + '0)');
        ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, 2 * r, 2 * r);
      }
      if (!dead) drawTrail(ctx, e, name, s);
      // afterimages on fast moves
      if (!dead) {
        const sp = (SIM.stateAt(name, s).x - SIM.stateAt(name, s - 0.03).x) / 0.03;
        if (Math.abs(sp) > 520 || st.rot !== 0 && Math.abs(st.h) > 30) {
          for (let j = 3; j >= 1; j--) {
            const g2 = SIM.stateAt(name, s - j * 0.045);
            drawBody(ctx, e, g2, name, 0.12 + 0.05 * (4 - j), c.body);
          }
        }
      }
      if (dead) {
        // erosion wave: reveal only the part of the body right of the wave front (wind blows +x)
        const ev = SIM.evs.find(q => q.type === 'die' && q.f === name);
        const sp = 1.15; const wave = ev.x0 + dtDead * (ev.x1 - ev.x0) / sp;
        ctx.save(); ctx.beginPath(); ctx.rect(e.X(wave), 0, W, H); ctx.clip();
        drawScarf(ctx, e, name, s, 1); drawBody(ctx, e, st, name, 1);
        ctx.restore();
        continue;
      }
      drawScarf(ctx, e, name, s, 1);
      drawBody(ctx, e, st, name, 1);
      if (st.held) drawSaber(ctx, e, st, name, 1);
    }
  }

  // ---------------------------------------------------------------- FX
  function drawFX(ctx, e) {
    const { s, X, Y, zoom } = e;
    for (const ev of SIM.evs) {
      const dt = s - ev.t; if (dt < 0) continue;
      switch (ev.type) {
        case 'clash': if (dt < 1.0) fxClash(ctx, e, ev, dt); break;
        case 'spark': if (dt < 1.0) fxClash(ctx, e, ev, dt); break;
        case 'sabre': fxSabre(ctx, e, ev, s); break;
        case 'push': if (dt < 1.1) fxPush(ctx, e, ev, dt); break;
        case 'dust': if (dt < 2.2) fxDust(ctx, e, ev, dt); break;
        case 'rubble': if (dt < 2.4) fxRubble(ctx, e, ev, dt); break;
        case 'boom': if (dt < 1.4) fxBoom(ctx, e, ev, dt); break;
        case 'slice': if (dt < 0.5) fxSlice(ctx, e, ev, dt); break;
        case 'ignite': if (dt < 0.5) fxIgnite(ctx, e, ev, dt); break;
        case 'die': if (dt < 4) fxDie(ctx, e, ev, dt); break;
        case 'hit': if (dt < 0.6) fxHit(ctx, e, ev, dt); break;
        case 'embers': if (dt < ev.dur) fxEmbers(ctx, e, ev, dt); break;
      }
    }
  }
  function fxClash(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, pw = ev.pwr || 1, R = rng(ev.id * 31 + 7);
    const px = X(p[0]), py = Y(p[1]);
    // flash
    if (dt < 0.14 && pw >= 0.9) {
      const k = 1 - dt / 0.14, r = (26 + 40 * pw) * zoom * (0.5 + 0.5 * k);
      const rg = ctx.createRadialGradient(px, py, 0, px, py, r);
      rg.addColorStop(0, `rgba(255,255,255,${0.95 * k})`); rg.addColorStop(0.3, `rgba(255,214,120,${0.7 * k})`); rg.addColorStop(1, 'rgba(255,170,60,0)');
      ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, 2 * r, 2 * r);
      // star spikes
      ctx.strokeStyle = `rgba(255,250,235,${k})`; ctx.lineCap = 'round';
      for (let i = 0; i < 7; i++) { const a = R() * 6.28, l = (24 + R() * 60) * pw * zoom * k; ctx.lineWidth = (2 + R() * 3) * zoom; ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px + Math.cos(a) * l, py - Math.sin(a) * l); ctx.stroke(); }
    }
    // sparks
    const n = 18 + pw * 14;
    for (let i = 0; i < n; i++) {
      const a = R() * 6.28, v = (240 + R() * 820) * (0.7 + pw * 0.3), life = 0.22 + R() * 0.5;
      if (dt > life) continue;
      const gx = p[0] + Math.cos(a) * v * dt, gy = p[1] + Math.sin(a) * v * dt - 0.5 * 1500 * dt * dt;
      const vx = Math.cos(a) * v, vy = Math.sin(a) * v - 1500 * dt;
      const k = 1 - dt / life, tl = 0.045;
      ctx.strokeStyle = k > 0.55 ? `rgba(255,252,220,${k})` : `rgba(255,${Math.floor(110 + k * 150)},40,${k + 0.2})`;
      ctx.lineWidth = (1.4 + R() * 1.6) * zoom; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(X(gx), Y(gy)); ctx.lineTo(X(gx - vx * tl), Y(gy - vy * tl)); ctx.stroke();
    }
    if (pw >= 2 && dt < 0.5) { // ring
      const r = dt * 900 * zoom, k = 1 - dt / 0.5;
      ctx.strokeStyle = `rgba(255,255,255,${0.7 * k})`; ctx.lineWidth = 6 * k * zoom; ctx.beginPath(); ctx.arc(px, py, r, 0, 7); ctx.stroke();
      ctx.strokeStyle = `rgba(30,24,16,${0.35 * k})`; ctx.lineWidth = 2 * zoom; ctx.beginPath(); ctx.arc(px, py, r * 1.04, 0, 7); ctx.stroke();
    }
  }
  function fxPush(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, d = ev.dir, pw = ev.pwr || 1;
    const gy = C.groundY(ev.gz || 0.5);
    // forward crescents
    for (let i = 0; i < 4; i++) {
      const t = dt - i * 0.05; if (t < 0 || t > 0.55) continue;
      const k = 1 - t / 0.55, dist = t * 1700 * pw;
      const cx = X(p[0] + d * dist), cy = Y(p[1] - 20);
      ctx.strokeStyle = `rgba(255,255,255,${0.85 * k})`; ctx.lineWidth = (9 - i * 1.6) * k * zoom; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.ellipse(cx, cy, 28 * zoom * (1 + t * 3), (120 + t * 160) * zoom * (0.6 + 0.4 * pw), 0, d > 0 ? -1.15 : Math.PI - 1.15 + 0, d > 0 ? 1.15 : Math.PI + 1.15); ctx.stroke();
      ctx.strokeStyle = `rgba(30,24,16,${0.35 * k})`; ctx.lineWidth = 2 * zoom; ctx.beginPath(); ctx.ellipse(cx + d * 5 * zoom, cy, 30 * zoom * (1 + t * 3), (122 + t * 160) * zoom * (0.6 + 0.4 * pw), 0, d > 0 ? -1.15 : Math.PI - 1.15, d > 0 ? 1.15 : Math.PI + 1.15); ctx.stroke();
    }
    // ground ring
    if (dt < 0.9) {
      const k = 1 - dt / 0.9, R0 = dt * 1100 * pw;
      ctx.strokeStyle = `rgba(235,230,220,${0.55 * k})`; ctx.lineWidth = 7 * k * zoom;
      ctx.beginPath(); ctx.ellipse(X(p[0]), Y(gy - 6), R0 * zoom, R0 * 0.2 * zoom, 0, 0, 7); ctx.stroke();
    }
    // streak lines
    const R = rng(ev.id * 17 + 3);
    for (let i = 0; i < 16; i++) {
      const off = (R() - 0.5) * 220, l0 = R() * 160, ln = 120 + R() * 260, t = dt * (1600 + R() * 600), life = 0.5;
      if (dt > life) continue;
      const a = (1 - dt / life) * 0.6;
      ctx.strokeStyle = `rgba(250,246,238,${a})`; ctx.lineWidth = (1.5 + R() * 2) * zoom;
      const xs = p[0] + d * (t - ln + l0), xe = p[0] + d * (t + l0);
      ctx.beginPath(); ctx.moveTo(X(xs), Y(p[1] + off)); ctx.lineTo(X(xe), Y(p[1] + off)); ctx.stroke();
    }
  }
  function fxDust(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, R = rng(ev.id * 13 + 1), n = ev.n || 10, gy = C.groundY(ev.z || 0.5), pw = ev.pwr || 1;
    for (let i = 0; i < n; i++) {
      const a = R() * Math.PI, sp = (60 + R() * 260) * pw, life = 0.9 + R() * 1.2, dly = R() * 0.1;
      const t = dt - dly; if (t < 0 || t > life) continue;
      const k = t / life, dir = (R() < 0.5 ? -1 : 1) * (ev.spread === undefined ? 1 : ev.spread);
      const wx = ev.x + Math.cos(a) * sp * t * dir * 0.8 + 70 * k * (ev.wind === undefined ? 1 : ev.wind);
      const wy = gy + 8 + Math.sin(a) * sp * t * 0.5 + 30 * k;
      const r = (12 + R() * 22) * (1 + k * 2.4) * pw * 0.8 * zoom;
      const al = (1 - k) * 0.5 * (ev.alpha === undefined ? 1 : ev.alpha);
      const px = X(wx), py = Y(wy);
      const rg = ctx.createRadialGradient(px, py, 0, px, py, r); rg.addColorStop(0, `rgba(168,160,148,${al})`); rg.addColorStop(1, 'rgba(168,160,148,0)');
      ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, r * 2, r * 2);
    }
  }
  function fxRubble(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, R = rng(ev.id * 19 + 5), n = ev.n || 14, gy = C.groundY(ev.z || 0.5);
    for (let i = 0; i < n; i++) {
      const a = (ev.ang0 !== undefined ? ev.ang0 : 0.3) + R() * (ev.spreadA || 2.4), v = (200 + R() * 620) * (ev.pwr || 1), sz = 4 + R() * 12, spin = (R() - 0.5) * 14;
      const x = ev.x + Math.cos(a) * v * dt * (ev.dirx || 1), y0 = ev.y + Math.sin(a) * v * dt - 0.5 * 1500 * dt * dt;
      const y = Math.max(y0, gy - 6 + R() * 6);
      const life = 2.2; if (dt > life) continue;
      const al = dt > 1.6 ? 1 - (dt - 1.6) / 0.6 : 1;
      ctx.save(); ctx.translate(X(x), Y(y)); ctx.rotate(spin * Math.min(dt, 0.9)); ctx.globalAlpha = al;
      ctx.fillStyle = R() < 0.5 ? '#3c3834' : '#58534c'; ctx.fillRect(-sz * zoom / 2, -sz * zoom * 0.35, sz * zoom, sz * zoom * 0.7); ctx.restore();
    }
    ctx.globalAlpha = 1;
  }
  function fxBoom(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, gy = C.groundY(ev.z || 0.5), pw = ev.pwr || 1;
    const px = X(p[0]), py = Y(p[1]);
    if (dt < 0.22) {
      const k = 1 - dt / 0.22, r = 420 * pw * zoom * (1 - k * 0.3);
      const rg = ctx.createRadialGradient(px, py, 0, px, py, r); rg.addColorStop(0, `rgba(255,255,255,${k})`); rg.addColorStop(0.35, `rgba(255,236,170,${0.7 * k})`); rg.addColorStop(1, 'rgba(255,200,100,0)');
      ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, r * 2, r * 2);
    }
    for (let i = 0; i < 3; i++) {
      const t = dt - i * 0.07; if (t < 0 || t > 0.9) continue;
      const k = 1 - t / 0.9, r = t * (1500 - i * 300) * pw * zoom;
      ctx.strokeStyle = i === 0 ? `rgba(255,255,255,${0.9 * k})` : `rgba(40,34,28,${0.4 * k})`; ctx.lineWidth = (12 - i * 3) * k * zoom;
      ctx.beginPath(); ctx.arc(px, py, r, 0, 7); ctx.stroke();
    }
    if (dt < 1.0) {
      const k = 1 - dt / 1.0, R0 = dt * 1700 * pw;
      ctx.strokeStyle = `rgba(230,224,212,${0.7 * k})`; ctx.lineWidth = 10 * k * zoom;
      ctx.beginPath(); ctx.ellipse(X(p[0]), Y(gy - 6), R0 * zoom, R0 * 0.2 * zoom, 0, 0, 7); ctx.stroke();
    }
  }
  function fxSlice(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, a = ev.ang * D2R, L = (ev.len || 260);
    const k = 1 - dt / 0.5, kk = Math.pow(k, 2.5);
    const x0 = p[0] - Math.cos(a) * L, y0 = p[1] - Math.sin(a) * L, x1 = p[0] + Math.cos(a) * L, y1 = p[1] + Math.sin(a) * L;
    ctx.lineCap = 'round';
    ctx.strokeStyle = `rgba(20,16,12,${0.5 * kk})`; ctx.lineWidth = 11 * kk * zoom; ctx.beginPath(); ctx.moveTo(X(x0), Y(y0)); ctx.lineTo(X(x1), Y(y1)); ctx.stroke();
    ctx.strokeStyle = `rgba(255,255,255,${kk})`; ctx.lineWidth = 6 * kk * zoom; ctx.beginPath(); ctx.moveTo(X(x0), Y(y0)); ctx.lineTo(X(x1), Y(y1)); ctx.stroke();
  }
  function fxIgnite(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, c = SIM.colors[ev.f];
    const k = 1 - dt / 0.5, px = X(p[0]), py = Y(p[1]), r = (60 + 160 * (ev.big || 1)) * zoom * (0.4 + 0.6 * k);
    const rg = ctx.createRadialGradient(px, py, 0, px, py, r); rg.addColorStop(0, `rgba(255,255,255,${0.9 * k})`); rg.addColorStop(0.3, c.glow + (0.7 * k) + ')'); rg.addColorStop(1, c.glow + '0)');
    ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, r * 2, r * 2);
    const R = rng(ev.id * 3 + 1);
    for (let i = 0; i < 10; i++) {
      const a = R() * 6.28, v = 80 + R() * 260, t = dt, life = 0.4; if (t > life) continue;
      const q = 1 - t / life; ctx.strokeStyle = c.glow + q + ')'; ctx.lineWidth = 2 * zoom;
      ctx.beginPath(); ctx.moveTo(X(p[0] + Math.cos(a) * v * t), Y(p[1] + Math.sin(a) * v * t)); ctx.lineTo(X(p[0] + Math.cos(a) * (v * t + 14)), Y(p[1] + Math.sin(a) * (v * t + 14))); ctx.stroke();
    }
  }
  function fxSabre(ctx, e, ev, s) {
    const { X, Y, zoom } = e, c = SIM.colors[ev.f], dt = s - ev.t;
    if (dt < 0 || s >= ev.tc) return;
    let p, ang, bl = 0;
    const T = ev.tl - ev.t;
    if (s < ev.tl) {
      p = [ev.p0[0] + ev.vx * dt, ev.p0[1] + ev.vy * dt - 0.5 * 1500 * dt * dt];
      ang = (ev.a0 || 0.6) + 17 * dt * (ev.spinDir || -1); bl = 1;
    } else if (s < ev.tp) {
      p = [ev.lx, ev.gy + 3]; ang = ev.rest !== undefined ? ev.rest : 0.14; bl = 0;
      // retract blade right after landing
      bl = Math.max(0, 1 - (s - ev.tl) / 0.12);
    } else {
      const u = clamp((s - ev.tp) / (ev.tc - ev.tp), 0, 1), k = u * u;
      p = [lerp(ev.lx, ev.pc[0], k), lerp(ev.gy + 3, ev.pc[1], k)]; ang = (ev.rest !== undefined ? ev.rest : 0.14) + 30 * u * u;
    }
    const px = X(p[0]), py = Y(p[1]);
    const trail = s >= ev.tp || s < ev.tl ? 4 : 0;
    for (let k = trail; k >= 0; k--) {
      const q = p; // ghost copies for motion smear
      const gdt = k * 0.012;
      let gp = p, ga = ang;
      if (s < ev.tl) { const d2 = Math.max(0, dt - gdt); gp = [ev.p0[0] + ev.vx * d2, ev.p0[1] + ev.vy * d2 - 0.5 * 1500 * d2 * d2]; ga = (ev.a0 || 0.6) + 17 * d2 * (ev.spinDir || -1); }
      else if (s >= ev.tp) { const u2 = clamp((s - gdt - ev.tp) / (ev.tc - ev.tp), 0, 1), k2 = u2 * u2; gp = [lerp(ev.lx, ev.pc[0], k2), lerp(ev.gy + 3, ev.pc[1], k2)]; ga = 0.14 + 30 * u2 * u2; }
      const gx = X(gp[0]), gy = Y(gp[1]), al = 1 - k * 0.2;
      ctx.globalAlpha = al; ctx.lineCap = 'round';
      const dx = Math.cos(ga), dy = -Math.sin(ga);
      if (bl > 0.01) {
        const L = 118 * bl * zoom, x0 = gx + dx * 16 * zoom, y0 = gy + dy * 16 * zoom, x1 = gx + dx * (16 * zoom + L), y1 = gy + dy * (16 * zoom + L);
        for (const [w, col, a] of [[30, c.glow + '0.18)', 1], [13.5, RIM[ev.f], 1], [9.5, c.saber, 1], [4.2, '#fff', 1]]) { ctx.strokeStyle = col; ctx.lineWidth = w * zoom; ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke(); }
      }
      ctx.strokeStyle = '#2b2927'; ctx.lineWidth = 6 * zoom; ctx.beginPath(); ctx.moveTo(gx - dx * 6 * zoom, gy - dy * 6 * zoom); ctx.lineTo(gx + dx * 20 * zoom, gy + dy * 20 * zoom); ctx.stroke();
      ctx.strokeStyle = '#a7a39b'; ctx.lineWidth = 3 * zoom; ctx.beginPath(); ctx.moveTo(gx - dx * 6 * zoom, gy - dy * 6 * zoom); ctx.lineTo(gx + dx * 20 * zoom, gy + dy * 20 * zoom); ctx.stroke();
    }
    ctx.globalAlpha = 1;
    // glint while it rests on the ground
    if (s >= ev.tl && s < ev.tp) { const g = 0.5 + 0.5 * Math.sin(s * 8); const r = 22 * zoom; const rg = ctx.createRadialGradient(px, py, 0, px, py, r); rg.addColorStop(0, c.glow + (0.35 * g) + ')'); rg.addColorStop(1, c.glow + '0)'); ctx.fillStyle = rg; ctx.fillRect(px - r, py - r, 2 * r, 2 * r); }
  }
  function fxHit(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, p = ev.pos, k = 1 - dt / 0.6, R = rng(ev.id * 5 + 2);
    const px = X(p[0]), py = Y(p[1]);
    if (dt < 0.16) {
      const q = 1 - dt / 0.16, n = 10, r0 = (14 + 16 * (ev.pwr || 1)) * zoom, r1 = (46 + 54 * (ev.pwr || 1)) * zoom * (1 - q * 0.4);
      ctx.beginPath();
      for (let i = 0; i < n * 2; i++) { const a = i / (n * 2) * 6.283 + ev.id, r = i % 2 ? r0 : r1 * (0.7 + 0.3 * Math.sin(i * 7.7)); const x = px + Math.cos(a) * r, y = py + Math.sin(a) * r; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      ctx.closePath(); ctx.fillStyle = `rgba(255,255,255,${0.95 * q})`; ctx.fill(); ctx.strokeStyle = `rgba(20,16,12,${0.8 * q})`; ctx.lineWidth = 3 * zoom; ctx.stroke();
    }
    for (let i = 0; i < 9; i++) { const a = R() * 6.28, l = (40 + R() * 90) * (ev.pwr || 1), t = Math.min(dt / 0.3, 1); ctx.strokeStyle = `rgba(30,24,16,${k})`; ctx.lineWidth = 3 * zoom * k; ctx.beginPath(); ctx.moveTo(px + Math.cos(a) * l * 0.4 * t * zoom, py - Math.sin(a) * l * 0.4 * t * zoom); ctx.lineTo(px + Math.cos(a) * l * t * zoom, py - Math.sin(a) * l * t * zoom); ctx.stroke(); }
  }
  function fxEmbers(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, R = rng(ev.id + 99), n = ev.n || 30;
    for (let i = 0; i < n; i++) {
      const x0 = ev.x + (R() - 0.5) * (ev.w || 400), vy = 40 + R() * 120, vx = 30 + R() * 90, ph = R() * 6.28;
      const x = x0 + vx * dt + Math.sin(dt * 2 + ph) * 20, y = ev.y + vy * dt; const al = Math.min(1, dt * 2) * (1 - dt / ev.dur);
      ctx.fillStyle = `rgba(255,${120 + Math.floor(R() * 90)},40,${al})`; ctx.beginPath(); ctx.arc(X(x), Y(y), (1.6 + R() * 1.6) * zoom, 0, 7); ctx.fill();
    }
  }
  function fxDie(ctx, e, ev, dt) {
    const { X, Y, zoom } = e, st0 = SIM.colors[ev.f], R = rng(ev.id * 77 + 11);
    const wave = (dt / 1.15);
    for (let i = 0; i < ev.pts.length; i++) {
      const p = ev.pts[i], u = clamp((p[0] - ev.x0) / (ev.x1 - ev.x0), 0, 1);
      const rel = dt - u * 1.15; if (rel < 0) continue; // released as the wave passes
      const vx = 110 + R() * 260, vy = 30 + R() * 170, life = 1.6 + R() * 1.8, sz = 3.2 + R() * 5.4, wob = R() * 6.28;
      if (rel > life) continue;
      const k = rel / life;
      const x = p[0] + vx * rel + Math.sin(rel * 3 + wob) * 10, y = p[1] + vy * rel * (1 - k * 0.3) - 20 * rel * rel + Math.sin(rel * 4 + wob) * 6;
      // colour -> ash grey
      const col = k < 0.3 ? st0.body : (k < 0.55 ? '#7b756c' : '#4b4741');
      ctx.globalAlpha = (1 - k * k) * 0.95; ctx.fillStyle = col;
      ctx.fillRect(X(x) - sz * zoom / 2, Y(y) - sz * zoom / 2, sz * zoom, sz * zoom);
    }
    ctx.globalAlpha = 1;
  }

  // ---------------------------------------------------------------- foreground + ash
  function drawForeground(ctx, e) {
    const { X, Y, zoom } = e, f = 1.45;
    ctx.fillStyle = '#16140f';
    const cx = e.cam.x * f, view = 900 / zoom + 200;
    for (const b of FG) {
      if (b.x < cx - view || b.x > cx + view) continue;
      const bx = X(b.x, f), by = Y(-300), h = b.h * 1.4 * zoom, w = b.w * zoom * 1.3;
      if (b.kind === 1) { // bent girder with a cross-brace
        ctx.strokeStyle = '#16140f'; ctx.lineWidth = w * 0.45; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(bx, by + 40); ctx.lineTo(bx + b.lean * h * 0.5, by - h * 0.6); ctx.lineTo(bx + b.lean * h * 1.4 + w, by - h * 0.85); ctx.stroke();
        ctx.lineWidth = w * 0.22; ctx.beginPath(); ctx.moveTo(bx - w * 0.8, by - h * 0.25); ctx.lineTo(bx + b.lean * h * 0.5 + w * 0.9, by - h * 0.5); ctx.stroke();
        continue;
      }
      ctx.beginPath(); ctx.moveTo(bx - w, by + 60); ctx.lineTo(bx - w * 0.8 + b.lean * h, by - h * (0.5 + b.pts[0] * 0.3)); ctx.lineTo(bx + b.lean * h + w * (b.pts[1] - 0.3), by - h);
      ctx.lineTo(bx + w * 0.6 + b.lean * h * 0.8, by - h * (0.55 + b.pts[2] * 0.3)); ctx.lineTo(bx + w, by + 60); ctx.closePath(); ctx.fill();
    }
  }
  function drawFlakes(ctx, e) {
    const { s, zoom } = e;
    for (const fl of FLAKES) {
      const par = [0.25, 0.6, 1.5][fl.l];
      const spd = [30, 55, 120][fl.l] * fl.sp, fall = [26, 44, 90][fl.l] * fl.sp;
      let x = ((fl.u * 1.4 - 0.2) * W - e.cam.x * par * zoom * 0.4 + s * spd + Math.sin(s * 0.8 + fl.ph) * 14) % (W * 1.4);
      if (x < 0) x += W * 1.4; x -= W * 0.2;
      let y = ((fl.v * H * 1.3 + s * fall) % (H * 1.3)) - H * 0.15;
      const r = fl.r * (0.6 + zoom * 0.5);
      if (fl.l === 2) { ctx.fillStyle = 'rgba(52,48,42,0.30)'; ctx.beginPath(); ctx.ellipse(x, y, r * 1.6, r * 0.8, -0.3, 0, 7); ctx.fill(); }
      else { ctx.fillStyle = fl.l === 0 ? 'rgba(120,114,105,0.42)' : 'rgba(86,80,72,0.5)'; ctx.beginPath(); ctx.ellipse(x, y, r * 1.5, r, -0.3, 0, 7); ctx.fill(); }
    }
  }

  // ---------------------------------------------------------------- frame
  function fx_overlay(ctx, s, o) {
    ctx.setTransform(S, 0, 0, S, 0, 0);
    // grade: warm shadows, slight desaturated cool highlights
    ctx.globalCompositeOperation = 'multiply'; ctx.fillStyle = 'rgba(255,248,240,0.06)'; ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = 'source-over';
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.drawImage(vigC, 0, 0); ctx.setTransform(S, 0, 0, S, 0, 0);
  }
  function overlays(ctx, s, o) {
    ctx.setTransform(S, 0, 0, S, 0, 0);
    // impact frames
    for (const ev of SIM.evs) {
      if (ev.type !== 'impact') continue;
      if (o >= ev.o0 && o < ev.o0 + ev.od) {
        ctx.globalCompositeOperation = 'difference'; ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H); ctx.globalCompositeOperation = 'source-over';
        const cam = SIM.camAt(s); const px = W / 2 + cam.zoom * (ev.pos[0] - cam.x), py = H / 2 - cam.zoom * (ev.pos[1] - cam.y);
        const R = rng(ev.id * 9 + (Math.floor((o - ev.o0) * 30) & 1));
        ctx.strokeStyle = 'rgba(255,255,255,0.95)'; ctx.lineCap = 'round';
        for (let i = 0; i < 70; i++) { const a = R() * 6.28, r0 = 90 + R() * 160, r1 = r0 + 120 + R() * 700; ctx.lineWidth = 1 + R() * 5; ctx.beginPath(); ctx.moveTo(px + Math.cos(a) * r0, py + Math.sin(a) * r0); ctx.lineTo(px + Math.cos(a) * r1, py + Math.sin(a) * r1); ctx.stroke(); }
      }
    }
    // flashes
    for (const ev of SIM.evs) {
      if (ev.type !== 'flash') continue;
      const dt = s - ev.t; if (dt < 0 || dt > (ev.dur || 0.4)) continue;
      ctx.fillStyle = `rgba(${ev.rgb || '255,255,255'},${(ev.amp || 0.8) * Math.pow(1 - dt / (ev.dur || 0.4), 2)})`; ctx.fillRect(0, 0, W, H);
    }
    // letterbox
    ctx.fillStyle = '#050403'; ctx.fillRect(0, 0, W, BAR); ctx.fillRect(0, H - BAR, W, BAR);
    // texts
    for (const t of SIM.texts) {
      if (s < t.t0 || s > t.t1) continue;
      const fi = clamp((s - t.t0) / (t.fi || 0.35), 0, 1), fo = clamp((t.t1 - s) / (t.fo || 0.45), 0, 1), a = Math.min(fi, fo);
      drawText(ctx, t, a, s - t.t0);
    }
    // fades
    for (const f of SIM.fades || []) {
      if (s < f.t0 || s > f.t1) { if (s > f.t1 && f.to > 0) { ctx.fillStyle = `rgba(0,0,0,${f.to})`; ctx.fillRect(0, 0, W, H); } continue; }
      const u = (s - f.t0) / (f.t1 - f.t0); ctx.fillStyle = `rgba(${f.rgb || '0,0,0'},${lerp(f.from, f.to, u)})`; ctx.fillRect(0, 0, W, H);
    }
  }
  function spaced(ctx, str, x, y, sp, align) {
    let w = 0; for (const ch of str) w += ctx.measureText(ch).width + sp; w -= sp;
    let cx = align === 'center' ? x - w / 2 : x;
    for (const ch of str) { ctx.fillText(ch, cx, y); cx += ctx.measureText(ch).width + sp; }
    return w;
  }
  function drawText(ctx, t, a, age) {
    ctx.save(); ctx.globalAlpha = a; ctx.textBaseline = 'alphabetic';
    if (t.kind === 'title') {
      const sc = 1 + (1 - a) * 0.05 + age * 0.004;
      ctx.translate(W / 2, H / 2 - 110); ctx.scale(sc, sc);
      ctx.font = `bold 118px ${FONT}`; ctx.fillStyle = 'rgba(0,0,0,0.12)'; spaced(ctx, t.text, 5, 7, 22, 'center');
      ctx.fillStyle = '#1b1814'; spaced(ctx, t.text, 0, 0, 22, 'center');
      ctx.font = `bold 22px ${FONT}`; ctx.fillStyle = '#3b362f'; spaced(ctx, t.sub, 0, 52, 14, 'center');
      const cols = ['#2fdc66', '#3b8cff', '#ffd21c']; for (let i = 0; i < 3; i++) { ctx.fillStyle = cols[i]; ctx.fillRect(-150 + i * 104, 76, 92, 7); }
    } else if (t.kind === 'name') {
      const c = SIM.colors[t.who];
      const slide = (1 - a) * -40;
      ctx.translate(90 + slide, H - BAR - 74);
      ctx.fillStyle = c.body; ctx.fillRect(0, 0, 9, 54);
      ctx.font = `bold 46px ${FONT}`; ctx.fillStyle = '#17140f'; ctx.fillText(c.name, 24, 38);
      ctx.font = `bold 15px ${FONT}`; ctx.fillStyle = '#3d382f'; spaced(ctx, t.sub || '', 26, 54, 6, 'left');
    } else if (t.kind === 'vs') {
      ctx.translate(W / 2, H / 2 - 120); const sc = 1 + (1 - a) * 0.4; ctx.scale(sc, sc);
      ctx.font = `bold 64px ${FONT}`; ctx.fillStyle = '#17140f'; spaced(ctx, t.text, 0, 0, 14, 'center');
    } else if (t.kind === 'end') {
      const sc = 1 + age * 0.006;
      ctx.translate(W / 2, H / 2 - 130); ctx.scale(sc, sc);
      ctx.font = `bold 104px ${FONT}`; ctx.fillStyle = 'rgba(0,0,0,0.25)'; spaced(ctx, t.text, 4, 6, 18, 'center');
      ctx.fillStyle = '#ffd21c'; ctx.strokeStyle = '#17140f'; ctx.lineWidth = 8; ctx.lineJoin = 'round';
      let w = 0; for (const ch of t.text) w += ctx.measureText(ch).width + 18; w -= 18; let cx = -w / 2;
      for (const ch of t.text) { ctx.strokeText(ch, cx, 0); cx += ctx.measureText(ch).width + 18; }
      cx = -w / 2; for (const ch of t.text) { ctx.fillText(ch, cx, 0); cx += ctx.measureText(ch).width + 18; }
      if (t.sub) { ctx.font = `bold 24px ${FONT}`; ctx.fillStyle = '#f2eee6'; ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 5; let w2 = 0; for (const ch of t.sub) w2 += ctx.measureText(ch).width + 12; w2 -= 12; let c2 = -w2 / 2; for (const ch of t.sub) { ctx.strokeText(ch, c2, 58); ctx.fillText(ch, c2, 58); c2 += ctx.measureText(ch).width + 12; } }
    } else if (t.kind === 'small') {
      ctx.font = `bold ${t.size || 20}px ${FONT}`; ctx.fillStyle = t.color || '#17140f'; spaced(ctx, t.text, t.x, t.y, t.sp || 8, t.align || 'center');
    }
    ctx.restore();
  }

  const NSUB = 5, SHUT = 0.5;
  function frame(i) {
    const o = i / SIM.FPS;
    const dtF = 1 / SIM.FPS;
    for (let k = 0; k < NSUB; k++) {
      const oo = o + (NSUB === 1 ? 0 : (k / (NSUB - 1) - 0.5) * SHUT * dtF);
      const s = SIM.warp.o2s(Math.max(0, oo));
      scene(sx, s, oo, SIM.warp.o2s(o), o);
      ax.setTransform(1, 0, 0, 1, 0, 0); ax.globalAlpha = 1 / (k + 1); ax.drawImage(sceneC, 0, 0);
    }
    ax.globalAlpha = 1;
    const s0 = SIM.warp.o2s(o);
    out.setTransform(1, 0, 0, 1, 0, 0); out.drawImage(accC, 0, 0);
    fx_overlay(out, s0, o);
    overlays(out, s0, o);
  }
  return { frame, scene, canvas };
}
root.createRenderer = createRenderer;
})(typeof window !== 'undefined' ? window : globalThis);
