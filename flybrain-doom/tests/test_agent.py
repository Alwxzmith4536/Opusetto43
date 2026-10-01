import numpy as np
import pytest

from flydoom.engine.runner import ExperimentConfig, RandomPolicy, build_agent, make_env, run_episode
from flydoom.brain.synthetic import SyntheticBrainConfig


@pytest.fixture(scope="module")
def setup():
    cfg = ExperimentConfig(env="minidoom:basic", calibration_frames=60,
                           brain_config=SyntheticBrainConfig(n_kc=400))
    env = make_env(cfg.env, seed=0)
    return cfg, env


def test_agent_plays_with_valid_actions(setup):
    cfg, env = setup
    agent = build_agent(cfg, env)
    assert agent.available == ["left", "right", "attack"]
    ep = run_episode(agent, env, seed=11, learn=False, record_aim=True)
    assert ep["steps"] > 0
    assert {a for _, a in ep["aim"]} <= {"left", "right", "attack"}


def test_learning_changes_weights_and_dopamine_lesion_blocks_it(setup):
    cfg, env = setup
    agent = build_agent(cfg, env)
    w0 = agent.weights()
    for s in range(3):
        run_episode(agent, env, seed=s, learn=True)
    changed = any(not np.allclose(w0[k], v) for k, v in agent.weights().items())
    assert changed

    lesioned = build_agent(cfg, env, lesion="dopamine")
    w0 = lesioned.weights()
    for s in range(3):
        run_episode(lesioned, env, seed=s, learn=True)
    assert all(np.allclose(w0[k], v) for k, v in lesioned.weights().items())


def test_frozen_evaluation_does_not_learn(setup):
    cfg, env = setup
    agent = build_agent(cfg, env)
    w0 = agent.weights()
    run_episode(agent, env, seed=4, learn=False)
    assert all(np.array_equal(w0[k], v) for k, v in agent.weights().items())
    assert agent.cfg.learning  # the switch is restored afterwards


def test_aversive_conditioning_lowers_value_of_the_punished_stimulus(setup):
    cfg, env = setup
    agent = build_agent(cfg, env)
    from flydoom.engine.experiment import _monster_frames
    left, right = _monster_frames(env, 6, seed=99)
    v_before = np.mean([agent.value(agent.present(f), agent.cfg.window_ms) for f in left])
    for _ in range(8):
        agent.condition(left[0], us=-1.0)
    v_after = np.mean([agent.value(agent.present(f), agent.cfg.window_ms) for f in left])
    assert v_after < v_before - 0.05


def test_random_policy_baseline(setup):
    cfg, env = setup
    ep = run_episode(RandomPolicy(env.motor_map, seed=0), env, seed=3)
    assert ep["raw_return"] < 101
