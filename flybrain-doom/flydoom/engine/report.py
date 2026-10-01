"""Write experiment results as JSON, Markdown and a self-contained interactive HTML report."""
from __future__ import annotations

import html
import json
import os

import numpy as np

from . import stats

AIM_BINS = [(-90, -20, "< -20°"), (-20, -10, "-20…-10°"), (-10, -3, "-10…-3°"), (-3, 3, "-3…3°"),
            (3, 10, "3…10°"), (10, 20, "10…20°"), (20, 90, "> 20°")]
CONDITIONS = [("random", "Random play"), ("untrained", "Fly brain, untrained"),
              ("trained", "Fly brain, trained"), ("kc_lesioned", "Trained, Kenyon cells silenced"),
              ("dan_lesioned_trained", "Trained with dopamine neurons silenced")]


def _clean(o):
    if isinstance(o, dict):
        return {str(k): _clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [_clean(v) for v in o]
    if isinstance(o, np.ndarray):
        return _clean(o.tolist())
    if isinstance(o, (np.floating, float)):
        f = float(o)
        return None if not np.isfinite(f) else round(f, 6)
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.bool_,)):
        return bool(o)
    return o


def aim_table(episodes: list[dict], actions: list[str]) -> dict:
    pairs = [p for e in episodes for p in e.get("aim", [])]
    rows = []
    for lo, hi, label in AIM_BINS:
        acts = [a for az, a in pairs if lo <= az < hi]
        n = len(acts)
        rows.append({"bin": label, "n": n, "p": {a: (acts.count(a) / n if n else 0.0) for a in actions}})
    return {"actions": actions, "rows": rows}


def summarize(results: dict) -> dict:
    """Compact, JSON-friendly view of a results dict (drops per-step aim lists)."""
    ev = results["eval"]
    actions = list(results["motor_map"])
    curve = [e["raw_return"] for e in results["curve"]]
    out = {
        "env": results["env"], "brain": results["brain"], "config": results["config"],
        "calibration": results.get("calibration"), "timing": results.get("timing"),
        "weight_change": results.get("weight_change"),
        "curve": {"returns": curve, "kills": [e["kills"] for e in results["curve"]],
                  "moving_average": stats.moving_average(curve, 20)},
        "eval": {}, "aim": {}, "gates": results["gates"],
    }
    if "dan_lesioned_curve" in ev:
        dc = [e["raw_return"] for e in ev["dan_lesioned_curve"]]
        out["curve"]["dan_lesioned_moving_average"] = stats.moving_average(dc, 20)
    for key, label in CONDITIONS:
        if key in ev:
            r = [e["raw_return"] for e in ev[key]]
            out["eval"][key] = {"label": label, "returns": r, "seeds": [e.get("seed") for e in ev[key]],
                                "kill_rate": float(np.mean([e["kills"] > 0 for e in ev[key]])),
                                "summary": stats.summary(r)}
    for key in ("untrained", "trained"):
        if key in ev:
            out["aim"][key] = aim_table(ev[key], actions)
    return _clean(out)


def _brain_state(b: dict) -> tuple[int, str]:
    if "state_neurons" in b:
        return b["state_neurons"], b.get("state_label", "Kenyon cells")
    return b.get("kenyon_cells", 0), "Kenyon cells"


def rerender(out_dir: str) -> None:
    """Rewrite report.md / report.html from an existing results.json (e.g. after template edits)."""
    with open(os.path.join(out_dir, "results.json")) as f:
        s = json.load(f)
    with open(os.path.join(out_dir, "report.md"), "w") as f:
        f.write(markdown(s))
    with open(os.path.join(out_dir, "report.html"), "w") as f:
        f.write(html_report(s))


def write_report(results: dict, out_dir: str) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    s = summarize(results)
    with open(os.path.join(out_dir, "results.json"), "w") as f:
        json.dump(s, f, indent=1)
    with open(os.path.join(out_dir, "report.md"), "w") as f:
        f.write(markdown(s))
    with open(os.path.join(out_dir, "report.html"), "w") as f:
        f.write(html_report(s))
    return s


def _fmt(x, digits=1):
    return "–" if x is None else f"{x:,.{digits}f}"


