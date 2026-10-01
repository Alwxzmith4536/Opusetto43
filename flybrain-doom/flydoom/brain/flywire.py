"""The real fly brain: FlyWire v783 connectome (Dorkenwald et al. 2024; Schlegel et al. 2024).

Data: the public tables used by Shiu et al. (2024) - ``Completeness_783.csv`` (neuron order)
and ``Connectivity_783.parquet`` (presynaptic index, postsynaptic index, signed synapse
count) - plus FlyWire's cell-type annotations (``Supplemental_file1_neuron_annotations.tsv``).
``python -m flydoom fetch-flywire`` downloads both.

How the Doom-playing loop attaches to the real wiring:

* **Vision in** - the LIF model cannot carry graded optic-lobe signals (photoreceptor drive
  dies out in the medulla; see :func:`connectome_gates`), so the functional optic-lobe model
  drives the real *visual projection neurons*: LC/LPLC lobula columnar types by their known
  tuning (LC4/LPLC2/LC6/LC16 looming; LC10a/LC11/LC18 small objects; ...), the mushroom-body
  visual inputs (aMe12, MTe30, MTe32, LTe25) and the lobula-plate tangential cells (HS/H2).
  Each real neuron gets the eye of its hemisphere and a receptive-field azimuth in that eye.
* **Dopamine** - the teaching signal is delivered to the real PAM (reward) and PPL1
  (punishment) dopamine neurons, and their spike counts are read back as the third factor.
* **Motor out** - descending neurons are read out by a small ventral-nerve-cord (VNC) layer
  that is *not* part of the connectome: each motor primitive has VNC units with innate fixed
  input from the DNs known to drive it (DNa01/DNa02 ipsilateral steering, DNp09/P9 forward,
  MDN backward, DNp01 giant fibre -> "attack") plus plastic synapses from all descending
  neurons. Value units read the same DNs. So the brain itself is the unmodified connectome;
  what learns is the DN -> VNC interface, gated by the real dopamine neurons.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

import numpy as np

from .blueprint import MOTOR_PRIMITIVES, BrainBlueprint
from .connectome import Connectome
from .lif import LIFNetwork, LIFParams
from ..senses.optic_lobe import FEATURES
from ..senses.vpn import VPNLayout

# approximate functional assignment of real visual projection neuron types to optic-lobe channels
VPN_FEATURES: dict[str, str] = {
    "LC4": "loom", "LPLC2": "loom", "LC6": "loom", "LC16": "loom", "LPLC1": "loom",
    "LC10a": "object", "LC11": "object", "LC18": "object", "LC21": "object", "LC26": "object",
    "LC12": "figure", "LC15": "figure", "LC9": "figure", "LC17": "figure", "LC22": "figure",
    "LC24": "dark", "LC25": "bright",
    "aMe12": "color", "MTe32": "on", "MTe30": "off", "LTe25": "dark",
    "HSE": "motion_r", "HSN": "motion_r", "HSS": "motion_r", "H2": "motion_l",
}

# descending neurons with a known motor role, by primitive (side None = both hemispheres)
DN_MOTOR: dict[str, list[tuple[str, str | None]]] = {
    "left": [("DNa02", "left"), ("DNa01", "left")],
    "right": [("DNa02", "right"), ("DNa01", "right")],
    "forward": [("DNp09", None)],
    "backward": [("MDN", None)],
    "attack": [("DNp01", None)],
}


def _read_annotations(path: str):
    import pandas as pd
    cols = ["root_id", "super_class", "cell_class", "cell_type", "side"]
    ann = pd.read_csv(path, sep="\t", usecols=cols, low_memory=False)
    return ann.drop_duplicates("root_id").set_index("root_id")


def load_flywire(data_dir: str, annotations: str | None = None, region: str = "central",
                 w_syn: float = 0.275, version: str = "783") -> Connectome:
    """Load FlyWire into a :class:`Connectome` with weights ``signed count x w_syn`` (mV).

    ``region='central'`` drops optic-lobe intrinsic neurons and photoreceptors (~88k neurons)
    but keeps visual projection neurons, which is where vision is injected; ``'full'`` keeps
    all 138,639 neurons (needed for the photoreceptor gate).
    """
    import pandas as pd

    comp = pd.read_csv(os.path.join(data_dir, f"Completeness_{version}.csv"), index_col=0)
    ids = comp.index.values.astype(np.int64)
    con = pd.read_parquet(os.path.join(data_dir, f"Connectivity_{version}.parquet"),
                          columns=["Presynaptic_Index", "Postsynaptic_Index", "Excitatory x Connectivity"])
    n = ids.size
    cell_type = np.full(n, "", dtype=object)
    side = np.full(n, "", dtype=object)
    super_class = np.full(n, "", dtype=object)
    if annotations:
        ann = _read_annotations(annotations)
        cell_type = ann["cell_type"].reindex(ids).fillna("").astype(str).values.astype(object)
        side = ann["side"].reindex(ids).fillna("").astype(str).values.astype(object)
        super_class = ann["super_class"].reindex(ids).fillna("").astype(str).values.astype(object)
    keep = np.ones(n, dtype=bool)
    if region == "central":
        if not annotations:
            raise ValueError("region='central' needs the annotation table to know which neurons are optic-lobe")
        keep = (super_class != "optic") & ~np.isin(cell_type, ["R1-6", "R7", "R8"])
    elif region != "full":
        raise ValueError("region must be 'central' or 'full'")
    new_index = np.full(n, -1, dtype=np.int64)
    new_index[keep] = np.arange(int(keep.sum()))
    pre = con["Presynaptic_Index"].values
    post = con["Postsynaptic_Index"].values
    ok = keep[pre] & keep[post]
    c = Connectome(meta={"source": f"FlyWire v{version}", "region": region, "data_dir": data_dir})
    c.n = int(keep.sum())
    c.cell_type = list(cell_type[keep])
    c.side = list(side[keep])
    c.neuron_ids = ids[keep]
    c.meta["super_class"] = super_class[keep]
    c.add_edges(new_index[pre[ok]], new_index[post[ok]],
                con["Excitatory x Connectivity"].values[ok].astype(np.float32) * np.float32(w_syn))
    return c


@dataclass
class FlyWireBrainConfig:
    vnc_per_action: int = 10
    critic_per_valence: int = 12
    w_innate: float = 12.0  # mV, known DN -> its VNC motor units
    w_dn_vnc_init: float = 0.5  # mV, plastic DN -> VNC (rescaled by calibration)
    w_dn_vnc_max: float = 6.0
    tonic_vnc_hz: float = 5.0
    tonic_value_hz: float = 10.0
    vpn_features: dict = field(default_factory=lambda: dict(VPN_FEATURES))
    motor_primitives: tuple[str, ...] = MOTOR_PRIMITIVES


def _types(conn: Connectome) -> np.ndarray:
    return np.asarray(conn.cell_type, dtype=object)


def build_flywire_brain(conn: Connectome, eye, seed: int = 0,
                        config: FlyWireBrainConfig | None = None) -> BrainBlueprint:
    """Attach eyes, dopamine teaching signal and a learnable VNC readout to the real connectome.

    Mutates ``conn`` by appending VNC/value units and their synapses (the connectome's own
    neurons and synapses are left untouched).
    """
    cfg = config or FlyWireBrainConfig()
    rng = np.random.default_rng(seed)
    types = _types(conn)
    sides = np.asarray(conn.side, dtype=object)
    supers = conn.meta.get("super_class")
    # ---- visual projection neurons, one receptive field each
    vpn_idx, feat, eyes, az = [], [], [], []
    for t, f in cfg.vpn_features.items():
        for s, e in (("left", "L"), ("right", "R")):
            idx = np.flatnonzero((types == t) & (sides == s))
            if idx.size == 0:
                continue
            lo, hi = eye.azimuth[eye.eye == e].min(), eye.azimuth[eye.eye == e].max()
            vpn_idx.append(idx)
            feat.append(np.full(idx.size, FEATURES.index(f)))
            eyes.append(np.full(idx.size, e))
            az.append(rng.uniform(lo, hi, size=idx.size))
    if not vpn_idx:
        raise ValueError("no visual projection neuron types found - are annotations loaded?")
    vpn_idx = np.concatenate(vpn_idx)
    layout = VPNLayout(np.concatenate(feat), np.concatenate(eyes), np.concatenate(az))
    # ---- dopamine neurons
    pam = np.flatnonzero(np.array([t.startswith("PAM") for t in types]))
    ppl1 = np.flatnonzero(np.array([t.startswith("PPL1") for t in types]))
    # ---- descending neurons = the brain's output = state for the learned readout
    if supers is not None:
        dn = np.flatnonzero(np.asarray(supers, dtype=object) == "descending")
    else:
        dn = np.flatnonzero(np.array([t.startswith("DN") or t == "MDN" for t in types]))
    # ---- VNC readout units (appended; not part of the connectome)
    actor, innate = {}, {}
    for name in cfg.motor_primitives:
        actor[name] = conn.add_neurons(f"VNC:{name}", cfg.vnc_per_action, cell_type="VNC_motor")
        src = []
        for t, s in DN_MOTOR.get(name, []):
            m = types == t
            if s is not None:
                m &= sides == s
            src.append(np.flatnonzero(m))
        innate[name] = np.concatenate(src) if src else np.zeros(0, dtype=np.int64)
        if innate[name].size:
            conn.connect_all(innate[name], actor[name], cfg.w_innate)
    critic_pos = conn.add_neurons("VNC:value+", cfg.critic_per_valence, cell_type="value_appetitive")
    critic_neg = conn.add_neurons("VNC:value-", cfg.critic_per_valence, cell_type="value_aversive")
    all_actor = np.concatenate(list(actor.values()))
    conn.connect_all(dn, all_actor, cfg.w_dn_vnc_init, plastic="actor")
    conn.connect_all(dn, np.concatenate([critic_pos, critic_neg]), cfg.w_dn_vnc_init, plastic="critic")
    conn.groups.update({"DAN:PAM": pam, "DAN:PPL1": ppl1, "DN": dn, "VPN": vpn_idx})
    for name, idx in innate.items():
        conn.groups[f"DN:{name}"] = idx
    tonic = [(all_actor, cfg.tonic_vnc_hz), (np.concatenate([critic_pos, critic_neg]), cfg.tonic_value_hz)]
    return BrainBlueprint(
        connectome=conn, vpn_idx=vpn_idx, vpn_layout=layout, motor=actor, actor=actor,
        critic_pos=critic_pos, critic_neg=critic_neg, state_idx=dn, dan_reward=pam, dan_punish=ppl1,
        tonic=tonic, weight_max={"actor": cfg.w_dn_vnc_max, "critic": cfg.w_dn_vnc_max},
        state_label="descending neurons",
        name=f"FlyWire v783 ({conn.meta.get('region', '?')})",
        notes=(f"{conn.n:,} neurons incl. {2 * cfg.critic_per_valence + len(actor) * cfg.vnc_per_action} "
               f"VNC/value units; {vpn_idx.size} real VPNs driven; {dn.size} DNs read out; "
               f"{pam.size} PAM + {ppl1.size} PPL1 dopamine neurons"))


# ------------------------------------------------------------------- gates
def connectome_gates(conn: Connectome, duration_ms: float = 200.0, trials: int = 5, seed: int = 0,
                     rate_hz: float = 100.0) -> list:
    """Stimulus -> response checks on the unmodified connectome (no learning involved)."""
    from ..engine import stats
    from ..engine.gates import GateResult

    types = _types(conn)
    sides = np.asarray(conn.side, dtype=object)
    supers = np.asarray(conn.meta.get("super_class", np.full(conn.n, "", dtype=object)), dtype=object)
    net = LIFNetwork(conn, LIFParams(), seed=seed)
    dn = np.flatnonzero(supers == "descending")

    def rates(stim: np.ndarray) -> list[np.ndarray]:
        out = []
        for _ in range(trials):
            net.reset_state()
            net.clear_rates()
            net.set_rate(stim, rate_hz)
            out.append(net.run(duration_ms) / (duration_ms * 1e-3))
        net.clear_rates()
        return out

    def pick(t, s=None):
        m = np.isin(types, [t] if isinstance(t, str) else t)
        if s is not None:
            m &= sides == s
        return np.flatnonzero(m)

    gates = []
    photo = pick(["R1-6"])
    if photo.size:
        r = rates(photo)
        frac = [float((x[dn] > 0).mean()) for x in r]
        lam = pick(["L1", "L2", "L3"])
        lc = pick(list(VPN_FEATURES))
        summary = {"photoreceptors": int(photo.size), "lamina_active_frac": float(np.mean([(x[lam] > 0).mean() for x in r])),
                   "vpn_active_frac": float(np.mean([(x[lc] > 0).mean() for x in r])),
                   "dn_active_frac": float(np.mean(frac))}
        gates.append(GateResult(
            "C1 photoreceptor -> descending neuron propagation", summary["dn_active_frac"] > 0.01,
            f"driving all R1-6 photoreceptors at {rate_hz:.0f} Hz activates >1% of descending neurons "
            "in the pure LIF connectome (expected to FAIL: early fly vision is graded, which is why "
            "flydoom injects vision at the visual projection neurons)", {"summary": summary}))
    steer = {s: pick("DNa02", s) for s in ("left", "right")}
    lc_types = [t for t, f in VPN_FEATURES.items() if t.startswith(("LC", "LPLC"))]
    if steer["left"].size and steer["right"].size:
        res = {}
        for s in ("left", "right"):
            r = rates(pick(lc_types, s))
            res[s] = np.array([x[steer["left"]].mean() - x[steer["right"]].mean() for x in r])
        cmp = stats.compare(res["left"], res["right"])
        summary = {"DNa02 L-R (Hz), left-eye LC drive": stats.summary(res["left"]),
                   "DNa02 L-R (Hz), right-eye LC drive": stats.summary(res["right"]), "test": cmp}
        gates.append(GateResult(
            "C2 lateralised visuomotor pathway", bool(cmp["p"] < 0.05 and cmp["mean_diff"] > 0),
            "LC/LPLC drive in the left eye pushes DNa02 (ipsilateral steering) activity to the left "
            "more than right-eye drive does", {"summary": summary}))
    gf = pick("DNp01")
    loom = pick(["LC4", "LPLC2"])
    if gf.size and loom.size:
        r = rates(loom)
        base = rates(np.zeros(0, dtype=np.int64))
        summary = {"giant_fibre_hz": float(np.mean([x[gf].mean() for x in r])),
                   "baseline_hz": float(np.mean([x[gf].mean() for x in base]))}
        gates.append(GateResult(
            "C3 looming -> giant fibre", summary["giant_fibre_hz"] > 20 and summary["baseline_hz"] < 1,
            "driving looming detectors LC4 + LPLC2 makes the giant fibre (DNp01) fire > 20 Hz from silence",
            {"summary": summary}))
    return gates
