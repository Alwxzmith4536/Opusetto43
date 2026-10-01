"""Procedurally generated fly-like brain, wired after known Drosophila circuit motifs.

    VPNs (LC/LPLC-like)  --6 random claws-->  Kenyon cells  <--feedback inhibition--  APL
    Kenyon cells  --plastic-->  actor MBONs (one group per motor primitive)  -->  DN groups
    Kenyon cells  --plastic-->  critic MBONs (appetitive MBON+ / aversive MBON-)
    DN groups  -->  LAL inhibitory interneurons  --|  other DN groups   (winner-take-all)
    PAM (reward) / PPL1 (punishment) dopamine neurons: teaching signal for the plastic synapses
    optional innate reflexes: object VPNs -> ipsilateral steering DNs (LC10a -> DNa02-like
    fixation), looming VPNs -> attack DN (LC4/LPLC2 -> giant-fibre-like)

Mushroom-body numbers are scaled down from the fly (~2,000 KCs per hemisphere, ~7 claws,
~5-10% of KCs active, one APL). Dynamics are the same Shiu et al. LIF model used for the
real connectome, so weights are given in mV of synaptic drive.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .blueprint import MOTOR_PRIMITIVES, BrainBlueprint
from .connectome import Connectome
from ..senses.optic_lobe import FEATURES
from ..senses.vpn import VPNLayout


@dataclass(frozen=True)
class SyntheticBrainConfig:
    n_kc: int = 1500
    kc_claws: int = 6
    kc_locality_deg: float | None = None  # if set, a KC's claws come from VPNs within this azimuth of a centre
    w_vpn_kc: float = 20.0  # mV per VPN spike on a KC claw
    n_apl: int = 20  # APL is one graded neuron in the fly; a pool of spiking units approximates it
    w_kc_apl: float = 1.0
    w_apl_kc: float = -3.0
    actor_per_action: int = 8
    critic_per_valence: int = 12
    w_kc_mbon_init: float = 0.6
    w_kc_mbon_max: float = 3.0
    dn_per_action: int = 10
    w_mbon_dn: float = 10.0
    lal_per_action: int = 2
    w_dn_lal: float = 10.0
    w_lal_dn: float = -4.0
    n_pam: int = 16
    n_ppl1: int = 16
    innate_fixation: float = 0.0  # mV, object VPN -> ipsilateral steering DN
    innate_loom_attack: float = 0.0  # mV, looming VPN -> attack DN
    tonic_dn_hz: float = 5.0  # exploration noise in descending neurons
    tonic_mbon_hz: float = 10.0  # spontaneous MBON activity
    motor_primitives: tuple[str, ...] = MOTOR_PRIMITIVES


def build_synthetic_brain(vpn_layout: VPNLayout, config: SyntheticBrainConfig | None = None,
                          seed: int = 0) -> BrainBlueprint:
    cfg = config or SyntheticBrainConfig()
    rng = np.random.default_rng(seed)
    c = Connectome(meta={"source": "synthetic", "seed": seed, "config": cfg.__dict__})

    vpn = c.add_neurons("VPN", vpn_layout.n, cell_type="VPN")
    for f in sorted(set(vpn_layout.feature.tolist())):
        for side in ("L", "R"):
            m = (vpn_layout.feature == f) & (vpn_layout.eye == side)
            c.groups[f"VPN:{FEATURES[f]}:{side}"] = vpn[m]
    kc = c.add_neurons("KC", cfg.n_kc, cell_type="KC")
    apl = c.add_neurons("APL", cfg.n_apl, cell_type="APL")

    # each KC samples kc_claws distinct VPNs (random combinatorial expansion), optionally from
    # a local patch of visual space around a random centre (retinotopically local KCs)
    claws = []
    for _ in range(cfg.n_kc):
        pool = vpn
        if cfg.kc_locality_deg is not None:
            centre = rng.uniform(vpn_layout.azimuth.min(), vpn_layout.azimuth.max())
            near = np.abs(vpn_layout.azimuth - centre) <= cfg.kc_locality_deg
            if near.sum() >= cfg.kc_claws:
                pool = vpn[near]
        claws.append(rng.choice(pool, size=cfg.kc_claws, replace=False))
    pre = np.concatenate(claws)
    post = np.repeat(kc, cfg.kc_claws)
    w = cfg.w_vpn_kc * rng.lognormal(0.0, 0.25, size=pre.size)
    c.add_edges(pre, post, w)
    c.connect_all(kc, apl, cfg.w_kc_apl)
    c.connect_all(apl, kc, cfg.w_apl_kc)

    actor: dict[str, np.ndarray] = {}
    motor: dict[str, np.ndarray] = {}
    lal: dict[str, np.ndarray] = {}
    for name in cfg.motor_primitives:
        actor[name] = c.add_neurons(f"MBON:{name}", cfg.actor_per_action, cell_type="MBON_actor")
        motor[name] = c.add_neurons(f"DN:{name}", cfg.dn_per_action, cell_type="DN")
        lal[name] = c.add_neurons(f"LAL:{name}", cfg.lal_per_action, cell_type="LAL_inh")
    critic_pos = c.add_neurons("MBON:value+", cfg.critic_per_valence, cell_type="MBON_appetitive")
    critic_neg = c.add_neurons("MBON:value-", cfg.critic_per_valence, cell_type="MBON_aversive")
    pam = c.add_neurons("DAN:PAM", cfg.n_pam, cell_type="PAM")
    ppl1 = c.add_neurons("DAN:PPL1", cfg.n_ppl1, cell_type="PPL1")

    all_actor = np.concatenate([actor[n] for n in cfg.motor_primitives])
    c.connect_all(kc, all_actor, cfg.w_kc_mbon_init, plastic="actor")
    c.connect_all(kc, np.concatenate([critic_pos, critic_neg]), cfg.w_kc_mbon_init, plastic="critic")
    for name in cfg.motor_primitives:
        c.connect_all(actor[name], motor[name], cfg.w_mbon_dn)
        c.connect_all(motor[name], lal[name], cfg.w_dn_lal)
        for other in cfg.motor_primitives:
            if other != name:
                c.connect_all(lal[name], motor[other], cfg.w_lal_dn)

    if cfg.innate_fixation:
        for side, name in (("L", "left"), ("R", "right")):
            if name in motor:
                src = c.groups.get(f"VPN:object:{side}")
                if src is not None:
                    c.connect_all(src, motor[name], cfg.innate_fixation)
    if cfg.innate_loom_attack and "attack" in motor:
        src = np.concatenate([c.groups.get(f"VPN:loom:{s}", np.zeros(0, dtype=np.int64)) for s in "LR"])
        c.connect_all(src, motor["attack"], cfg.innate_loom_attack)

    tonic = [(np.concatenate(list(motor.values())), cfg.tonic_dn_hz),
             (np.concatenate([all_actor, critic_pos, critic_neg]), cfg.tonic_mbon_hz)]
    return BrainBlueprint(
        connectome=c, vpn_idx=vpn, vpn_layout=vpn_layout, motor=motor, actor=actor,
        critic_pos=critic_pos, critic_neg=critic_neg, state_idx=kc, dan_reward=pam,
        dan_punish=ppl1, tonic=tonic,
        weight_max={"actor": cfg.w_kc_mbon_max, "critic": cfg.w_kc_mbon_max},
        name="synthetic-fly", notes=f"{c.n} neurons, {c.n_edges} synapses (procedural)")