def markdown(s: dict) -> str:
    n_state, state_label = _brain_state(s["brain"])
    lines = [f"# Fly brain plays Doom: {s['env']}", "",
             f"Brain: **{s['brain']['name']}** ({s['brain']['neurons']:,} neurons, "
             f"{s['brain']['synapses']:,} synapses; {n_state:,} {state_label} feed the plastic synapses). "
             f"Training: {len(s['curve']['returns'])} episodes. "
             f"Evaluation: frozen weights on {s['config']['eval_episodes']} fixed seeds.", "",
             "## Evaluation", "", "| condition | episodes | mean return | 95% CI | median | episodes with a kill |",
             "|---|---:|---:|---|---:|---:|"]
    for key, e in s["eval"].items():
        sm = e["summary"]
        lines.append(f"| {e['label']} | {sm['n']} | {_fmt(sm['mean'])} | [{_fmt(sm['ci95'][0])}, "
                     f"{_fmt(sm['ci95'][1])}] | {_fmt(sm['median'])} | {e['kill_rate']:.0%} |")
    lines += ["", "## Validation gates", "", "| gate | verdict | criterion |", "|---|---|---|"]
    for g in s["gates"]:
        verdict = {True: "PASS", False: "FAIL", None: "INFO"}[g["passed"]]
        lines.append(f"| {g['name']} | {verdict} | {g['criterion']} |")
    if s.get("aim"):
        lines += ["", "## Where the fly steers (share of actions by monster azimuth)", ""]
        for key, t in s["aim"].items():
            acts = t["actions"]
            lines += [f"**{key}**", "", "| monster azimuth | steps | " + " | ".join(acts) + " |",
                      "|---|---:|" + "---:|" * len(acts)]
            for row in t["rows"]:
                lines.append(f"| {row['bin']} | {row['n']} | " +
                             " | ".join(f"{row['p'][a]:.0%}" for a in acts) + " |")
            lines.append("")
    if s.get("timing"):
        lines += ["", f"Training wall time: {s['timing']['train_s']:.0f} s "
                      f"({s['timing']['train_s_per_episode']:.2f} s per episode)."]
    return "\n".join(lines) + "\n"


def html_report(s: dict) -> str:
    data = json.dumps(s).replace("</", "<\\/")
    title = f"Fly brain plays Doom · {s['env']}"
    return _TEMPLATE.replace("__TITLE__", html.escape(title)).replace("__DATA__", data)


_TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>__TITLE__</title>
<style>
:root{color-scheme:light;--page:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;
--grid:#e1e0d9;--axis:#c3c2b7;--ring:rgba(11,11,11,.10);--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;
--good:#0ca30c;--critical:#d03b3b;--good-text:#006300}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){color-scheme:dark;--page:#0d0d0d;--surface:#1a1a19;
--ink:#fff;--ink2:#c3c2b7;--muted:#898781;--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;--s3:#199e70;
--s4:#c98500;--s5:#d55181;--good-text:#0ca30c}}
:root[data-theme="dark"]{color-scheme:dark;--page:#0d0d0d;--surface:#1a1a19;--ink:#fff;--ink2:#c3c2b7;--muted:#898781;--grid:#2c2c2a;
--axis:#383835;--ring:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--good-text:#0ca30c}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1040px;margin:0 auto;padding:28px 16px 48px}h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:0 0 4px}
.sub{color:var(--ink2);margin:0 0 20px}.card{background:var(--surface);border:1px solid var(--ring);border-radius:10px;padding:16px;margin:0 0 16px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin:0 0 16px}
.tile .label{color:var(--ink2);font-size:13px}.tile .value{font-size:26px;font-weight:600}.tile .note{color:var(--muted);font-size:12px}
.legend{display:flex;flex-wrap:wrap;gap:14px;color:var(--ink2);font-size:13px;margin:6px 0 4px}.key{display:inline-flex;align-items:center;gap:6px}
.sw{width:14px;height:3px;border-radius:2px;display:inline-block}.sq{width:10px;height:10px;border-radius:2px;display:inline-block}
svg{display:block;max-width:100%;height:auto;overflow:visible}svg text{fill:var(--muted);font-size:11px;font-variant-numeric:tabular-nums}
svg text.halo{paint-order:stroke;stroke:var(--surface);stroke-width:3px;stroke-linejoin:round}
.tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--ring);border-radius:8px;
padding:6px 9px;font-size:12px;box-shadow:0 4px 14px rgba(0,0,0,.12);display:none;z-index:9;max-width:260px}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--grid);vertical-align:top}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}details{margin-top:8px;color:var(--ink2)}summary{cursor:pointer;font-size:13px}
.verdict{display:inline-flex;align-items:center;gap:6px;font-weight:600;white-space:nowrap}.pass{color:var(--good-text)}.fail{color:var(--critical)}.info{color:var(--muted)}
.multi{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}.muted{color:var(--muted)}
.toggle{float:right;font:inherit;font-size:12px;color:var(--ink2);background:transparent;border:1px solid var(--ring);border-radius:6px;padding:3px 8px;cursor:pointer}
</style></head><body><main>
<button class="toggle" id="theme" type="button">Theme</button>
<h1 id="h"></h1><p class="sub" id="sub"></p>
<div class="tiles" id="tiles"></div>
<section class="card"><h2>Learning curve</h2><p class="sub" style="margin:0">Return per training episode, 20-episode moving average. Reference lines: frozen evaluation means.</p>
<div class="legend" id="curve-legend"></div><div id="curve"></div>
<details><summary>Table view</summary><div id="curve-table"></div></details></section>
<section class="card"><h2>Evaluation on fixed seeds</h2><p class="sub" style="margin:0">One dot per episode; the vertical bar is the mean. Same episode seeds for every condition.</p>
<div id="eval"></div><details><summary>Table view</summary><div id="eval-table"></div></details></section>
<section class="card"><h2>Where the fly steers</h2><p class="sub" style="margin:0">Share of each motor command by the nearest monster's azimuth (negative = left). Ground truth from the game, never shown to the brain.</p>
<div class="legend" id="aim-legend"></div><div class="multi" id="aim"></div><details><summary>Table view</summary><div id="aim-table"></div></details></section>
<section class="card"><h2>Validation gates</h2><div id="gates"></div></section>
<p class="muted" id="foot"></p>
</main><div class="tip" id="tip"></div>
<script>
const D=__DATA__;
const $=id=>document.getElementById(id), css=v=>getComputedStyle(document.documentElement).getPropertyValue(v).trim();
const fmt=(x,d=0)=>x==null?'–':Number(x).toLocaleString(undefined,{maximumFractionDigits:d,minimumFractionDigits:d});
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const tip=$('tip');function showTip(e,h){tip.innerHTML=h;tip.style.display='block';const x=Math.min(e.clientX+14,innerWidth-tip.offsetWidth-8);tip.style.left=x+'px';tip.style.top=(e.clientY+14)+'px'}
function hideTip(){tip.style.display='none'}
const NS='http://www.w3.org/2000/svg';function el(t,a,p){const n=document.createElementNS(NS,t);for(const k in a)n.setAttribute(k,a[k]);if(p)p.appendChild(n);return n}
function ticks(lo,hi,n=5){const span=hi-lo||1,step0=span/n,mag=Math.pow(10,Math.floor(Math.log10(step0))),f=step0/mag,step=(f<1.5?1:f<3?2:f<7?5:10)*mag;
const out=[];for(let v=Math.ceil(lo/step)*step;v<=hi+1e-9;v+=step)out.push(+v.toFixed(10));return out}
function scale(d0,d1,r0,r1){return v=>r0+(v-d0)/(d1-d0||1)*(r1-r0)}
const series=['--s1','--s2','--s3','--s4','--s5'];
function header(){const ev=D.eval,t=ev.trained&&ev.trained.summary,u=ev.untrained&&ev.untrained.summary;
$('h').textContent='Fly brain plays Doom · '+D.env;
const nState=D.brain.state_neurons??D.brain.kenyon_cells,stateLabel=D.brain.state_label||'Kenyon cells';
$('sub').textContent=`${D.brain.name}: ${fmt(D.brain.neurons)} neurons, ${fmt(D.brain.synapses)} synapses, ${fmt(nState)} ${stateLabel} feed the plastic synapses · trained ${D.curve.returns.length} episodes · evaluated on ${D.config.eval_episodes} fixed seeds`;
const passed=D.gates.filter(g=>g.passed===true).length,judged=D.gates.filter(g=>g.passed!==null).length;
const tiles=[['Trained mean return',t?fmt(t.mean,1):'–',u?`untrained ${fmt(u.mean,1)}`:''],
['Episodes with a kill',ev.trained?fmt(100*ev.trained.kill_rate)+'%':'–',ev.untrained?`untrained ${fmt(100*ev.untrained.kill_rate)}%`:''],
['Gates passed',`${passed} / ${judged}`,'falsifiable checks below'],
['Training time',D.timing?fmt(D.timing.train_s/60,1)+' min':'–',D.timing?fmt(D.timing.train_s_per_episode,2)+' s per episode':'']];
$('tiles').innerHTML=tiles.map(([l,v,n])=>`<div class="card tile" style="margin:0"><div class="label">${l}</div><div class="value">${v}</div><div class="note">${n}</div></div>`).join('')}
function legend(id,items,shape='sw'){$(id).innerHTML=items.map(([c,l])=>`<span class="key"><span class="${shape}" style="background:var(${c})"></span>${esc(l)}</span>`).join('')}
function curve(){const box=$('curve');box.innerHTML='';const W=Math.max(box.clientWidth||960,300),narrow=W<640,H=narrow?240:300,m={l:44,r:narrow?10:120,t:12,b:34};
const ma=D.curve.moving_average,dm=D.curve.dan_lesioned_moving_average,n=ma.length;
const refs=[];for(const k of ['random','untrained','trained'])if(D.eval[k])refs.push([D.eval[k].label,D.eval[k].summary.mean]);
const vals=[...ma.filter(v=>v!=null),...(dm||[]).filter(v=>v!=null),...refs.map(r=>r[1])];
let lo=Math.min(...vals),hi=Math.max(...vals);const pad=(hi-lo)*.08||1;lo-=pad;hi+=pad;
const x=scale(1,n,m.l,W-m.r),y=scale(lo,hi,H-m.b,m.t);const svg=el('svg',{viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'Learning curve'},box);
for(const v of ticks(lo,hi)){el('line',{x1:m.l,x2:W-m.r,y1:y(v),y2:y(v),stroke:css('--grid'),'stroke-width':1},svg);const t=el('text',{x:m.l-8,y:y(v)+4,'text-anchor':'end'},svg);t.textContent=fmt(v)}
for(const v of ticks(1,n,narrow?4:6)){if(v<1)continue;const t=el('text',{x:x(v),y:H-m.b+18,'text-anchor':'middle'},svg);t.textContent=fmt(v)}
el('line',{x1:m.l,x2:W-m.r,y1:H-m.b,y2:H-m.b,stroke:css('--axis'),'stroke-width':1},svg);
const lab=el('text',{x:(m.l+W-m.r)/2,y:H-2,'text-anchor':'middle'},svg);lab.textContent='training episode';
for(const [name,v] of refs){el('line',{x1:m.l,x2:W-m.r,y1:y(v),y2:y(v),stroke:css('--axis'),'stroke-width':1.5},svg);const t=narrow?el('text',{x:W-m.r-2,y:y(v)-4,'text-anchor':'end',class:'halo'},svg):el('text',{x:W-m.r+6,y:y(v)+4},svg);t.textContent=`${name.replace('Fly brain, ','')}: ${fmt(v)}`}
const path=(arr,c)=>{let d='',pen=false;arr.forEach((v,i)=>{if(v==null){pen=false;return}d+=(pen?'L':'M')+x(i+1).toFixed(1)+','+y(v).toFixed(1);pen=true});
el('path',{d,fill:'none',stroke:css(c),'stroke-width':2,'stroke-linejoin':'round','stroke-linecap':'round'},svg)};
path(ma,'--s1');if(dm)path(dm,'--s2');
const items=[['--s1','Dopamine intact']];if(dm)items.push(['--s2','Dopamine neurons silenced']);legend('curve-legend',items);
const cross=el('line',{y1:m.t,y2:H-m.b,stroke:css('--axis'),'stroke-width':1,visibility:'hidden'},svg);
const dot1=el('circle',{r:4,fill:css('--s1'),stroke:css('--surface'),'stroke-width':2,visibility:'hidden'},svg);
const dot2=el('circle',{r:4,fill:css('--s2'),stroke:css('--surface'),'stroke-width':2,visibility:'hidden'},svg);
const hit=el('rect',{x:m.l,y:m.t,width:W-m.r-m.l,height:H-m.b-m.t,fill:'transparent'},svg);
hit.addEventListener('mousemove',e=>{const r=svg.getBoundingClientRect(),px=(e.clientX-r.left)*W/r.width;const i=Math.max(0,Math.min(n-1,Math.round((px-m.l)/(W-m.r-m.l)*(n-1))));
cross.setAttribute('x1',x(i+1));cross.setAttribute('x2',x(i+1));cross.setAttribute('visibility','visible');
let h=`<b>Episode ${i+1}</b><br>return ${fmt(D.curve.returns[i])}`;
if(ma[i]!=null){dot1.setAttribute('cx',x(i+1));dot1.setAttribute('cy',y(ma[i]));dot1.setAttribute('visibility','visible');h+=`<br>average, dopamine intact ${fmt(ma[i],1)}`}
if(dm&&dm[i]!=null){dot2.setAttribute('cx',x(i+1));dot2.setAttribute('cy',y(dm[i]));dot2.setAttribute('visibility','visible');h+=`<br>average, dopamine silenced ${fmt(dm[i],1)}`}
showTip(e,h)});hit.addEventListener('mouseleave',()=>{hideTip();for(const o of [cross,dot1,dot2])o.setAttribute('visibility','hidden')});
const rows=D.curve.returns.map((v,i)=>`<tr><td class="num">${i+1}</td><td class="num">${fmt(v)}</td><td class="num">${fmt(ma[i],1)}</td>${dm?`<td class="num">${fmt(dm[i],1)}</td>`:''}</tr>`).join('');
$('curve-table').innerHTML=`<table><tr><th class="num">episode</th><th class="num">return</th><th class="num">20-ep average</th>${dm?'<th class="num">20-ep average, dopamine silenced</th>':''}</tr>${rows}</table>`}
function evalChart(){const box=$('eval');box.innerHTML='';const keys=Object.keys(D.eval);const W=Math.max(box.clientWidth||960,300),narrow=W<640,row=narrow?58:44,m={l:narrow?12:250,r:narrow?12:20,t:8,b:30},H=m.t+m.b+row*keys.length;
const all=keys.flatMap(k=>D.eval[k].returns);let lo=Math.min(...all),hi=Math.max(...all);const pad=(hi-lo)*.04||1;lo-=pad;hi+=pad;
const x=scale(lo,hi,m.l,W-m.r);const svg=el('svg',{viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'Evaluation returns'},box);
for(const v of ticks(lo,hi,narrow?4:8)){el('line',{x1:x(v),x2:x(v),y1:m.t,y2:H-m.b,stroke:css('--grid'),'stroke-width':1},svg);const t=el('text',{x:x(v),y:H-m.b+16,'text-anchor':'middle'},svg);t.textContent=fmt(v)}
const xl=el('text',{x:(m.l+W-m.r)/2,y:H-2,'text-anchor':'middle'},svg);xl.textContent='episode return';
keys.forEach((k,ri)=>{const e=D.eval[k],cy=m.t+row*ri+row/2+(narrow?8:0);const t=narrow?el('text',{x:m.l,y:cy-18,style:'fill:var(--ink2);font-size:12px'},svg):el('text',{x:m.l-12,y:cy+4,'text-anchor':'end',style:'fill:var(--ink2);font-size:12px'},svg);t.textContent=e.label;
e.returns.forEach((v,i)=>{const jit=((i*37)%11-5)*2.2;const c=el('circle',{cx:x(v),cy:cy+jit,r:4,fill:css('--s1'),'fill-opacity':.75,stroke:css('--surface'),'stroke-width':2},svg);
const hitc=el('circle',{cx:x(v),cy:cy+jit,r:10,fill:'transparent'},svg);hitc.addEventListener('mousemove',ev=>showTip(ev,`<b>${esc(e.label)}</b><br>seed ${e.seeds[i]}: return ${fmt(v)}`));hitc.addEventListener('mouseleave',hideTip)});
const mu=e.summary.mean;el('line',{x1:x(mu),x2:x(mu),y1:cy-14,y2:cy+14,stroke:css('--ink'),'stroke-width':2,'stroke-linecap':'round'},svg)});
$('eval-table').innerHTML='<table><tr><th>condition</th><th class="num">episodes</th><th class="num">mean</th><th class="num">95% CI</th><th class="num">median</th><th class="num">with a kill</th></tr>'+
keys.map(k=>{const e=D.eval[k],s=e.summary;return `<tr><td>${esc(e.label)}</td><td class="num">${s.n}</td><td class="num">${fmt(s.mean,1)}</td><td class="num">${fmt(s.ci95[0],1)} … ${fmt(s.ci95[1],1)}</td><td class="num">${fmt(s.median,1)}</td><td class="num">${fmt(100*e.kill_rate)}%</td></tr>`}).join('')+'</table>'}
function aimChart(){const box=$('aim');box.innerHTML='';const keys=Object.keys(D.aim);if(!keys.length){box.textContent='No monster positions recorded.';return}
const acts=D.aim[keys[0]].actions;legend('aim-legend',acts.map((a,i)=>[series[i],a]),'sq');let tbl='';
for(const k of keys){const t=D.aim[k],wrap=document.createElement('div');wrap.innerHTML=`<div style="font-size:13px;color:var(--ink2);margin:4px 0">${k==='trained'?'Trained':'Untrained'}</div>`;box.appendChild(wrap);
const W=Math.max(wrap.clientWidth||460,280),H=230,m={l:40,r:8,t:8,b:44},nb=t.rows.length,band=(W-m.l-m.r)/nb,bw=Math.min(24,band*.6);const y=scale(0,1,H-m.b,m.t);
const svg=el('svg',{viewBox:`0 0 ${W} ${H}`,role:'img','aria-label':'Action share by monster azimuth'},wrap);
for(const v of [0,.25,.5,.75,1]){el('line',{x1:m.l,x2:W-m.r,y1:y(v),y2:y(v),stroke:css('--grid'),'stroke-width':1},svg);const tx=el('text',{x:m.l-6,y:y(v)+4,'text-anchor':'end'},svg);tx.textContent=Math.round(v*100)+'%'}
t.rows.forEach((r,bi)=>{const cx=m.l+band*bi+band/2;let acc=0;const lab=el('text',{x:cx,y:H-m.b+14,'text-anchor':'middle'},svg);lab.textContent=W<400?r.bin.replace('°',''):r.bin;
const nn=el('text',{x:cx,y:H-m.b+28,'text-anchor':'middle'},svg);nn.textContent='n='+r.n;if(!r.n)return;
acts.forEach((a,ai)=>{const p=r.p[a];if(p<=0){return}const y0=y(acc),y1=y(acc+p);acc+=p;const h=Math.max(0,y0-y1-2);
const rect=el('rect',{x:cx-bw/2,y:y1+ (ai?0:0),width:bw,height:h,fill:css(series[ai]),rx:ai===acts.length-1||acc>=0.999?4:0},svg);
const hit=el('rect',{x:cx-band/2,y:y1,width:band,height:Math.max(h,6),fill:'transparent'},svg);
hit.addEventListener('mousemove',e=>showTip(e,`<b>monster ${esc(r.bin)}</b><br>${esc(a)}: ${fmt(100*p)}% of ${r.n} steps`));hit.addEventListener('mouseleave',hideTip)})});
tbl+=`<p><b>${k}</b></p><table><tr><th>monster azimuth</th><th class="num">steps</th>${acts.map(a=>`<th class="num">${esc(a)}</th>`).join('')}</tr>`+
t.rows.map(r=>`<tr><td>${esc(r.bin)}</td><td class="num">${r.n}</td>${acts.map(a=>`<td class="num">${fmt(100*r.p[a])}%</td>`).join('')}</tr>`).join('')+'</table>'}
$('aim-table').innerHTML=tbl}
function gates(){const icon={true:'✓',false:'✕',null:'–'},cls={true:'pass',false:'fail',null:'info'},word={true:'Pass',false:'Fail',null:'Info'};
$('gates').innerHTML='<table><tr><th>gate</th><th>verdict</th><th>criterion</th></tr>'+D.gates.map(g=>`<tr><td>${esc(g.name)}</td><td><span class="verdict ${cls[g.passed]}">${icon[g.passed]} ${word[g.passed]}</span></td><td>${esc(g.criterion)}<details><summary>statistics</summary><pre style="white-space:pre-wrap;font-size:11px">${esc(JSON.stringify(g.metrics,null,1))}</pre></details></td></tr>`).join('')+'</table>'}
function render(){header();curve();evalChart();aimChart();gates();
$('foot').textContent=`Calibration: reference KC→MBON weight ${fmt(D.calibration&&D.calibration.w_ref_mv,2)} mV. Generated by flydoom.`}
$('theme').addEventListener('click',()=>{const r=document.documentElement,dark=matchMedia('(prefers-color-scheme: dark)').matches;
const cur=r.dataset.theme||(dark?'dark':'light');r.dataset.theme=cur==='dark'?'light':'dark';render()});
let rt;addEventListener('resize',()=>{clearTimeout(rt);rt=setTimeout(render,150)});
render();
</script></body></html>
"""
