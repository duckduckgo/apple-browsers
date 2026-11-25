"""PR-ready images for one attempt folder, drawn by lib/compose.swift (CoreGraphics and AVFoundation, which ship with
Xcode) in one call per attempt:

- `<device>/key-frames.png`: the proof's screenshots then the final screen, in the order taken, captioned.
- `<device>/poster.png`: the recording's last frame with a play badge, to link to `recording.mp4`.
- `devices.png`: each device's final screen side by side (two or more devices).
- `before-after-<device>.png` (`prove --base`): the base run's key frames above this checkout's, matched by name.

An image that can't be drawn is an evidence problem, never a failed proof.
"""
import json, os, subprocess, tempfile

from .env import SKILL

COMPOSE = os.path.join(SKILL, "lib", "compose.swift")
KEY_FRAMES, POSTER, DEVICES = "key-frames.png", "poster.png", "devices.png"
GENERATED = {KEY_FRAMES, POSTER}
HEIGHT = 720   # every frame is scaled to this height: legible at full size, small enough to upload
TIMEOUT = 180
NAMES = dict(iphone="iPhone", ipad="iPad")


def before_after(device):
    return f"before-after-{device}.png"


def key_frames(device_dir, shots=None):
    """Screenshot names in the order the proof took them, then final.png; [] when there is no folder. `shots` is that
    order from result.json; without it (older evidence), file times give it, which a copy may not keep."""
    if not device_dir or not os.path.isdir(device_dir):
        return []
    if shots is None:
        shots = [f for f in os.listdir(device_dir) if f.endswith(".png") and f not in GENERATED | {"final.png"}]
        shots.sort(key=lambda f: (os.path.getmtime(os.path.join(device_dir, f)), f))
    shots = [f for f in shots if f != "final.png" and os.path.isfile(os.path.join(device_dir, f))]
    return shots + (["final.png"] if os.path.isfile(os.path.join(device_dir, "final.png")) else [])


def _grid(out, rows):
    return dict(kind="grid", out=out, height=HEIGHT, rows=rows)


def _row(device_dir, names, label=None):
    return dict(label=label, cells=[dict(path=os.path.join(device_dir, n) if device_dir and os.path.isfile(
        os.path.join(device_dir, n)) else None, caption=n[:-4]) for n in names])


def proof_jobs(attempt, results):
    """Jobs for one `prove` attempt: a key-frame strip and poster per device, and the devices side by side."""
    jobs, finals = [], []
    for r in results:
        ev = r.get("evidence")
        if not ev:
            continue
        frames = key_frames(ev, r.get("shots"))
        if len(frames) >= 2:   # a single frame is final.png itself
            jobs.append(_grid(os.path.join(ev, KEY_FRAMES), [_row(ev, frames)]))
        if r.get("video"):
            jobs.append(dict(kind="poster", out=os.path.join(ev, POSTER), video=os.path.join(ev, r["video"]),
                             height=HEIGHT))
        if "final.png" in frames:
            finals.append(dict(path=os.path.join(ev, "final.png"), caption=NAMES.get(r["device"], r["device"])))
    if len(finals) >= 2:
        jobs.append(_grid(os.path.join(attempt, DEVICES), [dict(label=None, cells=finals)]))
    return jobs


def comparison_jobs(attempt, before, after, devices):
    """Jobs for a `prove --base` attempt: per device, the base run's key frames above this checkout's.
    `before` and `after` are the runs' folders relative to `attempt` (None when a run left none); `devices` maps each
    device to its outcome, whose `before` and `after` are that run's result.json."""
    jobs = []
    for dev, o in devices.items():
        b, a = (os.path.join(attempt, run, dev) if run else None for run in (before, after))
        if not (b and a and os.path.isdir(b) and os.path.isdir(a)):   # nothing to compare on this device
            continue
        names = matched_frames(key_frames(b, o["before"].get("shots")), key_frames(a, o["after"].get("shots")))
        jobs.append(_grid(os.path.join(attempt, before_after(dev)),
                          [_row(b, names, "Before\n(base build)"), _row(a, names, "After\n(this checkout)")]))
    return jobs


def matched_frames(before, after):
    """Frame names from both runs, in this checkout's order, then the base run's extras, then the final screen."""
    names = [n for n in after if n != "final.png"]
    return names + [n for n in before if n not in names and n != "final.png"] + ["final.png"]


def compose(jobs):
    """Draw `jobs`; returns {out path: why} for each image that wasn't drawn (never raises)."""
    if not jobs:
        return {}
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(jobs, f)
        try:
            p = subprocess.run(["xcrun", "swift", COMPOSE, f.name], capture_output=True, text=True, timeout=TIMEOUT)
        finally:
            os.unlink(f.name)
        out = json.loads(p.stdout) if p.returncode == 0 else None
        if out is None:
            why = f"compose.swift exited {p.returncode}: {p.stderr.strip()[-300:]}"
            return {j["out"]: why for j in jobs}
        failed = {**{j["out"]: "not drawn" for j in jobs if j["out"] not in out["ok"]}, **out["failed"]}
        return {k: " ".join(why.split()) for k, why in failed.items()}   # AVFoundation errors span lines
    except subprocess.TimeoutExpired:
        return {j["out"]: f"compose.swift took over {TIMEOUT} s" for j in jobs}
    except (OSError, ValueError) as e:
        return {j["out"]: f"{type(e).__name__}: {e}" for j in jobs}


def problems(failed, attempt, results):
    """[(result, problem)]: each image not drawn, as an evidence problem of the device it shows (an image of every
    device goes to the first)."""
    runs = [r for r in results if r.get("evidence")]
    return [(next((r for r in runs if out.startswith(r["evidence"] + os.sep)), runs[0]),
             f"could not draw {os.path.relpath(out, attempt)}: {why}") for out, why in sorted(failed.items()) if runs]
