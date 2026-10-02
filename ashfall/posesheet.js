// quick dev tool: render a sheet of all poses
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const out = process.argv[2] || 'sheet.png';
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  await p.setContent('<body style="margin:0;background:#ddd"><canvas id=c width=1600 height=900></canvas></body>');
  await p.addScriptTag({ content: fs.readFileSync(path.join(__dirname, 'core.js'), 'utf8') });
  await p.addScriptTag({ content: fs.readFileSync(path.join(__dirname, 'poses.js'), 'utf8') });
  const err = [];
  p.on('pageerror', e => err.push(String(e)));
  await p.evaluate(() => {
    const { POSE, solveLocal, resolvePose } = CORE;
    const c = document.getElementById('c'), x = c.getContext('2d');
    x.fillStyle = '#e4e1dc'; x.fillRect(0, 0, 1600, 900);
    const names = Object.keys(POSE);
    const cols = 8, cw = 200, ch = 220;
    names.forEach((n, i) => {
      const P = resolvePose(n); if (P.walk || P.run) { }
      const sk = solveLocal(P, 0.6);
      const ox = (i % cols) * cw + 90, oy = Math.floor(i / cols) * ch + 170;
      const T = pt => [ox + pt[0], oy - (pt[1] + sk.lift)];
      x.strokeStyle = '#111'; x.lineCap = 'round'; x.lineJoin = 'round';
      const line = (pts, w, col) => { x.strokeStyle = col; x.lineWidth = w; x.beginPath(); pts.forEach((q, k) => { const t = T(q); k ? x.lineTo(t[0], t[1]) : x.moveTo(t[0], t[1]); }); x.stroke(); };
      const body = (w, col) => {
        line([[0, 0], sk.N], w, col);
        line([sk.S, sk.e1, sk.hand1], w, col); line([sk.S, sk.e2, sk.hand2], w, col);
        line([[0, 0], sk.k1, sk.foot1], w, col); line([[0, 0], sk.k2, sk.foot2], w, col);
        const h = T(sk.head); x.fillStyle = col; x.beginPath(); x.arc(h[0], h[1], 14.5 + (w > 9 ? 3 : 0), 0, 7); x.fill();
      };
      body(13, '#111'); body(8, '#f1c40f');
      const hb = sk.hilt1, tip = [sk.hand1[0] + sk.bd[0] * 138, sk.hand1[1] + sk.bd[1] * 138];
      line([sk.hilt0, hb], 6, '#333'); line([hb, tip], 9, '#6af'); line([hb, tip], 4, '#fff');
      x.fillStyle = '#000'; x.font = '14px sans-serif'; x.fillText(n, ox - 60, oy + 20 + 0);
      x.strokeStyle = '#999'; x.lineWidth = 1; x.beginPath(); x.moveTo(ox - 90, oy); x.lineTo(ox + 100, oy); x.stroke();
    });
  });
  const data = await p.evaluate(() => document.getElementById('c').toDataURL('image/png'));
  fs.writeFileSync(out, Buffer.from(data.split(',')[1], 'base64'));
  if (err.length) console.log('ERR', err);
  await b.close();
})();
