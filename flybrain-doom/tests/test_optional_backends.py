"""Tests that need optional pieces: ViZDoom (pip install vizdoom) and the FlyWire tables.

Set FLYDOOM_FLYWIRE_DIR (folder with Connectivity_783.parquet) and FLYDOOM_FLYWIRE_ANN (path to
Supplemental_file1_neuron_annotations.tsv) to run the connectome tests.
"""
import os

import pytest

from flydoom.envs.vizdoom_env import vizdoom_available

needs_vizdoom = pytest.mark.skipif(not vizdoom_available(), reason="vizdoom not installed")
FW_DIR = os.environ.get("FLYDOOM_FLYWIRE_DIR")
FW_ANN = os.environ.get("FLYDOOM_FLYWIRE_ANN")
needs_flywire = pytest.mark.skipif(not (FW_DIR and FW_ANN and os.path.exists(FW_DIR)),
                                   reason="FlyWire tables not configured")


@needs_vizdoom
def test_vizdoom_basic_runs_and_is_seeded():
    from flydoom.envs.vizdoom_env import VizDoomEnv

    env = VizDoomEnv("basic", seed=0)
    f = env.reset(seed=10)
    assert f.shape == (120, 160, 3)
    az = env.monster_azimuths()
    res = env.step("left")
    assert res.reward < 0 and not res.done
    env.reset(seed=10)
    assert env.monster_azimuths() == az
    assert set(env.motor_map) == {"left", "right", "attack"}
    env.close()


@needs_flywire
def test_flywire_visuomotor_gates():
    from flydoom.brain.flywire import connectome_gates, load_flywire

    conn = load_flywire(FW_DIR, FW_ANN, region="central")
    assert conn.n > 40_000
    gates = {g.name: g for g in connectome_gates(conn, duration_ms=150, trials=3)}
    assert gates["C2 lateralised visuomotor pathway"].passed
    assert gates["C3 looming -> giant fibre"].passed
