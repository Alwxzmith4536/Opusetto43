import math

import numpy as np
import pytest

from flydoom.envs.minidoom import MiniDoomEnv


def test_reset_and_step_shapes():
    env = MiniDoomEnv("basic", seed=0)
    f = env.reset(seed=3)
    assert f.shape == (120, 160, 3) and f.dtype == np.uint8
    res = env.step("left")
    assert res.frame.shape == f.shape
    assert res.reward == -4 / 100.0  # four tics of the -1 living reward, scaled
    assert set(env.motor_map) == {"left", "right", "attack"}


def test_seeded_episodes_repeat():
    env = MiniDoomEnv("basic")
    env.reset(seed=7)
    a = env.monster_azimuths()
    env.reset(seed=8)
    env.reset(seed=7)
    assert env.monster_azimuths() == a


def test_shooting_a_centred_monster_kills_it():
    env = MiniDoomEnv("basic", seed=0)
    env.reset(seed=1)
    # place the monster straight ahead
    env.monsters[0]["pos"] = env.pos + np.array([0.0, 3.0])
    assert abs(env.monster_azimuths()[0]) < 1e-6
    res = env.step("attack")
    assert res.done and res.info["raw_reward"] == 101.0 - 1.0  # the kill ends the episode in its first tic
    assert env.episode_stats()["kills"] == 1


def test_missed_shot_costs_five():
    env = MiniDoomEnv("basic", seed=0)
    env.reset(seed=1)
    env.monsters[0]["pos"] = env.pos + np.array([2.0, 3.0])
    res = env.step("attack")
    assert not res.done and res.info["raw_reward"] == -5.0 - 4.0


def test_azimuth_sign_convention_left_is_negative():
    env = MiniDoomEnv("basic", seed=0)
    env.reset(seed=1)
    env.monsters[0]["pos"] = env.pos + np.array([-1.0, 3.0])
    assert env.monster_azimuths()[0] == pytest.approx(math.degrees(math.atan2(-1.0, 3.0)))


def test_defend_monsters_approach_and_bite():
    env = MiniDoomEnv("defend", seed=0)
    env.reset(seed=2)
    hp = env.health
    for _ in range(200):
        res = env.step(None)
        if res.done:
            break
    assert env.health < hp
