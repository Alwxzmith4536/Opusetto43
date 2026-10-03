"""
Signed-distance-field toolkit + block based Surface-Nets mesher.

Pure numpy (works with the numpy that ships inside Blender), no other
dependencies. Used by build_power.py to sculpt the body, shoes and
garment shells procedurally.
"""
import numpy as np

F = np.float64


# ----------------------------------------------------------------------------
# small math helpers
# ----------------------------------------------------------------------------
def v3(*a):
    if len(a) == 1:
        return np.asarray(a[0], dtype=F)
    return np.asarray(a, dtype=F)


def norm(v):
    v = np.asarray(v, dtype=F)
    return v / np.linalg.norm(v)


def frame(fwd, up_hint):
    """Orthonormal 3x3 matrix, columns = (x=fwd, y, z), z close to up_hint."""
    x = norm(fwd)
    z = np.asarray(up_hint, dtype=F)
    z = norm(z - x * (z @ x))
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def rot_axis(axis, ang):
    axis = norm(axis)
    c, s = np.cos(ang), np.sin(ang)
    x, y, z = axis
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]], dtype=F)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def pchip(x, xs, ys):
    """Monotone cubic (Fritsch-Carlson) interpolation, clamped at the ends."""
    xs = np.asarray(xs, dtype=F)
    ys = np.asarray(ys, dtype=F)
    x = np.clip(np.asarray(x, dtype=F), xs[0], xs[-1])
    hk = np.diff(xs)
    dk = np.diff(ys) / hk
    m = np.zeros_like(ys)
    for i in range(1, len(xs) - 1):
        if dk[i - 1] * dk[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * hk[i] + hk[i - 1]
            w2 = hk[i] + 2 * hk[i - 1]
            m[i] = (w1 + w2) / (w1 / dk[i - 1] + w2 / dk[i])
    m[0] = dk[0]
    m[-1] = dk[-1]
    i = np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2)
    t = (x - xs[i]) / hk[i]
    t2, t3 = t * t, t * t * t
    h00 = 2 * t3 - 3 * t2 + 1
    h10 = t3 - 2 * t2 + t
    h01 = -2 * t3 + 3 * t2
    h11 = t3 - t2
    return h00 * ys[i] + h10 * hk[i] * m[i] + h01 * ys[i + 1] + h11 * hk[i] * m[i + 1]


def dot(a, b):
    return np.einsum('ij,ij->i', a, b)


# ----------------------------------------------------------------------------
# primitives: each has .lo/.hi (AABB) and __call__(P[N,3]) -> d[N]
# ----------------------------------------------------------------------------
class Prim:
    lo = None
    hi = None


class Sphere(Prim):
    def __init__(self, c, r):
        self.c = v3(c)
        self.r = float(r)
        self.lo = self.c - r
        self.hi = self.c + r

    def __call__(self, P):
        return np.linalg.norm(P - self.c, axis=1) - self.r


class RoundCone(Prim):
    """Capsule with different radii at both ends (Inigo Quilez)."""

    def __init__(self, a, b, r1, r2):
        a, b = v3(a), v3(b)
        self.a, self.b, self.r1, self.r2 = a, b, float(r1), float(r2)
        ba = b - a
        self.ba = ba
        self.l2 = float(ba @ ba)
        self.rr = self.r1 - self.r2
        self.a2 = self.l2 - self.rr * self.rr
        self.il2 = 1.0 / self.l2
        r = max(r1, r2)
        self.lo = np.minimum(a, b) - r
        self.hi = np.maximum(a, b) + r

    def __call__(self, P):
        pa = P - self.a
        y = pa @ self.ba
        z = y - self.l2
        q = pa * self.l2 - y[:, None] * self.ba
        x2 = dot(q, q)
        y2 = y * y * self.l2
        z2 = z * z * self.l2
        k = np.sign(self.rr) * self.rr * self.rr * x2
        d1 = np.sqrt(x2 + z2) * self.il2 - self.r2
        d2 = np.sqrt(x2 + y2) * self.il2 - self.r1
        d3 = (np.sqrt(np.maximum(x2 * self.a2 * self.il2, 0.0)) + y * self.rr) * self.il2 - self.r1
        return np.where(np.sign(z) * self.a2 * z2 > k, d1,
                        np.where(np.sign(y) * self.a2 * y2 < k, d2, d3))


def Capsule(a, b, r):
    return RoundCone(a, b, r, r * 0.9999)


