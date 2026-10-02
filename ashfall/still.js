// dev tool: contact sheet of frames. usage: node still.js out.png "s:12.5,s:13,o:2.0" [storyFile] [cols] [scale]
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const out = process.argv[2], list = process.argv[3].split(','), story = process.argv[4] || 'story.js';
const cols = +(process.argv[5] || 3), thumbW = +(process.argv[6] || 640);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1300, height: 760 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e))); p.on('console', m => { if (m.type() === 'error' || m.type() === 'log') console.log('[page]', m.text()); });
  await p.setContent('<body style="margin:0"><canvas id=c></canvas></body>');
  for (const f of ['core.js', 'poses.js', 'sim.js', story, 'render.js']) await p.addScriptTag({ content: fs.readFileSync(path.join(__dirname, f), 'utf8') });
  const res = await p.evaluate(({ list, cols, thumbW }) => {
    const c = document.getElementById('c'); const R = createRenderer(c, 1);
    const tw = thumbW, th = Math.round(thumbW * 720 / 1280);
    const rows = Math.ceil(list.length / cols);
    const sheet = document.createElement('canvas'); sheet.width = tw * cols; sheet.height = th * rows; const g = sheet.getContext('2d');
    list.forEach((q, i) => {
      const [k, v] = q.split(':'); let o = k === 's' ? SIM.warp.s2o(+v) : +v;
      const fi = Math.round(o * SIM.FPS); R.frame(fi);
      g.drawImage(c, (i % cols) * tw, Math.floor(i / cols) * th, tw, th);
      g.fillStyle = '#fff'; g.font = 'bold 14px sans-serif'; g.fillText(q, (i % cols) * tw + 8, Math.floor(i / cols) * th + 62);
    });
    return { url: sheet.toDataURL('image/png'), dur: SIM.warp.dur };
  }, { list, cols, thumbW });
  fs.writeFileSync(out, Buffer.from(res.url.split(',')[1], 'base64'));
  console.log('output duration', res.dur);
  if (errs.length) console.log('ERRORS', errs);
  await b.close();
})();
