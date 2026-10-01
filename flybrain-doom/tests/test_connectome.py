import numpy as np

from flydoom.brain.connectome import Connectome


def test_groups_edges_and_csr_positions():
    c = Connectome()
    a = c.add_neurons("A", 3, cell_type="KC", side="left")
    b = c.add_neurons("B", 2, cell_type="MBON")
    fixed = c.add_edges([2, 0], [3, 4], [1.0, 2.0])
    plastic = c.connect_all(a, b, 0.5, plastic="kc_mbon")
    assert c.n == 5 and c.n_edges == 2 + 6
    assert list(c.select(cell_type="KC", side="left")) == [0, 1, 2]
    csr, pos = c.to_csr()
    pre, post, w = c.edges()
    # every edge id maps to the CSR slot holding its postsynaptic neuron and weight
    for e in np.concatenate([fixed, plastic]):
        assert csr.indices[pos[e]] == post[e]
        assert csr.data[pos[e]] == w[e]
        assert csr.indptr[pre[e]] <= pos[e] < csr.indptr[pre[e] + 1]
    assert c.plastic_sets["kc_mbon"].size == 6


def test_connect_random_has_no_self_loops():
    c = Connectome()
    x = c.add_neurons("X", 20)
    c.connect_random(x, x, 0.5, 1.0, np.random.default_rng(0))
    pre, post, _ = c.edges()
    assert (pre != post).all() and pre.size > 50


def test_subgraph_remaps_groups_and_plastic_sets():
    c = Connectome()
    a = c.add_neurons("A", 2)
    b = c.add_neurons("B", 2)
    c.connect_all(a, b, 1.0, plastic="p")
    sub = c.subgraph(np.array([True, False, True, True]))
    assert sub.n == 3
    assert list(sub.groups["A"]) == [0] and list(sub.groups["B"]) == [1, 2]
    assert sub.plastic_sets["p"].size == 2