class Ellipsoid(Prim):
    """Approximate ellipsoid SDF. R columns are the local axes in world space."""

    def __init__(self, c, r, R=None):
        self.c = v3(c)
        self.r = v3(r)
        self.R = np.eye(3) if R is None else np.asarray(R, dtype=F)
        ext = np.abs(self.R) @ self.r
        self.lo = self.c - ext
        self.hi = self.c + ext

    def __call__(self, P):
        q = (P - self.c) @ self.R
        k0 = np.linalg.norm(q / self.r, axis=1)
        k1 = np.linalg.norm(q / (self.r * self.r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


class RoundBox(Prim):
    def __init__(self, c, half, rad, R=None):
        self.c = v3(c)
        self.half = v3(half)
        self.rad = float(rad)
        self.R = np.eye(3) if R is None else np.asarray(R, dtype=F)
        ext = np.abs(self.R) @ (self.half + rad)
        self.lo = self.c - ext
        self.hi = self.c + ext

    def __call__(self, P):
        q = np.abs((P - self.c) @ self.R) - self.half
        return (np.linalg.norm(np.maximum(q, 0.0), axis=1)
                + np.minimum(np.max(q, axis=1), 0.0) - self.rad)


class Loft(Prim):
    """
    Vertical sweep of super-ellipse cross sections.
    keys: rows of (z, half_width, front_depth, back_depth, y_center, exponent)
    Front of the character is -Y.
    """

    def __init__(self, keys, cap_lo=0.03, cap_hi=0.03, x_center=0.0):
        k = np.asarray(keys, dtype=F)
        self.k = k
        self.z0, self.z1 = k[0, 0], k[-1, 0]
        self.cap_lo, self.cap_hi = cap_lo, cap_hi
        self.xc = x_center
        a = k[:, 1].max()
        self.lo = v3(x_center - a, (k[:, 4] - k[:, 2]).min(), self.z0)
        self.hi = v3(x_center + a, (k[:, 4] + k[:, 3]).max(), self.z1)

    def profile(self, z):
        k = self.k
        zs = k[:, 0]
        return [pchip(z, zs, k[:, i]) for i in range(1, 6)]

    def __call__(self, P):
        z = P[:, 2]
        a, bf, bb, yc, n = self.profile(z)
        x = np.abs(P[:, 0] - self.xc)
        y = P[:, 1] - yc
        b = np.where(y < 0, bf, bb)
        u = x / a + 1e-9
        w = np.abs(y) / b + 1e-9
        r = (u ** n + w ** n) ** (1.0 / n)
        # gradient of r in the cross-section plane
        rp = r ** (1.0 - n)
        gx = rp * u ** (n - 1) / a
        gy = rp * w ** (n - 1) / b
        g = np.sqrt(gx * gx + gy * gy) + 1e-9
        d = (r - 1.0) / g
        d = smax(d, self.z0 - z, self.cap_lo)
        d = smax(d, z - self.z1, self.cap_hi)
        return d


class Custom(Prim):
    def __init__(self, fn, lo, hi):
        self.fn = fn
        self.lo = v3(lo)
        self.hi = v3(hi)

    def __call__(self, P):
        return self.fn(P)


# ----------------------------------------------------------------------------
# scene = ordered list of CSG operations
# ----------------------------------------------------------------------------
class SDFScene:
    def __init__(self):
        self.ops = []  # (mode, prim, k)

    def add(self, prim, k=0.0):
        self.ops.append(('add', prim, k))
        return prim

    def sub(self, prim, k=0.0):
        self.ops.append(('sub', prim, k))
        return prim

    def bounds(self):
        lo = np.min([p.lo for m, p, k in self.ops if m == 'add'], axis=0)
        hi = np.max([p.hi for m, p, k in self.ops if m == 'add'], axis=0)
        return lo, hi

    def cull(self, lo, hi, pad=0.0):
        # A primitive can only be skipped where it cannot change the result
        # near the surface: beyond its own blend radius AND beyond the blend
        # radius of every later smooth operation (which could otherwise blend
        # with it).
        ks = np.array([k for _, _, k in self.ops] + [0.0])
        later = np.maximum.accumulate(ks[::-1])[::-1][1:]
        out = []
        for (m, p, k), kl in zip(self.ops, later):
            m_ = max(2.0 * k, 1.3 * kl) + 0.012 + pad
            if np.all(p.lo - m_ <= hi) and np.all(p.hi + m_ >= lo):
                out.append((m, p, k))
        return out

    @staticmethod
    def eval_ops(ops, P, far=1.0):
        d = np.full(len(P), far, dtype=F)
        for m, p, k in ops:
            dp = p(P)
            if m == 'add':
                d = smin(d, dp, k)
            else:
                d = smax(d, -dp, k)
        return d

    def __call__(self, P):
        P = np.asarray(P, dtype=F)
        lo, hi = P.min(axis=0), P.max(axis=0)
        return self.eval_ops(self.cull(lo, hi), P)


# ----------------------------------------------------------------------------
# Surface nets
# ----------------------------------------------------------------------------
def surface_nets(scene, h, lo=None, hi=None, block=40, project=True, verbose=True):
    """Return (verts[N,3], quads[M,4]) of the zero iso-surface."""
    if lo is None:
        lo, hi = scene.bounds()
        lo = lo - 4 * h
        hi = hi + 4 * h
    lo = v3(lo)
    hi = v3(hi)
    ns = np.ceil((hi - lo) / h).astype(np.int64) + 1  # samples per axis
    nc = ns - 1                                         # cells per axis
    all_keys, all_pos, all_quads = [], [], []
    half_diag = 0.5 * np.sqrt(3) * block * h
    nblocks = 0
    for bi in range(0, nc[0], block):
        for bj in range(0, nc[1], block):
            for bk in range(0, nc[2], block):
                c0 = np.array([bi, bj, bk])
                c1 = np.minimum(c0 + block, nc)
                blo = lo + c0 * h
                bhi = lo + c1 * h
                ops = scene.cull(blo, bhi, pad=2 * h)
                if not any(m == 'add' for m, _, _ in ops):
                    continue
                ctr = 0.5 * (blo + bhi)
                dc = SDFScene.eval_ops(ops, ctr[None, :])[0]
                if abs(dc) > 1.6 * half_diag + 4 * h:
                    continue
                nblocks += 1
                xs = lo[0] + h * np.arange(c0[0], c1[0] + 1)
                ys = lo[1] + h * np.arange(c0[1], c1[1] + 1)
                zs = lo[2] + h * np.arange(c0[2], c1[2] + 1)
                X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
                P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
                D = SDFScene.eval_ops(ops, P).reshape(X.shape)
                D[D == 0] = 1e-9
                S = D < 0
                if S.all() or not S.any():
                    continue
                k, p, q = _block_nets(D, S, c0, nc, h, lo)
                if k is None:
                    continue
                if project and len(p):
                    p = _project(ops, p, h)
                all_keys.append(k)
                all_pos.append(p)
                if q is not None and len(q):
                    all_quads.append(q)
    keys = np.concatenate(all_keys)
    pos = np.concatenate(all_pos)
    quads = np.concatenate(all_quads)
    order = np.argsort(keys)
    sk = keys[order]
    qi = np.searchsorted(sk, quads)
    qi = np.clip(qi, 0, len(sk) - 1)
    ok = np.all(sk[qi] == quads, axis=1)
    if verbose and np.count_nonzero(~ok):
        bad = quads[~ok]
        miss = bad[sk[qi[~ok]] != bad]
        nyz = nc[1] * nc[2]
        gi = np.stack([miss // nyz, (miss // nc[2]) % nc[1], miss % nc[2]], 1)
        print("  missing cells sample:", np.unique(gi // block, axis=0)[:8], (lo + gi * h)[:5])
    quads = order[qi[ok]]
    if verbose:
        print(f"  surface nets: blocks={nblocks} verts={len(pos)} quads={len(quads)} dropped={np.count_nonzero(~ok)}")
    return pos, quads


def _block_nets(D, S, c0, nc, h, lo):
    sx, sy, sz = D.shape
    # cell activity: any sign change among 8 corners
    cs = (S[:-1, :-1, :-1].astype(np.int8) + S[1:, :-1, :-1] + S[:-1, 1:, :-1] + S[1:, 1:, :-1]
          + S[:-1, :-1, 1:] + S[1:, :-1, 1:] + S[:-1, 1:, 1:] + S[1:, 1:, 1:])
    active = (cs > 0) & (cs < 8)
    if not active.any():
        return None, None, None
    acc = np.zeros(active.shape + (3,), dtype=F)
    cnt = np.zeros(active.shape, dtype=F)

    # x-edges
    a, b = D[:-1, :, :], D[1:, :, :]
    ch = (a < 0) != (b < 0)
    with np.errstate(divide='ignore', invalid='ignore'):
        t = np.where(ch, a / (a - b), 0.0)
    for dj in (0, 1):
        for dk in (0, 1):
            m = ch[:, dj:sy - 1 + dj, dk:sz - 1 + dk]
            tt = t[:, dj:sy - 1 + dj, dk:sz - 1 + dk]
            acc[..., 0] += np.where(m, tt, 0)
            acc[..., 1] += np.where(m, dj, 0)
            acc[..., 2] += np.where(m, dk, 0)
            cnt += m
    # y-edges
    a, b = D[:, :-1, :], D[:, 1:, :]
    ch = (a < 0) != (b < 0)
    with np.errstate(divide='ignore', invalid='ignore'):
        t = np.where(ch, a / (a - b), 0.0)
    for di in (0, 1):
        for dk in (0, 1):
            m = ch[di:sx - 1 + di, :, dk:sz - 1 + dk]
            tt = t[di:sx - 1 + di, :, dk:sz - 1 + dk]
            acc[..., 0] += np.where(m, di, 0)
            acc[..., 1] += np.where(m, tt, 0)
            acc[..., 2] += np.where(m, dk, 0)
            cnt += m
    # z-edges
    a, b = D[:, :, :-1], D[:, :, 1:]
    ch = (a < 0) != (b < 0)
    with np.errstate(divide='ignore', invalid='ignore'):
        t = np.where(ch, a / (a - b), 0.0)
    for di in (0, 1):
        for dj in (0, 1):
            m = ch[di:sx - 1 + di, dj:sy - 1 + dj, :]
            tt = t[di:sx - 1 + di, dj:sy - 1 + dj, :]
            acc[..., 0] += np.where(m, di, 0)
            acc[..., 1] += np.where(m, dj, 0)
            acc[..., 2] += np.where(m, tt, 0)
            cnt += m

    ci, cj, ck = np.nonzero(active)
    local = acc[ci, cj, ck] / cnt[ci, cj, ck][:, None]
    gidx = np.stack([ci, cj, ck], axis=1) + c0
    pos = lo + (gidx + local) * h
    nyz = nc[1] * nc[2]
    keys = gidx[:, 0] * nyz + gidx[:, 1] * nc[2] + gidx[:, 2]

    def key(i, j, k):
        return i * nyz + j * nc[2] + k

    quads = []
    # x-edges owned: i in [0,Bx), j in [0,By), k in [0,Bz)
    a, b = D[:-1, :-1, :-1], D[1:, :-1, :-1]
    ch = (a < 0) != (b < 0)
    ii, jj, kk = np.nonzero(ch)
    if len(ii):
        inside = a[ii, jj, kk] < 0
        gi, gj, gk = ii + c0[0], jj + c0[1], kk + c0[2]
        good = (gj > 0) & (gk > 0)
        gi, gj, gk, inside = gi[good], gj[good], gk[good], inside[good]
        q = np.stack([key(gi, gj - 1, gk - 1), key(gi, gj, gk - 1), key(gi, gj, gk), key(gi, gj - 1, gk)], 1)
        q[~inside] = q[~inside][:, ::-1]
        quads.append(q)
    a, b = D[:-1, :-1, :-1], D[:-1, 1:, :-1]
    ch = (a < 0) != (b < 0)
    ii, jj, kk = np.nonzero(ch)
    if len(ii):
        inside = a[ii, jj, kk] < 0
        gi, gj, gk = ii + c0[0], jj + c0[1], kk + c0[2]
        good = (gi > 0) & (gk > 0)
        gi, gj, gk, inside = gi[good], gj[good], gk[good], inside[good]
        q = np.stack([key(gi - 1, gj, gk - 1), key(gi - 1, gj, gk), key(gi, gj, gk), key(gi, gj, gk - 1)], 1)
        q[~inside] = q[~inside][:, ::-1]
        quads.append(q)
    a, b = D[:-1, :-1, :-1], D[:-1, :-1, 1:]
    ch = (a < 0) != (b < 0)
    ii, jj, kk = np.nonzero(ch)
    if len(ii):
        inside = a[ii, jj, kk] < 0
        gi, gj, gk = ii + c0[0], jj + c0[1], kk + c0[2]
        good = (gi > 0) & (gj > 0)
        gi, gj, gk, inside = gi[good], gj[good], gk[good], inside[good]
        q = np.stack([key(gi - 1, gj - 1, gk), key(gi, gj - 1, gk), key(gi, gj, gk), key(gi - 1, gj, gk)], 1)
        q[~inside] = q[~inside][:, ::-1]
        quads.append(q)
    quads = np.concatenate(quads) if quads else None
    return keys, pos, quads


def _project(ops, p, h, iters=2):
    e = 0.25 * h
    for _ in range(iters):
        d = SDFScene.eval_ops(ops, p)
        g = np.zeros_like(p)
        for ax in range(3):
            o = np.zeros(3)
            o[ax] = e
            g[:, ax] = (SDFScene.eval_ops(ops, p + o) - SDFScene.eval_ops(ops, p - o)) / (2 * e)
        gl2 = np.maximum(np.einsum('ij,ij->i', g, g), 1e-8)
        step = (d / gl2)[:, None] * g
        # never move a vertex more than half a voxel
        sl = np.linalg.norm(step, axis=1)
        step *= np.minimum(1.0, (0.5 * h) / np.maximum(sl, 1e-12))[:, None]
        p = p - step
    return p


def mesh_cleanup(verts, quads):
    """Remove unused vertices."""
    used = np.zeros(len(verts), bool)
    used[quads.ravel()] = True
    remap = -np.ones(len(verts), np.int64)
    remap[used] = np.arange(used.sum())
    return verts[used], remap[quads]
