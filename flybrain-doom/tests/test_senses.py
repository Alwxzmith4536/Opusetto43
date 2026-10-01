import numpy as np

from flydoom.senses.eye import CompoundEye, EyeConfig
from flydoom.senses.optic_lobe import FEATURES, OpticLobe
from flydoom.senses.vpn import VPNEncoder, VPNLayout

CFG = EyeConfig(spacing=4.5, elev_min=-10, elev_max=12)


def frame_with_blob(x_center: int, color=(200, 40, 60), bg=(110, 80, 55), width=10):
    f = np.zeros((120, 160, 3), np.uint8)
    f[:] = bg
    f[45:75, max(0, x_center - width // 2):x_center + width // 2] = color
    return f


def test_two_eyes_with_binocular_overlap():
    eye = CompoundEye((120, 160), CFG)
    left, right = eye.azimuth[eye.eye == "L"], eye.azimuth[eye.eye == "R"]
    assert left.size and right.size
    assert left.min() < -40 and right.max() > 40
    assert left.max() > 0 and right.min() < 0  # both see across the midline
    rows = np.asarray(eye.S.sum(axis=1)).ravel()
    assert np.allclose(rows, 1.0, atol=1e-6)


def test_object_channel_peaks_at_the_blob():
    eye = CompoundEye((120, 160), CFG)
    lobe = OpticLobe(eye)
    f = frame_with_blob(40)  # 40 px = about -26 deg
    lobe.process(f)
    feats = lobe.process(f)
    az_blob = np.degrees(np.arctan((40 - 80) / eye.focal))
    near = np.abs(eye.azimuth - az_blob) < 6
    assert feats["object"][near].max() > 2 * np.median(feats["object"])
    assert eye.azimuth[np.argmax(feats["object"])] < -10


def test_motion_detector_sign():
    eye = CompoundEye((120, 160), CFG)
    lobe = OpticLobe(eye, temporal_alpha=0.5)
    for x in (60, 66, 72, 78):  # a bar sliding rightwards
        feats = lobe.process(frame_with_blob(x, color=(240, 240, 240), width=6))
    assert feats["motion_r"].sum() > feats["motion_l"].sum()


def test_vpn_rates_are_bounded_and_aligned():
    eye = CompoundEye((120, 160), CFG)
    layout = VPNLayout.columnar(eye)
    enc = VPNEncoder(eye, layout)
    lobe = OpticLobe(eye)
    for x in (30, 40, 50):
        rates = enc.rates(lobe.process(frame_with_blob(x)))
    assert rates.shape == (layout.n,)
    assert rates.min() >= 0 and rates.max() <= enc.max_rate
    assert layout.n == len(FEATURES) * len(set(zip(layout.eye, layout.azimuth)))
