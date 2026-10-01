// Small statistics toolkit for the test engine. Permutation tests are the
// primary inference (no distribution assumptions); t-tests are reported too.

import { RNG } from './rng.js';

export const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : NaN);
export function sd(a) {
  if (a.length < 2) return 0;
  const m = mean(a);
  return Math.sqrt(a.reduce((s, x) => s + (x - m) * (x - m), 0) / (a.length - 1));
}
export const sem = (a) => (a.length ? sd(a) / Math.sqrt(a.length) : NaN);

// Regularized incomplete beta I_x(a, b) via continued fraction (Numerical Recipes).
function lnGamma(z) {
  const g = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];
  let x = z, y = z, tmp = x + 5.5;
  tmp -= (x + 0.5) * Math.log(tmp);
  let ser = 1.000000000190015;
  for (let j = 0; j < 6; j++) ser += g[j] / ++y;
  return -tmp + Math.log((2.5066282746310005 * ser) / x);
}
function betacf(a, b, x) {
  const MAXIT = 200, EPS = 3e-14, FPMIN = 1e-300;
  let qab = a + b, qap = a + 1, qam = a - 1, c = 1, d = 1 - (qab * x) / qap;
  if (Math.abs(d) < FPMIN) d = FPMIN;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= MAXIT; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c; if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d; h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c; if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < EPS) break;
  }
  return h;
}
export function incBeta(x, a, b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const bt = Math.exp(lnGamma(a + b) - lnGamma(a) - lnGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
  return x < (a + 1) / (a + b + 2) ? (bt * betacf(a, b, x)) / a : 1 - (bt * betacf(b, a, 1 - x)) / b;
}
// Two-sided p-value of Student's t with df degrees of freedom.
export function tPValue(t, df) {
  if (!isFinite(t)) return t === t ? 0 : NaN;
  return incBeta(df / (df + t * t), df / 2, 0.5);
}

export function oneSampleT(a, mu = 0) {
  const n = a.length, s = sd(a);
  if (n < 2) return { t: NaN, df: n - 1, p: NaN };
  if (s === 0) { const same = mean(a) === mu; return { t: same ? 0 : Infinity, df: n - 1, p: same ? 1 : 0 }; }
  const t = (mean(a) - mu) / (s / Math.sqrt(n));
  return { t, df: n - 1, p: tPValue(t, n - 1) };
}

export function welchT(a, b) {
  const va = sd(a) ** 2 / a.length, vb = sd(b) ** 2 / b.length;
  if (a.length < 2 || b.length < 2) return { t: NaN, df: NaN, p: NaN };
  if (va + vb === 0) { const same = mean(a) === mean(b); return { t: same ? 0 : Infinity, df: a.length + b.length - 2, p: same ? 1 : 0 }; }
  const t = (mean(a) - mean(b)) / Math.sqrt(va + vb);
  const df = (va + vb) ** 2 / ((va * va) / (a.length - 1) + (vb * vb) / (b.length - 1));
  return { t, df, p: tPValue(t, df) };
}

// Two-sided sign-flip permutation test of mean(a) = 0 (one-sample or paired differences).
export function signFlipTest(a, { n = 20000, seed = 1 } = {}) {
  const k = a.length;
  if (!k) return { p: NaN };
  const obs = Math.abs(mean(a));
  if (k <= 16) {
    // exact enumeration
    let ge = 0;
    const total = 1 << k;
    for (let m = 0; m < total; m++) {
      let s = 0;
      for (let i = 0; i < k; i++) s += m & (1 << i) ? -a[i] : a[i];
      if (Math.abs(s / k) >= obs - 1e-12) ge++;
    }
    return { p: ge / total, exact: true };
  }
  const rng = new RNG(seed);
  let ge = 0;
  for (let r = 0; r < n; r++) {
    let s = 0;
    for (let i = 0; i < k; i++) s += rng.next() < 0.5 ? -a[i] : a[i];
    if (Math.abs(s / k) >= obs - 1e-12) ge++;
  }
  return { p: (ge + 1) / (n + 1), exact: false };
}

// Two-sided permutation test of mean(a) = mean(b), independent samples.
export function permutationTest(a, b, { n = 20000, seed = 2 } = {}) {
  const all = [...a, ...b], na = a.length;
  const obs = Math.abs(mean(a) - mean(b));
  const rng = new RNG(seed);
  let ge = 0;
  for (let r = 0; r < n; r++) {
    rng.shuffle(all);
    let sa = 0, sb = 0;
    for (let i = 0; i < all.length; i++) (i < na ? (sa += all[i]) : (sb += all[i]));
    if (Math.abs(sa / na - sb / (all.length - na)) >= obs - 1e-12) ge++;
  }
  return { p: (ge + 1) / (n + 1) };
}

export function cohenD(a, b) {
  const na = a.length, nb = b.length;
  const sp = Math.sqrt(((na - 1) * sd(a) ** 2 + (nb - 1) * sd(b) ** 2) / (na + nb - 2));
  return sp > 0 ? (mean(a) - mean(b)) / sp : 0;
}

export function bootstrapCI(a, { n = 5000, seed = 3, level = 0.95 } = {}) {
  if (!a.length) return [NaN, NaN];
  const rng = new RNG(seed), ms = new Float64Array(n);
  for (let r = 0; r < n; r++) {
    let s = 0;
    for (let i = 0; i < a.length; i++) s += a[rng.int(a.length)];
    ms[r] = s / a.length;
  }
  ms.sort();
  const lo = (1 - level) / 2;
  return [ms[Math.floor(lo * (n - 1))], ms[Math.ceil((1 - lo) * (n - 1))]];
}

export const fmtP = (p) => (!isFinite(p) ? 'n/a' : p < 0.001 ? '<0.001' : p.toFixed(3));
export const pEq = (p) => (!isFinite(p) ? 'p n/a' : p < 0.001 ? 'p<0.001' : `p=${p.toFixed(3)}`);
