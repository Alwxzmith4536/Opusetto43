"""
Procedural textures painted with numpy (no image files needed).
"""
import numpy as np


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def power_eye(size=512, iris_r=0.36, srgb_out=False):
    """
    Power's eye: golden-yellow iris that turns orange at the rim,
    a red cross-hair 'pupil' (ring + cross) and a white sclera.
    UV centre (0.5, 0.5) is the front of the eyeball; returns RGBA float array
    in *linear* colour space, shape (size, size, 4), row 0 = bottom (Blender).
    """
    v, u = np.mgrid[0:size, 0:size]
    u = (u + 0.5) / size - 0.5
    v = (v + 0.5) / size - 0.5
    r = np.sqrt(u * u + v * v)
    ang = np.arctan2(v, u)
    rr = r / iris_r  # 1.0 at iris border

    def lin(c):
        c = np.asarray(c, float)
        return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

    sclera = lin((0.96, 0.95, 0.93))
    sclera_edge = lin((0.86, 0.80, 0.80))
    img = sclera[None, None, :] * (1 - _smooth(0.30, 0.5, r))[..., None] \
        + sclera_edge[None, None, :] * _smooth(0.30, 0.5, r)[..., None]

    # iris gradient + radial fibres
    inner = lin((1.00, 0.93, 0.38))
    outer = lin((1.00, 0.64, 0.12))
    t = _smooth(0.15, 1.0, rr)[..., None]
    iris = inner * (1 - t) + outer * t
    rng = np.random.default_rng(7)
    k = rng.normal(size=64)
    fib = np.zeros_like(ang)
    for i in range(1, 40):
        fib += k[i] * np.sin(i * 3 * ang + k[i + 20] * 3.0) / i ** 0.6
    fib = fib / np.abs(fib).max()
    iris = iris * (0.88 + 0.12 * fib[..., None])
    # dark limbal ring
    limb = _smooth(0.82, 1.0, rr)[..., None]
    iris = iris * (1 - 0.5 * limb)
    # red cross-hair: ring + cross + small centre
    red = lin((0.80, 0.03, 0.03))
    ring = np.exp(-((rr - 0.50) / 0.055) ** 2)
    cross_w = 0.032
    cross = (np.exp(-(u / (iris_r * cross_w)) ** 2) + np.exp(-(v / (iris_r * cross_w)) ** 2))
    cross = np.clip(cross, 0, 1) * (1 - _smooth(0.78, 0.88, rr))
    centre = np.exp(-(rr / 0.12) ** 2)
    m = np.clip(ring + cross + centre, 0, 1)[..., None]
    iris = iris * (1 - m) + red * m
    # soft upper shadow from the lid
    a = _smooth(0.97, 1.02, rr)[..., None]
    img = iris * (1 - a) + img * a
    shade = 1 - 0.35 * _smooth(0.05, 0.30, v)[..., None] * _smooth(-0.1, 0.4, -np.abs(u) + 0.3)[..., None]
    img = img * shade
    out = np.ones((size, size, 4), np.float32)
    if srgb_out:
        img = np.clip(img, 0, 1)
        img = np.where(img <= 0.0031308, img * 12.92, 1.055 * img ** (1 / 2.4) - 0.055)
    out[..., :3] = img
    return out


def fabric_noise(size=512, seed=1):
    """Tileable woven fabric height map (0..1)."""
    y, x = np.mgrid[0:size, 0:size] / size
    w = 0.5 + 0.25 * np.sin(2 * np.pi * x * 96) * np.sign(np.sin(2 * np.pi * y * 48)) \
        + 0.25 * np.sin(2 * np.pi * y * 96) * np.sign(np.sin(2 * np.pi * x * 48))
    rng = np.random.default_rng(seed)
    n = rng.normal(size=(size // 8, size // 8))
    n = np.kron(n, np.ones((8, 8)))
    return np.clip(w + 0.05 * n, 0, 1).astype(np.float32)
