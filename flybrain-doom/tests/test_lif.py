import numpy as np
import pytest

from flydoom.brain.connectome import Connectome
from flydoom.brain.lif import LIFNetwork, LIFParams


def pair(weight_mv, params=None, seed=0):
    c = Connectome()
    a = c.add_neurons("A", 1)
    b = c.add_neurons("B", 1)
    c.add_edges(a, b, weight_mv, plastic="ab")
    return LIFNetwork(c, params, seed=seed), a, b


@pytest.mark.parametrize("dt", [0.1, 0.25, 0.5, 1.0])
def test_psp_matches_analytic_solution(dt):
    # g kick of 30 mV with tau=5, t_mbr=20: peak depolarisation 30 * 0.1575 = 4.725 mV
    net, a, b = pair(30.0, LIFParams(dt=dt))
    net.v[a] = -40.0  # above threshold: spikes on the first step
    peak = -np.inf
    for _ in range(int(40 / dt)):
        net.run(dt)
        peak = max(peak, float(net.v[b[0]]))
    assert peak + 52.0 == pytest.approx(4.725, abs=0.01)


def test_poisson_drive_sets_rate():
    net, a, b = pair(0.0)
    net.set_rate(a, 50.0)
    counts = net.run(4000.0)
    assert 35 <= counts[a[0]] / 4.0 <= 65


def test_strong_synapse_relays_spikes_after_the_delay():
    net, a, b = pair(60.0)
    net.v[a] = -40.0
    counts, (steps, ids) = net.run(30.0, record=np.array([True, True]))
    t_a = steps[ids == a[0]].min() * net.p.dt
    t_b = steps[ids == b[0]].min() * net.p.dt
    assert counts[b[0]] == 1
    assert t_b - t_a >= net.p.delay - 1e-9


def test_inhibition_suppresses_firing():
    c = Connectome()
    drive = c.add_neurons("drive", 1)
    inh = c.add_neurons("inh", 1)
    target = c.add_neurons("target", 1)
    c.add_edges(drive, target, 40.0)
    c.add_edges(inh, target, -200.0)
    net = LIFNetwork(c, seed=1)
    net.set_rate(drive, 80.0)
    base = net.run(2000.0)[target[0]]
    net.reset_state()
    net.set_rate(inh, 200.0)
    with_inh = net.run(2000.0)[target[0]]
    assert base > 20 and with_inh < base / 3


def test_silenced_neuron_never_spikes():
    net, a, b = pair(60.0)
    net.set_rate(a, 100.0)
    net.silence(b)
    counts = net.run(500.0)
    assert counts[a[0]] > 10 and counts[b[0]] == 0


def test_plastic_weights_can_be_rewritten():
    net, a, b = pair(60.0)
    assert net.get_weights("ab").tolist() == [60.0]
    net.set_weights("ab", np.array([0.0]))
    net.set_rate(a, 100.0)
    assert net.run(500.0)[b[0]] == 0
