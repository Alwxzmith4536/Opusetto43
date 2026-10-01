import numpy as np

from flydoom.brain.connectome import Connectome
from flydoom.brain.lif import LIFNetwork
from flydoom.brain.plasticity import ActorCriticPlasticity, PlasticityConfig


def tiny():
    c = Connectome()
    kc = c.add_neurons("KC", 10)
    act = {"left": c.add_neurons("MBON:left", 2), "right": c.add_neurons("MBON:right", 2)}
    pos = c.add_neurons("MBON:value+", 2)
    neg = c.add_neurons("MBON:value-", 2)
    c.connect_all(kc, np.concatenate(list(act.values())), 1.0, plastic="actor")
    c.connect_all(kc, np.concatenate([pos, neg]), 1.0, plastic="critic")
    net = LIFNetwork(c, seed=0)
    pl = ActorCriticPlasticity(net, kc, act, pos, neg, {"actor": 3.0, "critic": 3.0},
                               PlasticityConfig(lr_actor=0.5, lr_critic=0.5, ref_active=2.0))
    return net, pl, kc, act, pos, neg


def test_reward_strengthens_chosen_action_from_active_kcs_only():
    net, pl, kc, act, pos, neg = tiny()
    counts = np.zeros(net.n, dtype=np.int32)
    counts[kc[:2]] = 3  # two active Kenyon cells
    pl.accumulate(counts, action=0, probs=np.array([0.5, 0.5]))
    w0 = net.get_weights("actor")
    pl.apply_dopamine(+1.0)
    dw = net.get_weights("actor") - w0
    pre, post = net.plastic["actor"]["pre"], net.plastic["actor"]["post"]
    to_left = np.isin(post, act["left"])
    active = np.isin(pre, kc[:2])
    assert (dw[active & to_left] > 0).all()
    assert (dw[active & ~to_left] < 0).all()
    assert np.allclose(dw[~active], 0.0)


def test_punishment_lowers_value_and_zero_dopamine_changes_nothing():
    net, pl, kc, act, pos, neg = tiny()
    counts = np.zeros(net.n, dtype=np.int32)
    counts[kc[:4]] = 2
    v0 = pl.critic_drive(counts, value_mv=0.5)
    pl.accumulate(counts, action=None, probs=np.array([0.5, 0.5]))
    before = net.get_weights("critic")
    pl.apply_dopamine(0.0)
    assert np.array_equal(before, net.get_weights("critic"))
    pl.apply_dopamine(-1.0)
    assert pl.critic_drive(counts, value_mv=0.5) < v0


def test_weights_stay_within_bounds():
    net, pl, kc, act, pos, neg = tiny()
    counts = np.zeros(net.n, dtype=np.int32)
    counts[kc] = 3
    pl.accumulate(counts, action=1, probs=np.array([0.5, 0.5]))
    for _ in range(50):
        pl.apply_dopamine(+1.0)
    w = net.get_weights("actor")
    assert w.min() >= 0.0 and w.max() <= 3.0
