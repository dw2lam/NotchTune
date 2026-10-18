#!/usr/bin/env python3
"""Source of truth for the closed-notch pixel characters.

Each character is drawn on a 14x14 grid ('#' = pixel, '+' = dim pixel,
'.' = empty) and animated per state (idle, working, waiting) twice over:
Lively loops, optionally with a smooth Core Animation motion (hop / wave),
and Calm loops (the default) with no whole-sprite motion. Still shows each
calm loop's first frame.

    python3 scripts/generate-pixel-sprites.py
    NOTCHTUNE_SPRITE_SHEET_DIR=/some/dir swift test --filter PixelSpriteContactSheet

Output (generated, do not edit): Sources/NotchTuneApp/Views/PixelSprites.swift and
the website's copy, website/src/lib/sprites.ts.
"""
import os
import sys

W = H = 14


def F(*rows):
    rows = list(rows)
    assert len(rows) == H, f"{len(rows)} rows"
    for r in rows:
        assert len(r) == W, f"row {r!r} is {len(r)} wide"
        assert set(r) <= set("#+."), r
    return rows


def over(f, edits):
    """Overlay edits: {(row, col): string}. '.' transparent, '-' erase."""
    g = [list(r) for r in f]
    for (r, c), s in edits.items():
        for i, ch in enumerate(s):
            if ch == ".":
                continue
            if 0 <= r < H and 0 <= c + i < W:
                g[r][c + i] = "." if ch == "-" else ch
    return ["".join(r) for r in g]


def rows(f, replacements):
    """Replace whole rows: {row: 'fourteen chars'}."""
    g = list(f)
    for r, s in replacements.items():
        assert len(s) == W, s
        g[r] = s
    return g


def shift(f, dx=0, dy=0):
    g = [["."] * W for _ in range(H)]
    for r in range(H):
        for c in range(W):
            if f[r][c] != "." and 0 <= r + dy < H and 0 <= c + dx < W:
                g[r + dy][c + dx] = f[r][c]
    return ["".join(r) for r in g]


def bang(f, col, top=0):
    """The "needs you" mark: a 3-tall bar, a gap, a dot."""
    return over(f, {(top, col): "#", (top + 1, col): "#", (top + 2, col): "#", (top + 4, col): "#"})


def motion(curve, amplitude, period, axis="y"):
    return {"curve": curve, "amplitude": amplitude, "period": period, "axis": axis}


CHARACTERS = {}


def character(name, title, frames, idle, working, waiting,
              idle_motion=None, working_motion=None, waiting_motion=None,
              calm_idle=None, calm_working=None, calm_waiting=None):
    """Lively loops (idle / working / waiting, each with an optional smooth
    motion) and Calm ones (no whole-sprite motion: the default, since the
    pill sits in peripheral vision for hours). Still shows each calm loop's
    first frame, so calm waiting must open on its "!" frame."""
    calm = dict(calm_idle=calm_idle, calm_working=calm_working, calm_waiting=calm_waiting)
    for label, seq in (("idle", idle), ("working", working), ("waiting", waiting), *calm.items()):
        assert seq, f"{name}: missing {label}"
        for frame_name, duration in seq:
            assert frame_name in frames, f"{name}: missing frame {frame_name}"
            assert duration > 0
    assert calm_idle[0][0] == idle[0][0], f"{name}: calm idle must rest on the same frame"
    CHARACTERS[name] = dict(title=title, frames=frames,
                            idle=(idle, idle_motion), working=(working, working_motion),
                            waiting=(waiting, waiting_motion),
                            calm_idle=(calm_idle, None), calm_working=(calm_working, None),
                            calm_waiting=(calm_waiting, None))


# --------------------------------------------------------------------------
# Dino — the T. rex, facing right.

dino_rest = F(
    "..............",
    "......#######.",
    ".....##.######",
    ".....#########",
    ".....#####....",
    ".....#######..",
    "#...#####.....",
    "#..#######....",
    "##########.#..",
    ".#########....",
    "..#######.....",
    "...##..##.....",
    "...#....#.....",
    "...##...##....",
)
dino_blink = over(dino_rest, {(2, 7): "#"})
dino_open = rows(dino_rest, {4: ".....####.....", 5: ".....#####...."})
dino_legs_a = {11: "...##..##.....", 12: "...#....##....", 13: "...##........."}
dino_legs_b = {11: "...##..##.....", 12: "..##....#.....", 13: "........##...."}


dino_tail_flick = rows(dino_rest, {5: "#....#######..", 7: "...#######...."})
dino_w1 = rows(rows(dino_rest, dino_legs_a), {5: "#....#######..", 7: "...#######.#..", 8: "##########...."})
dino_w2 = rows(dino_rest, dino_legs_b)
dino_w3 = rows(rows(dino_open, dino_legs_a), {7: "#..#######.#..", 8: "##########...."})
dino_w4 = rows(dino_rest, dino_legs_b)
dino_alert = bang(dino_open, 2)
dino_alert_shut = bang(dino_rest, 2)

character(
    "dino", "Dino",
    frames=dict(rest=dino_rest, blink=dino_blink, open=dino_open, flick=dino_tail_flick,
                w1=dino_w1, w2=dino_w2, w3=dino_w3, w4=dino_w4,
                alert=dino_alert, alertShut=dino_alert_shut),
    idle=[("rest", 2.8), ("blink", 0.12), ("rest", 2.2), ("flick", 0.18), ("rest", 0.16),
          ("flick", 0.18), ("rest", 1.8), ("open", 0.55)],
    working=[("w1", 0.1), ("w2", 0.1), ("w3", 0.1), ("w4", 0.1)],
    working_motion=motion("hop", 0.6, 0.2),
    waiting=[("alert", 0.32), ("alertShut", 0.32), ("alert", 0.32), ("rest", 0.5)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.5), ("flick", 0.3), ("rest", 4.0),
               ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("w1", 0.45), ("w2", 0.45), ("w3", 0.45), ("w4", 0.45)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)

# --------------------------------------------------------------------------
# Ghost — front-facing, floats.

ghost_body = [
    "..............",
    "....######....",
    "...########...",
    "..##########..",
    "..##########..",
    "..##..##..##..",
    "..##..##..##..",
    "..##########..",
    "..##########..",
    "..##########..",
    "..##########..",
    "..##########..",
]
ghost_hems = ["..##.##.##.#..", "..#.##.##.##..", "...##.##.##...", ]


def ghost(hem=0, extra=None, tail="..............", row_edits=None):
    f = F(*(ghost_body + [ghost_hems[hem], tail]))
    if row_edits:
        f = rows(f, row_edits)
    if extra:
        f = over(f, extra)
    return f


ghost_rest = ghost()
ghost_blink = ghost(row_edits={5: "..##########.."})
ghost_look_l = ghost(extra={(6, 4): "+", (6, 8): "+"})
ghost_look_r = ghost(extra={(6, 5): "+", (6, 9): "+"})
ghost_boo = ghost(row_edits={8: "..####..####..", 9: "..####..####.."})
ghost_alert = bang(ghost_boo, 13, top=0)
ghost_alert_shut = bang(ghost(), 13, top=0)

character(
    "ghost", "Ghost",
    frames=dict(rest=ghost_rest, blink=ghost_blink, lookL=ghost_look_l, lookR=ghost_look_r,
                h0=ghost(0), h1=ghost(1), h2=ghost(2),
                alert=ghost_alert, alertShut=ghost_alert_shut),
    idle=[("rest", 2.6), ("blink", 0.12), ("rest", 1.8), ("lookL", 0.8), ("rest", 0.2),
          ("lookR", 0.8), ("rest", 1.4), ("h1", 0.16), ("h2", 0.16), ("rest", 0.4)],
    idle_motion=motion("wave", 0.3, 3.2),
    working=[("h0", 1 / 6), ("h1", 1 / 6), ("h2", 1 / 6)],
    working_motion=motion("wave", 0.6, 1.0),
    waiting=[("alert", 0.36), ("alertShut", 0.36), ("alert", 0.36), ("rest", 0.5)],
    waiting_motion=motion("wave", 0.4, 0.8),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.0), ("lookL", 1.2), ("rest", 0.3),
               ("lookR", 1.2), ("rest", 4.0), ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("h0", 0.5), ("h1", 0.5), ("h2", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)

# --------------------------------------------------------------------------
# Crab — eyes on stalks, claws up.

crab_rest = F(
    "..............",
    ".##........##.",
    "#..#......#..#",
    "####.#..#.####",
    ".#...+..+...#.",
    ".#.########.#.",
    "..##########..",
    "..##########..",
    "..##+####+##..",
    "..##########..",
    "...########...",
    "..#.#....#.#..",
    ".#..#....#..#.",
    "..............",
)
crab_closed = rows(crab_rest, {1: "..............", 2: ".##........##.", 3: "###..#..#..###"})
crab_blink = over(crab_rest, {(3, 5): "+", (3, 8): "+"})
crab_look_l = rows(crab_rest, {3: "####.#..#.####", 4: ".#..+..+....#."})
crab_look_l = over(crab_look_l, {(3, 5): "-", (3, 8): "-", (3, 4): "#", (3, 7): "#"})
crab_legs_b = {11: "...#.#..#.#...", 12: "..#..#..#..#.."}
crab_w1 = crab_rest
crab_w2 = rows(crab_rest, crab_legs_b)
crab_w3 = crab_closed
crab_w4 = rows(crab_closed, crab_legs_b)
crab_wave_l = rows(crab_rest, {0: ".##...........", 1: "#..#.......##.", 2: "####......#..#"})
crab_wave_r = rows(crab_rest, {0: "...........##.", 1: ".##.......#..#", 2: "#..#......####"})

character(
    "crab", "Crab",
    frames=dict(rest=crab_rest, closed=crab_closed, blink=crab_blink, lookL=crab_look_l,
                w1=crab_w1, w2=crab_w2, w3=crab_w3, w4=crab_w4,
                waveL=crab_wave_l, waveR=crab_wave_r),
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 2.0), ("closed", 0.14), ("rest", 0.14),
          ("closed", 0.14), ("rest", 1.6), ("lookL", 0.9), ("rest", 0.6)],
    working=[("w1", 0.1), ("w2", 0.1), ("w3", 0.1), ("w4", 0.1)],
    working_motion=motion("wave", 0.5, 0.4, axis="x"),
    waiting=[("waveL", 0.24), ("waveR", 0.24)],
    waiting_motion=motion("hop", 0.3, 0.48),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("lookL", 1.2), ("rest", 4.0),
               ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("w1", 0.45), ("w2", 0.45), ("w1", 0.45), ("w2", 0.45), ("w3", 0.35), ("w4", 0.35)],
    calm_waiting=[("waveL", 1.0), ("waveR", 1.0)],
)

# --------------------------------------------------------------------------
# Duck — facing right, waddles.

duck_rest = F(
    "..............",
    "......####....",
    ".....######...",
    ".....##.###...",
    ".....#######++",
    ".....#######..",
    "......####....",
    "......####....",
    ".########.....",
    "##########....",
    "###++######...",
    ".#########....",
    "..########....",
    "....#..#......",
)
duck_blink = over(duck_rest, {(3, 7): "#"})
duck_quack = rows(duck_rest, {4: ".....#######++", 5: ".....#######.+"})
duck_quack = over(duck_quack, {(4, 12): "+", (5, 12): "-", (5, 13): "-", (6, 11): "++"})
duck_feet_b = {13: "...#...#......"}
duck_feet_c = {13: ".....#..#....."}


def duck_head_forward(f):
    """The walking head bob: head and neck one pixel forward."""
    head = [r[:5] + "." + r[5:13] if i <= 7 else r for i, r in enumerate(f)]
    return [r[:W] for r in head]


duck_w1 = rows(duck_head_forward(duck_rest), duck_feet_b)
duck_w2 = rows(duck_rest, duck_feet_c)
duck_w3 = rows(duck_head_forward(duck_rest), duck_feet_c)
duck_w4 = rows(duck_quack, duck_feet_b)
duck_ruffle = rows(duck_rest, {10: "#+#+#######..."})
duck_alert = bang(duck_quack, 2, top=1)
duck_alert_shut = bang(duck_rest, 2, top=1)

character(
    "duck", "Duck",
    frames=dict(rest=duck_rest, blink=duck_blink, quack=duck_quack, ruffle=duck_ruffle,
                w1=duck_w1, w2=duck_w2, w3=duck_w3, w4=duck_w4,
                alert=duck_alert, alertShut=duck_alert_shut),
    idle=[("rest", 2.6), ("blink", 0.12), ("rest", 2.4), ("ruffle", 0.16), ("rest", 0.16),
          ("ruffle", 0.16), ("rest", 1.5), ("quack", 0.3), ("rest", 0.6)],
    working=[("w1", 0.13), ("w2", 0.13), ("w3", 0.13), ("w4", 0.13)],
    working_motion=motion("wave", 0.45, 0.52, axis="x"),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("rest", 0.5)],
    waiting_motion=motion("hop", 0.35, 0.6),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("ruffle", 0.3), ("rest", 4.0),
               ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("w1", 0.5), ("w2", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)

# --------------------------------------------------------------------------
# Claude — Clawd, Claude Code's own mascot, scaled from the CLI's pixel art
# (its welcome-screen Clawd and the "Clawd cooking" scene): a wide, squat
# body with one-pixel-wide eyes set in from each edge, stubby arms at
# mid-height and four legs in two pairs at the body's edges. The moves are
# the CLI's own vocabulary: glance left/right (its `look`), blink and wink,
# tap one pair of feet then the other (`tap` / `waddle`), throw both arms up
# (`jump` / `celebrate`), and raise one arm (`one-up`).

CLAWD_EYES = (4, 9)  # columns; 2 tall, rows 5-6


def clawd(arms="down", eyes="open", feet="both", crouch=False):
    g = [list("." * W) for _ in range(H)]
    for r in range(4, 10):  # body: 10 wide, 6 tall
        for c in range(2, 12):
            g[r][c] = "#"
    arm_rows = {"down": ((7, 8), (7, 8)), "up": ((5, 6), (5, 6)), "one-up": ((7, 8), (5, 6))}[arms]
    for side, rows_ in zip(((0, 1), (12, 13)), arm_rows):
        for r in rows_:
            for c in side:
                g[r][c] = "#"
    # The CLI's glance also lifts the eyes a row; at 14px that notches the
    # head's outline, so ours only slide sideways.
    dx, top = {"open": (0, 5), "left": (-1, 5), "right": (1, 5)}.get(eyes, (0, 5))
    for i, c in enumerate(CLAWD_EYES):
        col = c + dx
        closed = eyes == "closed" or (eyes == "wink" and i == 1)
        if closed:
            g[6][col] = "+"  # a lid line where the eye was
        else:
            g[top][col] = "."
            g[top + 1][col] = "."
    pairs = {"both": ((2, 4), (9, 11)), "left": ((2, 4),), "right": ((9, 11),)}[feet]
    lifted = {"both": (), "left": (9, 11), "right": (2, 4)}[feet]
    for pair in pairs:
        for c in pair:
            g[10][c] = "#"
            g[11][c] = "#"
    for c in lifted:  # the lifted pair, tucked up to a stub
        g[10][c] = "#"
    f = ["".join(r) for r in g]
    return shift(f, dy=1) if crouch else f


claude_rest = clawd()
claude_frames = dict(
    rest=claude_rest,
    blink=clawd(eyes="closed"),
    wink=clawd(eyes="wink"),
    lookL=clawd(eyes="left"),
    lookR=clawd(eyes="right"),
    up=clawd(arms="up"),
    oneUp=clawd(arms="one-up"),
    tapL=clawd(feet="left"),
    tapR=clawd(feet="right"),
    tapLookL=clawd(feet="left", eyes="left"),
    tapLookR=clawd(feet="right", eyes="right"),
    crouch=clawd(crouch=True),
    # Needs you: "!" on the left, the right arm up (the CLI's `one-up`).
    alert=bang(clawd(arms="one-up"), 0, top=0),
    alertDown=bang(clawd(), 0, top=0),
)

character(
    "claude", "Claude",
    frames=claude_frames,
    # Lively: the CLI's moves at near its own pace.
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.6), ("lookR", 0.6), ("lookL", 0.6), ("rest", 1.8),
          ("wink", 0.3), ("rest", 1.0)],
    working=[("tapL", 0.18), ("tapR", 0.18), ("tapL", 0.18), ("tapR", 0.18), ("crouch", 0.12),
             ("up", 0.22), ("rest", 0.12)],
    waiting=[("alert", 0.3), ("alertDown", 0.3)],
    # Calm: a slow foot-tap with the odd glance; the "!" holds.
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("lookR", 1.2), ("rest", 0.3),
               ("lookL", 1.2), ("rest", 3.5), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("tapL", 0.5), ("tapR", 0.5), ("tapL", 0.5), ("tapR", 0.5),
                  ("tapLookR", 0.5), ("tapR", 0.5), ("tapLookL", 0.5), ("tapR", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertDown", 1.0)],
)

# --------------------------------------------------------------------------
# Cat — sits facing you, tail curled round its side. One clean silhouette:
# pointed ears, a broad head, a round body; motion is ears, eyes and tail.


def cat_frame(eyes="open", ear=None, tail="down", paws="both", mouth=False):
    f = F(
        "..............",
        "..#......#....",
        "..##....##....",
        "..########....",
        ".##########...",
        ".##.####.##...",
        ".##.####.##...",
        "..########....",
        "...######.....",
        "..########....",
        "..########....",
        "..########....",
        "..########....",
        "...##..##.....",
    )
    eye_cols = {"open": (3, 8), "left": (2, 7), "right": (4, 9)}.get(eyes, (3, 8))
    if eyes != "open":
        f = over(f, {(5, 3): "#", (6, 3): "#", (5, 8): "#", (6, 8): "#"})
        if eyes == "closed":
            f = over(f, {(6, 3): "+", (6, 8): "+"})
        else:
            for c in eye_cols:
                f = over(f, {(5, c): "-", (6, c): "-"})
    if mouth:
        f = over(f, {(7, 5): "--"})
    if ear == "flick":  # the right ear folds back for a beat
        f = over(f, {(1, 9): "-", (2, 8): "-"})
    tail_cells = {
        "down": [(12, 10), (12, 11), (11, 12), (10, 12), (9, 12)],
        "up": [(12, 10), (12, 11), (11, 12), (10, 12), (9, 12), (8, 12), (7, 11)],
        "out": [(12, 10), (12, 11), (12, 12), (11, 13), (10, 13)],
    }[tail]
    for r, c in tail_cells:
        f = over(f, {(r, c): "#"})
    if paws == "left":  # one forepaw lifted (kneading)
        f = over(f, {(13, 3): "--", (12, 3): "+"})
    elif paws == "right":
        f = over(f, {(13, 7): "--", (12, 7): "+"})
    return f


cat_rest = cat_frame()
cat_frames = dict(
    rest=cat_rest,
    blink=cat_frame(eyes="closed"),
    ear=cat_frame(ear="flick"),
    lookL=cat_frame(eyes="left"),
    lookR=cat_frame(eyes="right"),
    tailUp=cat_frame(tail="up"),
    tailOut=cat_frame(tail="out"),
    kneadL=cat_frame(paws="left", tail="up"),
    kneadR=cat_frame(paws="right", tail="out"),
    kneadL2=cat_frame(paws="left", tail="out"),
    meow=bang(cat_frame(mouth=True, tail="up"), 12),
    meowShut=bang(cat_frame(tail="up"), 12),
)

character(
    "cat", "Cat",
    frames=cat_frames,
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 1.8), ("ear", 0.14), ("rest", 0.1), ("ear", 0.14),
          ("rest", 1.6), ("tailUp", 0.5), ("rest", 0.4), ("tailOut", 0.5), ("rest", 1.2)],
    working=[("kneadL", 0.14), ("kneadR", 0.14), ("kneadL2", 0.14), ("kneadR", 0.14)],
    waiting=[("meow", 0.3), ("meowShut", 0.3), ("meow", 0.3), ("tailUp", 0.5)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("tailOut", 0.8), ("rest", 3.5),
               ("lookR", 1.2), ("rest", 0.3), ("ear", 0.16), ("rest", 2.5)],
    calm_working=[("kneadL", 0.5), ("kneadR", 0.5), ("kneadL2", 0.5), ("kneadR", 0.5)],
    calm_waiting=[("meow", 1.4), ("meowShut", 1.0)],
)

# --------------------------------------------------------------------------
# Robot — a screen-faced bot: hollow head with two square eyes, antenna
# light, a compact body. Busy = the antenna blinks and the eyes scan.


def robot_frame(eyes="open", lit=False, legs="both"):
    f = F(
        "......++......",
        "......##......",
        "..##########..",
        "..#........#..",
        "..#.##..##.#..",
        "..#.##..##.#..",
        "..#........#..",
        "..##########..",
        "......##......",
        "..##########..",
        "..#.######.#..",
        "..#.######.#..",
        "....##..##....",
        "...###..###...",
    )
    if lit:
        f = over(f, {(0, 6): "##"})
    eye_rows = {
        "open": "..#.##..##.#..",
        "closed": "..#........#..",
        "left": "..#.#...#..#..",
        "right": "..#..#...#.#..",
    }
    f = rows(f, {4: eye_rows[eyes], 5: eye_rows[eyes] if eyes != "closed" else "..#.++..++.#.."})
    if legs == "left":
        f = rows(f, {12: "....##..##....", 13: "...###...##..."})
    elif legs == "right":
        f = rows(f, {12: "....##..##....", 13: "....##..###..."})
    return f


robot_rest = robot_frame()
robot_frames = dict(
    rest=robot_rest,
    lit=robot_frame(lit=True),
    blink=robot_frame(eyes="closed"),
    lookL=robot_frame(eyes="left"),
    lookR=robot_frame(eyes="right"),
    w1=robot_frame(eyes="left", lit=True),
    w2=robot_frame(eyes="open"),
    w3=robot_frame(eyes="right", lit=True),
    w4=robot_frame(eyes="open", legs="left"),
    # Needs you: "!" beside it while the antenna light blinks.
    alert=bang(robot_frame(lit=True), 13, top=0),
    alertDim=bang(robot_frame(), 13, top=0),
)

character(
    "robot", "Robot",
    frames=robot_frames,
    idle=[("rest", 1.6), ("lit", 0.5), ("rest", 1.4), ("blink", 0.14), ("rest", 1.2), ("lit", 0.5),
          ("rest", 0.9), ("lookL", 0.6), ("lookR", 0.6), ("rest", 0.5)],
    working=[("w1", 0.15), ("w2", 0.15), ("w3", 0.15), ("w4", 0.15)],
    waiting=[("alert", 0.25), ("alertDim", 0.25)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.0), ("lit", 0.8), ("rest", 3.5),
               ("lookR", 1.2), ("rest", 0.3), ("lookL", 1.2), ("rest", 2.0)],
    calm_working=[("w1", 0.6), ("w2", 0.6), ("w3", 0.6), ("w2", 0.6)],
    calm_waiting=[("alert", 1.4), ("alertDim", 1.0)],
)

# --------------------------------------------------------------------------
# Octopus — a tall bulb of a head over a skirt of tentacles that curl out
# at the tips (the Ghost is a dome with a hem; this is all arms).


def octo_frame(eyes="open", curl=0, raised=False):
    head = [
        "..............",
        ".....####.....",
        "....######....",
        "...########...",
        "...########...",
        "...#.####.#...",
        "...#.####.#...",
        "...########...",
        "..##########..",
    ]
    if eyes == "closed":
        head[5] = "...########..."
        head[6] = "...#+####+#..."
    # tentacles: rows 9-13; curl phases ripple the tips
    legs = [
        [".#.##.##.##.#.", "#..#..##..#..#", "##.#..#...#.##", "...##....##...", ".............."],
        [".#.##.##.##.#.", "#..#..##..#..#", "#..#...#..#..#", "##.##...##.###", ".............."],
        [".#.##.##.##.#.", ".#.#..##..#.#.", "#..#..#...#..#", "##..#....#..##", ".............."],
    ][curl % 3]
    if raised:
        legs = [".#.##.##.##.#.", "...#..##..#...", "...#..#...#...", "...##....##...", ".............."]
        head[7] = "#..########..#"
        head[8] = "###########.##"
    return F(*(head + legs))


octo_rest = octo_frame()
octo_frames = dict(
    rest=octo_rest,
    blink=octo_frame(eyes="closed"),
    c1=octo_frame(curl=1),
    c2=octo_frame(curl=2),
    raised=bang(octo_frame(raised=True), 13, top=0),
    raisedRest=bang(octo_rest, 13, top=0),
)

character(
    "octopus", "Octopus",
    frames=octo_frames,
    idle=[("rest", 2.6), ("blink", 0.14), ("rest", 1.8), ("c1", 0.2), ("c2", 0.2), ("rest", 2.2)],
    idle_motion=motion("wave", 0.3, 3.0),
    working=[("rest", 0.16), ("c1", 0.16), ("c2", 0.16), ("c1", 0.16)],
    working_motion=motion("wave", 0.5, 1.28),
    waiting=[("raised", 0.32), ("raisedRest", 0.32)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("c1", 0.5), ("rest", 4.0), ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("rest", 0.5), ("c1", 0.5), ("c2", 0.5), ("c1", 0.5)],
    calm_waiting=[("raised", 1.4), ("raisedRest", 1.0)],
)

# --------------------------------------------------------------------------
# Frog — bulging eyes, hops while working, puffs its throat at rest.

frog_rest = F(
    "..............",
    "..............",
    "..###....###..",
    ".##.##..##.##.",
    ".#####..#####.",
    "..##########..",
    ".############.",
    "##++++++++++##",
    "##############",
    ".############.",
    "#.##########.#",
    "##..######..##",
    "..............",
    "..............",
)
frog_blink = rows(frog_rest, {3: ".#####..#####."})
frog_blink = over(frog_blink, {(3, 2): "+++", (3, 9): "+++"})
frog_puff = rows(frog_rest, {9: ".############.", 10: "#.###++++###.#", 11: "##..#++++#..##", 12: ".....####....."})
frog_tongue = over(frog_rest, {(7, 9): "+++", (7, 12): "##", (6, 13): "#"})
frog_crouch = shift(frog_rest, dy=1)
frog_crouch = rows(frog_crouch, {12: "###.######.###"})
frog_leap = rows(frog_rest, {10: ".############.", 11: "..##########..", 12: "..#........#..", 13: ".#..........#."})
frog_tuck = rows(frog_rest, {10: "#.##########.#", 11: ".###......###."})
frog_ribbit = rows(frog_rest, {7: "##..........##", 8: "###........###"})
frog_alert = bang(frog_ribbit, 6, top=0)
frog_alert_shut = bang(frog_rest, 6, top=0)

character(
    "frog", "Frog",
    frames=dict(rest=frog_rest, blink=frog_blink, puff=frog_puff, tongue=frog_tongue,
                crouch=frog_crouch, leap=frog_leap, tuck=frog_tuck,
                alert=frog_alert, alertShut=frog_alert_shut),
    idle=[("rest", 2.2), ("blink", 0.14), ("rest", 1.6), ("puff", 0.4), ("rest", 0.3), ("puff", 0.4),
          ("rest", 1.8), ("tongue", 0.16), ("rest", 1.0)],
    working=[("crouch", 0.12), ("leap", 0.13), ("tuck", 0.12), ("leap", 0.13)],
    working_motion=motion("hop", 1.0, 0.5),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("rest", 0.5)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("puff", 0.5), ("rest", 4.0),
               ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("puff", 0.5), ("rest", 0.4), ("tuck", 0.5), ("rest", 0.4), ("tongue", 0.25), ("rest", 0.45)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)

# --------------------------------------------------------------------------
# Slime — a droplet: pointed tip, round body, a glint of highlight and two
# eyes. Busy = it wobbles (the tip sways, the body squashes a row).


def slime_frame(eyes="open", lean=0, squash=False, stretch=False):
    f = F(
        "..............",
        "......##......",
        "......##......",
        ".....####.....",
        "....######....",
        "...##+#####...",
        "..##+#######..",
        "..##########..",
        ".###.####.###.",
        ".###.####.###.",
        ".############.",
        ".############.",
        "..##########..",
        "....######....",
    )
    if eyes == "closed":
        f = over(f, {(8, 4): "#", (8, 9): "#", (9, 4): "+", (9, 9): "+"})
    elif eyes == "left":
        f = over(f, {(8, 4): "#", (9, 4): "#", (8, 9): "#", (9, 9): "#", (8, 3): "-", (9, 3): "-", (8, 8): "-", (9, 8): "-"})
    elif eyes == "right":
        f = over(f, {(8, 4): "#", (9, 4): "#", (8, 9): "#", (9, 9): "#", (8, 5): "-", (9, 5): "-", (8, 10): "-", (9, 10): "-"})
    if lean:
        top = shift(F(*(f[:5] + ["." * W] * 9)), dx=lean)
        f = top[:5] + f[5:]
    if squash:
        f = shift(f, dy=1)
        f = rows(f, {13: "..##########.."})
        f = over(f, {(12, 0): "#", (12, 13): "#"})
    if stretch:
        f = shift(f, dy=-1)
        f = rows(f, {12: "...########...", 13: "..............", 11: "..##########.."})
    return f


slime_rest = slime_frame()
slime_frames = dict(
    rest=slime_rest,
    blink=slime_frame(eyes="closed"),
    lookL=slime_frame(eyes="left"),
    lookR=slime_frame(eyes="right"),
    leanL=slime_frame(lean=-1),
    leanR=slime_frame(lean=1),
    squash=slime_frame(squash=True),
    stretch=slime_frame(stretch=True),
    alert=bang(slime_frame(stretch=True), 12, top=0),
    alertRest=bang(slime_rest, 12, top=0),
)

character(
    "slime", "Slime",
    frames=slime_frames,
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 2.0), ("squash", 0.16), ("rest", 0.16),
          ("squash", 0.16), ("rest", 1.6)],
    working=[("squash", 0.12), ("stretch", 0.14), ("rest", 0.12), ("stretch", 0.14)],
    working_motion=motion("hop", 0.7, 0.52),
    waiting=[("alert", 0.3), ("alertRest", 0.3)],
    waiting_motion=motion("hop", 0.5, 0.6),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("lookR", 1.2), ("rest", 0.3),
               ("lookL", 1.2), ("rest", 3.0), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("leanL", 0.6), ("rest", 0.4), ("leanR", 0.6), ("rest", 0.4)],
    calm_waiting=[("alertRest", 1.4), ("alert", 1.0)],
)


# --------------------------------------------------------------------------
# Blob — a soft, melty mound of goo (the Slime is a droplet with a tip; this
# is a dome with no point that spreads into a puddle at its base, its left
# side slumping into it). A curved glint near the top, big square eyes and a
# little "u" smile; a drip of goo hangs off its right side. Its moves are goo
# moves: the top dips a row while the base spreads (a jiggle), the top sways
# a pixel, and the drip slides down the side, pours into the puddle and
# re-forms.

# Body outline per pose: {row: (left col, right col)}, filled.
blob_body = {
    "rest": {3: (5, 8), 4: (3, 10), **{r: (2, 11) for r in range(5, 12)}, 12: (1, 12), 13: (0, 13)},
    # Settles: the top drops a row, the base spreads a pixel.
    "squash": {4: (4, 9), **{r: (2, 11) for r in range(5, 11)}, 11: (1, 12), 12: (0, 13), 13: (0, 13)},
    # Pulled up tall (surprised): the top rises a row, the puddle holds.
    "stretch": {2: (5, 8), 3: (3, 10), **{r: (2, 11) for r in range(4, 12)}, 12: (1, 12), 13: (0, 13)},
}
blob_top = {"rest": 3, "squash": 4, "stretch": 2}
# The drip on the right side (the body's edge is col 11): '#' goo, '+' a wet trail.
blob_drips = {
    "none": {},
    "bead": {(6, 12): "#"},
    "hang": {(7, 12): "#", (8, 12): "#"},
    "slide": {(8, 12): "+", (9, 12): "#", (10, 12): "#"},
    "pour": {(10, 12): "+", (11, 12): "#", (12, 13): "#"},
    "pool": {(12, 13): "#"},
}


def blob_frame(pose="rest", eyes="open", mouth="smile", drip="hang", lean=0):
    top = blob_top[pose]
    g = [["."] * W for _ in range(H)]
    for r, (a, b) in blob_body[pose].items():
        dx = lean if r <= top + 1 else 0  # the top two rows sway
        for c in range(a + dx, b + dx + 1):
            g[r][c] = "#"
    f = ["".join(r) for r in g]
    f = over(f, {(10, 1): "#", (11, 1): "#"})  # the left side oozing into the puddle
    f = over(f, {(top + 1, 5): "++", (top + 2, 4): "+"})  # the glint (stays as the top sways)
    e = 7 if pose == "stretch" else 8  # eye rows e, e+1
    holes = {
        "open": [(e, c) for c in (3, 4, 9, 10)] + [(e + 1, c) for c in (3, 4, 9, 10)],
        "left": [(r, c) for r in (e, e + 1) for c in (3, 9)],
        "right": [(r, c) for r in (e, e + 1) for c in (4, 10)],
        "wide": [(r, c) for r in (e - 1, e, e + 1) for c in (3, 4, 9, 10)],
        "closed": [],
    }[eyes]
    edits = {rc: "-" for rc in holes}
    if eyes == "closed":
        edits.update({(e + 1, c): "+" for c in (3, 4, 9, 10)})
    m = e + 3  # mouth rows m, m+1
    edits.update({rc: "-" for rc in {
        "smile": [(m, 5), (m, 8), (m + 1, 6), (m + 1, 7)],
        "o": [(m, 6), (m, 7), (m + 1, 6), (m + 1, 7)],
    }[mouth]})
    f = over(f, edits)
    return over(f, blob_drips[drip])


blob_rest = blob_frame()
blob_frames = dict(
    rest=blob_rest,
    blink=blob_frame(eyes="closed"),
    lookL=blob_frame(eyes="left"),
    lookR=blob_frame(eyes="right"),
    squash=blob_frame(pose="squash"),
    # The goo cycle: the drip slides down, pours into the puddle and re-forms
    # while the top sways (Lively also squashes as it pours).
    g1=blob_frame(drip="slide", lean=-1),
    g2=blob_frame(drip="pour"),
    g2Squash=blob_frame(pose="squash", drip="pour"),
    g3=blob_frame(drip="pool", lean=1),
    g4=blob_frame(drip="bead"),
    # Needs you: pulled up tall with wide eyes and an "o", the "!" beside it.
    alert=bang(blob_frame(pose="stretch", eyes="wide", mouth="o"), 13),
    alertSettle=bang(blob_frame(eyes="wide", mouth="o"), 13),
)

character(
    "blob", "Blob",
    frames=blob_frames,
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 1.6), ("squash", 0.16), ("rest", 0.14), ("squash", 0.16),
          ("rest", 1.4), ("lookR", 0.6), ("lookL", 0.6), ("rest", 1.0)],
    working=[("g1", 0.14), ("g2Squash", 0.14), ("g3", 0.14), ("g4", 0.14), ("rest", 0.14), ("squash", 0.14)],
    working_motion=motion("wave", 0.4, 0.84, axis="x"),
    waiting=[("alert", 0.3), ("alertSettle", 0.3)],
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("lookR", 1.2), ("rest", 0.3),
               ("lookL", 1.2), ("rest", 4.0), ("squash", 0.3), ("rest", 2.0)],
    calm_working=[("rest", 0.5), ("g1", 0.5), ("g2", 0.5), ("g3", 0.5), ("g4", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertSettle", 1.0)],
)


# --------------------------------------------------------------------------
# Poo — the poop emoji: a soft-serve pile of three stacked tiers, each wider
# than the one above, with a curled tip leaning over the top. The tiers'
# rounded ends notch the outline (the swirl's creases), big eyes sit on the
# middle tier and a wide open grin on the bottom one. Moves: blink and glance,
# the tip curl swaying side to side, stink lines rising off it while it
# works, and a gasp ("O" mouth) beside the "!" when it needs you.

POO_TIPS = {  # rows 0-1: the curl, hooked over to one side
    "left": (".....###......", ".......##....."),
    "right": ("......###.....", ".....##......."),
}
POO_EYES = {"open": (4, 8), "left": (3, 7), "right": (5, 9)}  # 2x2 holes, rows 7-8
# Stink: a dim wavy line over each shoulder; each bows out "(  )" or in ")  (".
POO_STINK_L = {"out": [(0, 2), (1, 1), (2, 1), (3, 2)], "in": [(0, 1), (1, 2), (2, 2), (3, 1)]}
POO_STINK_R = {"out": [(0, 11), (1, 12), (2, 12), (3, 11)], "in": [(0, 12), (1, 11), (2, 11), (3, 12)]}


def poo_frame(eyes="open", mouth="grin", tip="left", lean=0, stink=None, fly=None):
    """stink: None or (left bow, right bow), each "out" or "in"."""
    f = F(
        *POO_TIPS[tip],
        ".....####.....",
        "....######....",
        ".....####.....",
        "..##########..",
        ".############.",
        ".############.",
        ".############.",
        "..##########..",
        "##############",
        "###........###",
        "####......####",
        ".############.",
    )
    if eyes == "closed":
        f = over(f, {(8, 4): "++", (8, 8): "++"})  # a lid line low in each eye
    else:
        for c in POO_EYES[eyes]:
            f = over(f, {(7, c): "--", (8, c): "--"})
    if mouth == "open":  # a gasp: the wide grin rounds into a small "O"
        f = rows(f, {11: "#####....#####", 12: "#####....#####"})
    if lean:  # the tip and top tier slide over a pixel (a jiggle)
        top = shift(F(*(f[:5] + ["." * W] * 9)), dx=lean)
        f = top[:5] + f[5:]
    if stink:
        for r, c in POO_STINK_L[stink[0]] + POO_STINK_R[stink[1]]:
            f = over(f, {(r, c): "+"})
    if fly:
        f = over(f, {fly: "#"})
    return f


poo_rest = poo_frame()
poo_frames = dict(
    rest=poo_rest,
    blink=poo_frame(eyes="closed"),
    lookL=poo_frame(eyes="left"),
    lookR=poo_frame(eyes="right"),
    tipR=poo_frame(tip="right"),
    # Working: the stink lines waver, one side at a time, while the tip sways.
    s1=poo_frame(stink=("out", "out")),
    s2=poo_frame(stink=("in", "out")),
    s3=poo_frame(stink=("in", "in"), tip="right"),
    s4=poo_frame(stink=("out", "in"), tip="right"),
    # Lively working: a jiggle with a fly buzzing round the tip.
    j1=poo_frame(lean=-1, fly=(1, 11)),
    j2=poo_frame(tip="right", fly=(0, 12)),
    j3=poo_frame(tip="right", lean=1, fly=(1, 13)),
    j4=poo_frame(fly=(2, 12)),
    # Needs you: "!" on the right, mouth open in a gasp.
    alert=bang(poo_frame(mouth="open"), 12, top=0),
    alertShut=bang(poo_rest, 12, top=0),
)

character(
    "poo", "Poo",
    frames=poo_frames,
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 1.8), ("tipR", 0.5), ("rest", 0.4), ("tipR", 0.5),
          ("rest", 1.6), ("lookR", 0.6), ("lookL", 0.6), ("rest", 1.0)],
    working=[("j1", 0.14), ("j2", 0.14), ("j3", 0.14), ("j4", 0.14)],
    working_motion=motion("hop", 0.5, 0.56),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("rest", 0.5)],
    waiting_motion=motion("hop", 0.35, 0.6),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("lookR", 1.2), ("rest", 0.3),
               ("lookL", 1.2), ("rest", 3.5), ("tipR", 0.8), ("rest", 2.0)],
    calm_working=[("s1", 0.55), ("s2", 0.55), ("s3", 0.55), ("s4", 0.55)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)


# --------------------------------------------------------------------------
# John Pork — the meme: a man with a realistic pig's head, framed like the
# caller-ID photo on his "John Pork is calling" screen. A wide pig face with
# ears flaring out at the top corners (a dim inner ear), small eyes and a big
# flat snout (the dim plate, two nostril holes) above suited shoulders and a
# tie. Moves are a pig's: a blink, an ear flop, a sniff (the nostrils flare);
# busy, he roots about, the snout swinging side to side. Needs you: John Pork
# is calling — phone to his ear, mouth going, "!" on the open side.


def pork_frame(eyes="open", ears="out", snout="rest", mouth=False, phone=False, nod=False):
    f = F(
        "##.........##.",
        "#+#.#####.#+#.",
        ".###########..",
        ".###.###.###..",
        ".###########..",
        ".##+++++++##..",
        ".#++.+++.++#..",
        ".#++.+++.++#..",
        "..#+++++++#...",
        "...#######....",
        "..............",
        "..###.#.###...",
        ".####.#.####..",
        "#####.#.#####.",
    )
    if eyes != "open":
        f = over(f, {(3, 4): "#", (3, 8): "#"})
        if eyes == "closed":
            f = over(f, {(3, 4): "+", (3, 8): "+"})
        else:
            for c in {"left": (3, 7), "right": (5, 9)}[eyes]:
                f = over(f, {(3, c): "-"})
    if snout == "flare":  # a sniff: both nostrils open wide
        f = over(f, {(6, 3): "-", (7, 3): "-", (6, 9): "-", (7, 9): "-"})
    elif snout == "left":  # the whole snout swings a pixel left, over the jowl
        f = over(f, {(5, 2): "+++++++#", (6, 1): "++-+++-++#", (7, 1): "++-+++-++#", (8, 2): "+++++++#"})
    elif snout == "right":
        f = over(f, {(5, 3): "#+++++++", (6, 2): "#++-+++-++", (7, 2): "#++-+++-++", (8, 3): "#+++++++"})
    if mouth:  # the jaw drops under the snout
        f = over(f, {(9, 5): "---"})
    if ears == "flop":  # the right ear tips over sideways
        f = over(f, {(0, 11): "--", (1, 10): "####"})
    elif ears == "perk":  # the right ear stands up, clear of the "!"
        f = over(f, {(0, 10): "##-", (1, 12): "-"})
    if phone:  # a dark phone held to the ear on our left (hiding it), hand under it
        f = over(f, {(0, 0): "++", (1, 0): "++-#", (2, 0): "++-", (3, 0): "++-", (4, 0): "###", (5, 0): "#"})
    if nod:  # the head dips onto the collar
        f = shift(F(*(f[:10] + ["." * W] * 4)), dy=1)[:11] + f[11:]
    return f


pork_rest = pork_frame()
pork_frames = dict(
    rest=pork_rest,
    blink=pork_frame(eyes="closed"),
    lookL=pork_frame(eyes="left"),
    lookR=pork_frame(eyes="right"),
    ear=pork_frame(ears="flop"),
    sniff=pork_frame(snout="flare"),
    chomp=pork_frame(mouth=True),
    rootL=pork_frame(eyes="left", snout="left"),
    rootR=pork_frame(eyes="right", snout="right"),
    rootLNod=pork_frame(eyes="left", snout="left", nod=True),
    rootRNod=pork_frame(eyes="right", snout="right", nod=True),
    # Needs you: John Pork is calling.
    calling=bang(pork_frame(phone=True, ears="perk", mouth=True), 13, top=0),
    callingShut=bang(pork_frame(phone=True, ears="perk"), 13, top=0),
)

character(
    "johnPork", "John Pork",
    frames=pork_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.8), ("ear", 0.14), ("rest", 0.1), ("ear", 0.14),
          ("rest", 1.6), ("sniff", 0.16), ("rest", 0.12), ("sniff", 0.16), ("rest", 1.2),
          ("lookR", 0.6), ("lookL", 0.6), ("rest", 0.8)],
    working=[("rootLNod", 0.16), ("rootR", 0.16), ("rootL", 0.16), ("rootRNod", 0.16),
             ("chomp", 0.14), ("rest", 0.12), ("chomp", 0.14), ("sniff", 0.14)],
    # Lively: the call buzzes him side to side.
    waiting=[("calling", 0.3), ("callingShut", 0.3), ("calling", 0.3), ("callingShut", 0.5)],
    waiting_motion=motion("wave", 0.4, 0.24, axis="x"),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("ear", 0.3), ("rest", 4.0),
               ("sniff", 0.3), ("rest", 3.0), ("blink", 0.14), ("rest", 2.0)],
    # Calm: the snout swings slowly side to side, with the odd chomp.
    calm_working=[("rootL", 0.5), ("rest", 0.4), ("rootR", 0.5), ("rest", 0.4),
                  ("chomp", 0.4), ("rest", 0.4), ("chomp", 0.4), ("rest", 0.4)],
    calm_waiting=[("calling", 1.4), ("callingShut", 1.0)],
)


# --------------------------------------------------------------------------
# Tung Tung — Tung Tung Tung Sahur, the Italian-brainrot log: a tall wooden
# trunk with a rounded top and two strokes of grain, two huge staring eyes
# (dim whites, one-pixel pupils), a small "o" mouth, stick arms and legs, and
# THE bat held up over its right shoulder (thin handle in the fist, thick
# barrel). A lowered bat reads as a tail at 14px, so the bat stays up: busy =
# it knocks (wound back upright, then down on the shoulder: tung, tung,
# tung); needs you = bat raised straight up, mouth open, "!" on the left.

tung_bats = {  # the right arm plus the bat, per pose
    "shoulder": {(7, 9): "#", (6, 10): "#", (5, 10): "#", (4, 11): "##", (3, 11): "##", (2, 12): "##", (1, 12): "##"},
    "upright": {(7, 9): "#", (6, 10): "#", (5, 10): "#", (4, 10): "##", (3, 11): "##", (2, 11): "##", (1, 11): "##"},
    "strike": {(7, 9): "#", (6, 10): "#", (5, 11): "#", (4, 11): "##", (3, 12): "##", (2, 12): "##"},
    "high": {(6, 9): "#", (5, 10): "#", (4, 10): "#", (3, 10): "##", (2, 10): "##", (1, 10): "##", (0, 10): "##"},
}
tung_pupils = {"open": ((3, 4), (3, 6)), "left": ((3, 3), (3, 6)), "right": ((3, 4), (3, 7)),
               "up": ((2, 4), (2, 6))}


def tung_frame(eyes="open", bat="shoulder", mouth="shut"):
    f = F(
        "...#####......",
        "..#######.....",
        "..#######.....",
        "..#######.....",
        "..#######.....",
        "..#######.....",
        "..#######.....",
        ".########.....",
        "#.#######.....",
        "#.#######.....",
        "..#######.....",
        "...#...#......",
        "...#...#......",
        "..##...##.....",
    )
    if eyes == "closed":
        f = over(f, {(3, 3): "++", (3, 6): "++"})  # a lid line across each eye
    else:
        for c in (3, 6):
            f = over(f, {(2, c): "++", (3, c): "++", (4, c): "++"})
        for r, c in tung_pupils[eyes]:
            f = over(f, {(r, c): "-"})
    f = over(f, {(6, 5): "-", (7, 5): "-" if mouth == "open" else "."})
    f = over(f, {(8, 3): "+", (9, 3): "+", (9, 6): "+", (10, 6): "+"})  # the grain
    return over(f, tung_bats[bat])


tung_rest = tung_frame()
tung_frames = dict(
    rest=tung_rest,
    blink=tung_frame(eyes="closed"),
    lookL=tung_frame(eyes="left"),
    lookR=tung_frame(eyes="right"),
    lean=tung_frame(bat="upright"),
    strike=tung_frame(bat="strike"),
    # Needs you: "!" on the left, the bat raised high, calling "sahur!".
    alert=bang(tung_frame(bat="high", mouth="open", eyes="up"), 0, top=0),
    alertDown=bang(tung_frame(bat="upright"), 0, top=0),
)

character(
    "tungTung", "Tung Tung",
    frames=tung_frames,
    # Lively: three quick knocks (wind-up, swing through, back to the shoulder).
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.8), ("lookL", 0.6), ("lookR", 0.6), ("rest", 1.6),
          ("lean", 0.5), ("rest", 0.3), ("lean", 0.5), ("rest", 1.0)],
    working=[("lean", 0.14), ("strike", 0.12), ("rest", 0.1), ("lean", 0.14), ("strike", 0.12), ("rest", 0.1),
             ("lean", 0.14), ("strike", 0.12), ("rest", 0.2)],
    waiting=[("alert", 0.3), ("alertDown", 0.3)],
    waiting_motion=motion("hop", 0.35, 0.6),
    # Calm: the blank stare; working rocks the bat a column, tung... tung...
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("lookR", 1.2), ("rest", 0.3),
               ("lookL", 1.2), ("rest", 3.5), ("lean", 1.4), ("rest", 2.5), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("lean", 0.5), ("rest", 0.45), ("lean", 0.5), ("rest", 0.45), ("lean", 0.5), ("rest", 0.8)],
    calm_waiting=[("alert", 1.4), ("alertDown", 1.0)],
)


# --------------------------------------------------------------------------
# Tralalero — Tralalero Tralala, the Italian-brainrot shark in sneakers,
# side view facing right like the Dino and the Duck. A torpedo: a long flat
# back with one dorsal fin standing mid-back, a small forked tail, a pointed
# snout over a toothy grin (dim teeth), and two short legs in chunky
# sneakers (a high collar, a sole that juts past the toe): the shark +
# sneakers pairing is the whole joke, so the shoes stay big. Busy = it
# struts, one sneaker up then the other; idle = a blink, a tail flick, the
# odd jaw snap; needs you = jaws open beside the "!".

shark_body = [  # rows 0-6 (rows 7-9 are the jaws); the tail is drawn separately
    "..............",
    "..............",
    "......#.......",
    "......##......",
    ".....###......",
    "...#########..",
    "..########.#..",
]
shark_jaws = {  # rows 7-9: the grin, or the snout lifted off the lower jaw
    "shut": ["..############", "...####.+.+.+.", "...########..."],
    "open": ["..######...+..", "...####.....+.", "...###########"],
}
shark_tails = {  # columns 0-3: upper lobe, fork, lower lobe
    "rest": {4: "#...", 5: "##..", 6: ".##.", 7: ".##.", 8: "##.."},
    "up": {3: "#...", 4: "##..", 5: ".##.", 6: ".##.", 7: "#..."},
}
shark_feet = {  # rows 10-13: legs, collar, upper, sole
    "both": ["....#.....#...", "...##....##...", "...####..####.", "...#####.#####"],
    "back": ["...##.....#...", "...####..##...", "...#####.####.", ".........#####"],
    "front": ["....#....##...", "...##....####.", "...####..#####", "...#####......"],
}


def shark_frame(eyes="open", jaw="shut", tail="rest", feet="both"):
    f = F(*(shark_body + shark_jaws[jaw] + shark_feet[feet]))
    f = over(f, {(r, 0): s for r, s in shark_tails[tail].items()})
    if eyes == "closed":
        f = over(f, {(6, 10): "#"})
    return f


shark_rest = shark_frame()
shark_frames = dict(
    rest=shark_rest,
    blink=shark_frame(eyes="closed"),
    flick=shark_frame(tail="up"),
    snap=shark_frame(jaw="open"),
    stepB=shark_frame(feet="back"),
    stepF=shark_frame(feet="front"),
    stepBFlick=shark_frame(feet="back", tail="up"),
    stepFFlick=shark_frame(feet="front", tail="up"),
    # Needs you: jaws open, "!" over the snout.
    alert=bang(shark_frame(jaw="open"), 13),
    alertShut=bang(shark_rest, 13),
)

character(
    "tralalero", "Tralalero",
    frames=shark_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.8), ("flick", 0.16), ("rest", 0.14), ("flick", 0.16),
          ("rest", 1.6), ("snap", 0.18), ("rest", 0.14), ("snap", 0.18), ("rest", 1.0)],
    working=[("stepBFlick", 0.16), ("rest", 0.08), ("stepF", 0.16), ("rest", 0.08)],
    working_motion=motion("hop", 0.5, 0.24),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("rest", 0.5)],
    waiting_motion=motion("hop", 0.35, 0.6),
    # Calm: still but for a blink and one tail flick; a slow sneaker shuffle.
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("flick", 0.3), ("rest", 4.0),
               ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("stepB", 0.5), ("rest", 0.4), ("stepF", 0.5), ("rest", 0.4),
                  ("stepB", 0.5), ("rest", 0.4), ("stepFFlick", 0.5), ("rest", 0.4)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)


# --------------------------------------------------------------------------
# Bombardiro — Bombardiro Crocodilo, the Italian-brainrot crocodile bomber,
# facing right. The nose is a crocodile head (eye bump on top, nostril at the
# tip, a row of teeth over an open mouth line); behind it the body is a plane
# seen from a little above, wings crossing it like a x (far wing up, the
# nearer, bigger wing down) and a fin at the tail. Busy = the engine on the
# near wing spins its propeller and a bomb drops from the belly; needs you =
# the jaws gape under a "!".


def croc_frame(eyes="open", jaw="teeth", prop=None, bomb=None, alert=False):
    f = F(
        "..##..........",
        "#.###.........",
        "#..###...##...",
        "##..###.#.##..",
        "###########.#.",
        ".#############",
        "..#####.#.#.#.",
        "..#####.......",
        "..############",
        "...#######....",
        "....###.......",
        "...###........",
        "..###.........",
        ".###..........",
    )
    if eyes == "closed":
        f = over(f, {(3, 9): "+"})
    elif eyes == "front":  # glancing ahead
        f = over(f, {(3, 9): "#", (3, 10): "-"})
    if jaw == "crack":  # the lower jaw's tip drops a row
        f = rows(f, {8: "..########....", 9: "...###########"})
    elif jaw == "wide":  # lower jaw swung down, its teeth showing
        f = rows(f, {8: "..######......", 9: "...######.#.#.", 10: "....###..#####"})
    if prop:  # the engine pod on the near wing's leading edge
        f = over(f, {(12, 5): "#"})
    if prop == "a":  # blades up and down: the disc seen edge-on
        f = over(f, {(11, 6): "+", (12, 6): "+", (13, 6): "+"})
    elif prop == "b":  # blades across: just the hub
        f = over(f, {(12, 6): "+"})
    if bomb == 0:  # slung under the belly, fins aft
        f = over(f, {(10, 9): "+##"})
    elif bomb is not None:  # falling nose-down, fins up
        top = 10 + bomb
        f = over(f, {(top, 10): "+", (top + 1, 10): "#", (top + 2, 10): "#"})
    if alert:  # the snout tip and nostril step back so the "!" stands clear
        f = bang(over(f, {(4, 12): "-", (5, 13): "-", (8, 13): "-"}), 13, top=0)
    return f


croc_rest = croc_frame()
croc_frames = dict(
    rest=croc_rest,
    blink=croc_frame(eyes="closed"),
    glance=croc_frame(eyes="front"),
    crack=croc_frame(jaw="crack"),
    propA=croc_frame(prop="a"),
    propB=croc_frame(prop="b"),
    # A bomb drops while the propeller keeps alternating.
    bomb0=croc_frame(prop="a", bomb=0),
    bomb1=croc_frame(prop="b", bomb=1),
    bomb2=croc_frame(prop="a", bomb=2),
    bomb3=croc_frame(prop="b", bomb=3),
    # Needs you: "!" at the snout, the jaws thrown wide.
    alert=croc_frame(jaw="wide", alert=True),
    alertShut=croc_frame(alert=True),
)

character(
    "bombardiro", "Bombardiro",
    frames=croc_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.8), ("crack", 0.3), ("rest", 0.2), ("crack", 0.3),
          ("rest", 1.6), ("glance", 0.8), ("rest", 0.6)],
    idle_motion=motion("wave", 0.3, 3.0),
    working=[("propA", 0.08), ("propB", 0.08), ("propA", 0.08), ("propB", 0.08),
             ("bomb0", 0.12), ("bomb1", 0.1), ("bomb2", 0.1), ("bomb3", 0.1)],
    working_motion=motion("wave", 0.5, 1.2),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("rest", 0.5)],
    waiting_motion=motion("wave", 0.4, 0.8),
    # Calm: still but for a blink, a slow jaw-crack and a glance; busy is the
    # propeller ticking over with a bomb sinking a row each beat.
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("crack", 0.7), ("rest", 4.5),
               ("glance", 1.2), ("rest", 3.0), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("propA", 0.5), ("propB", 0.5), ("propA", 0.5), ("propB", 0.5),
                  ("bomb0", 0.6), ("bomb1", 0.5), ("bomb2", 0.5), ("bomb3", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)


# --------------------------------------------------------------------------
# Ballerina — Ballerina Cappuccina, the Italian-brainrot dancer whose head is
# a cappuccino cup. The cup is the identifier and the biggest shape: a rim
# of dim foam, a handle loop on the right (a 2x2 hole, so it reads as a
# handle and not an eye), then a slim bodice with the arms raised in a small
# V, a flat tutu and legs drawn together en pointe. No face, like the meme;
# the "blink" is a wisp of steam curling up off the foam. Busy = she
# pirouettes (the handle swings right, behind, left, behind while one leg
# holds passé); calm busy is the barre version, passé on one leg then the
# other while the cup steams. Needs you = the free arm flung up beside the
# cup and the "!" past the handle.

ballerina_steam = {  # a wisp rising off the foam: emerges, curls, lifts clear, drifts
    0: [(1, 4)],
    1: [(1, 5), (0, 4)],
    2: [(0, 5)],
    3: [(0, 6)],
}


def ballerina_frame(arms="v", legs="pointe", handle="right", steam=None):
    f = F(
        "..............",
        "..............",
        "..#+++++#.....",
        "..#######.....",
        "..#######.....",
        "..#######.....",
        "...#####......",
        ".....#........",
        "....###.......",
        "...#####......",
        "+#########+...",
        "....#.#.......",
        "....#.#.......",
        ".....#........",
    )
    if handle == "right":  # the full loop
        f = over(f, {(2, 9): "###", (3, 11): "#", (4, 11): "#", (5, 9): "###"})
    elif handle == "turned":  # a quarter turn away: foreshortened to a slot
        f = over(f, {(2, 9): "##", (3, 10): "#", (4, 10): "#", (5, 9): "##"})
    elif handle == "left":  # half way round a pirouette
        f = over(f, {(2, 0): "##", (3, 0): "#", (4, 0): "#", (5, 0): "##"})
    for r, c in ballerina_steam.get(steam, []):
        f = over(f, {(r, c): "+"})
    arm_cells = {
        "v": [(8, 2), (7, 1), (8, 8), (7, 9)],
        "out": [(8, 1), (8, 2), (8, 8), (8, 9)],
        "up": [(8, 2), (7, 1), (6, 0), (5, 0), (4, 0), (3, 0), (8, 8), (7, 9)],
    }[arms]
    for r, c in arm_cells:
        f = over(f, {(r, c): "#"})
    if legs == "passeR":  # right knee out, toe to the standing knee
        f = rows(f, {11: "....#.##......", 12: ".....##......."})
    elif legs == "passeL":
        f = rows(f, {11: "...##.#.......", 12: ".....##......."})
    elif legs == "passeF":  # knee turned to the front, mid-pirouette
        f = rows(f, {11: "....###.......", 12: ".....#........"})
    return f


ballerina_rest = ballerina_frame()
ballerina_frames = dict(
    rest=ballerina_rest,
    steam0=ballerina_frame(steam=0),
    steam1=ballerina_frame(steam=1),
    steam2=ballerina_frame(steam=2),
    steam3=ballerina_frame(steam=3),
    turn=ballerina_frame(handle="turned"),
    out=ballerina_frame(arms="out"),
    passeR=ballerina_frame(legs="passeR"),
    # At the barre: passé one leg, then the other, while the cup steams.
    barreR=ballerina_frame(legs="passeR", steam=2),
    barreDown=ballerina_frame(steam=3),
    barreL=ballerina_frame(legs="passeL", steam=0),
    barreUp=ballerina_frame(steam=1),
    # The pirouette: the handle goes round while she holds passé.
    spinR=ballerina_frame(legs="passeR"),
    spinF=ballerina_frame(legs="passeF", handle=None),
    spinL=ballerina_frame(legs="passeL", handle="left"),
    spinB=ballerina_frame(legs="passeF", handle=None),
    # Needs you: the free arm flung up, "!" past the handle.
    alert=bang(ballerina_frame(arms="up"), 13),
    alertDown=bang(ballerina_rest, 13),
)

character(
    "ballerina", "Ballerina",
    frames=ballerina_frames,
    idle=[("rest", 2.4), ("steam0", 0.25), ("steam1", 0.25), ("steam2", 0.25), ("steam3", 0.25),
          ("rest", 1.6), ("turn", 0.6), ("rest", 1.2), ("out", 0.5), ("rest", 0.4), ("passeR", 0.4),
          ("rest", 0.8)],
    working=[("spinR", 0.14), ("spinF", 0.14), ("spinL", 0.14), ("spinB", 0.14), ("out", 0.4)],
    waiting=[("alert", 0.3), ("alertDown", 0.3), ("alert", 0.3), ("rest", 0.5)],
    waiting_motion=motion("hop", 0.3, 0.6),
    calm_idle=[("rest", 6.0), ("steam0", 0.5), ("steam1", 0.5), ("steam2", 0.6), ("steam3", 0.6),
               ("rest", 5.5), ("turn", 1.4), ("rest", 5.0)],
    calm_working=[("barreR", 0.5), ("barreDown", 0.5), ("barreL", 0.5), ("barreUp", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertDown", 1.0)],
)


# --------------------------------------------------------------------------
# Chimpanzini Bananini — the Italian-brainrot chimp that lives in a banana. A
# round chimp head (fur cap, ears out at eye level, a dim heart-shaped face
# mask with a widow's peak and the eyes set in it) pokes out of the top of
# an upright banana; two peel flaps hang at its sides and the banana curves
# away below, a dim ridge down its length, to a dim stem tip. Moves: blink,
# turn the face, wiggle an ear; working flaps the peel ("wa wa wa") and
# ducks into the banana; needs you = popped right up, mouth an "ooh".

CHIMP_HEAD = [  # rows 1-7 at rest; anything from row 7 down hides in the banana
    "..............",
    ".....####.....",
    "...########...",
    "..##########..",
    "..##########..",
    "..##########..",
    "...########...",
    "....######....",  # neck, seen only when popped up
]
CHIMP_BANANA = [  # rows 7-13; the peel flaps are drawn separately
    "....######....",
    "....######....",
    ".....#+####...",
    "......#+####..",
    ".......#+###..",
    "........###...",
    ".........#+...",
]
CHIMP_EARS = {  # left ear cells; the right ear mirrors them
    "down": ((4, 0), (4, 1), (5, 1)),
    "up": ((3, 0), (3, 1), (4, 1)),
}
CHIMP_FLAPS = {  # left flap cells (the peel's root is at (7, 2)); mirrored on the right
    "down": ((7, 2), (8, 1)),
    "lift": ((7, 2), (7, 1)),  # a small twitch, for Calm
    "out": ((7, 2), (7, 1), (6, 0)),  # flung up, "wa wa wa"
}


def chimp_frame(eyes="open", face=0, mouth="shut", ears="down", flaps="down", dy=0):
    """eyes: open / closed; face: -1 / 0 / 1 turns the mask; mouth: shut / ooh;
    ears and flaps: one state for both, or a (left, right) pair; dy: -1 pops
    the head up a row (showing the neck), 1 ducks it into the banana."""
    head = [list(r) for r in CHIMP_HEAD] + [list("." * W) for _ in range(H - len(CHIMP_HEAD))]
    ear_l, ear_r = (ears, ears) if isinstance(ears, str) else ears
    for (r, c) in CHIMP_EARS[ear_l]:
        head[r][c] = "#"
    for (r, c) in CHIMP_EARS[ear_r]:
        head[r][W - 1 - c] = "#"
    # The face mask: two lobes round the eyes under a widow's peak of fur,
    # merging into the muzzle.
    mask = {3: "+.##.+", 4: "+.++.+", 5: "++++++", 6: ".++++."}
    for r, s in mask.items():
        for i, ch in enumerate(s):
            c = 4 + face + i
            if ch == "+" or (ch == "." and r in (3, 4)):
                head[r][c] = ch
    if eyes == "closed":
        for r in (3, 4):
            head[r][5 + face] = head[r][8 + face] = "+"
    if mouth == "ooh":
        head[6][6 + face] = head[6][7 + face] = "."
    head = shift(["".join(r) for r in head], dy=dy)
    g = [list(r) if i < 7 else list(CHIMP_BANANA[i - 7]) for i, r in enumerate(head)]
    flap_l, flap_r = (flaps, flaps) if isinstance(flaps, str) else flaps
    for (r, c) in CHIMP_FLAPS[flap_l]:
        g[r][c] = "#"
    for (r, c) in CHIMP_FLAPS[flap_r]:
        g[r][W - 1 - c] = "#"
    return F(*("".join(r) for r in g))


CHIMP_BANG = (1, 9)  # col, top: the "!" stands in the space the banana curves away from

chimp_rest = chimp_frame()
chimp_frames = dict(
    rest=chimp_rest,
    blink=chimp_frame(eyes="closed"),
    lookL=chimp_frame(face=-1),
    lookR=chimp_frame(face=1),
    earL=chimp_frame(ears=("up", "down")),
    earR=chimp_frame(ears=("down", "up")),
    ooh=chimp_frame(mouth="ooh"),
    flapL=chimp_frame(flaps=("out", "down")),
    flapR=chimp_frame(flaps=("down", "out")),
    liftL=chimp_frame(flaps=("lift", "down")),
    liftR=chimp_frame(flaps=("down", "lift")),
    liftLookL=chimp_frame(flaps=("lift", "down"), face=-1),
    liftLookR=chimp_frame(flaps=("down", "lift"), face=1),
    duck=chimp_frame(dy=1),  # peeking over the peel
    pop=chimp_frame(dy=-1, flaps="out", ears="up"),
    # Needs you: popped right up, "ooh", the "!" beside the banana.
    alert=bang(chimp_frame(dy=-1, mouth="ooh", flaps="out"), *CHIMP_BANG),
    alertShut=bang(chimp_frame(dy=-1, flaps="out"), *CHIMP_BANG),
    alertRest=bang(chimp_rest, *CHIMP_BANG),
)

character(
    "chimpanzini", "Chimpanzini",
    frames=chimp_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.6), ("earL", 0.14), ("rest", 0.12), ("earR", 0.14),
          ("rest", 1.4), ("lookR", 0.7), ("lookL", 0.7), ("rest", 1.2), ("ooh", 0.3), ("rest", 0.6)],
    working=[("flapL", 0.16), ("flapR", 0.16), ("flapL", 0.16), ("flapR", 0.16), ("duck", 0.14),
             ("pop", 0.2), ("rest", 0.12)],
    waiting=[("alert", 0.3), ("alertRest", 0.3)],
    waiting_motion=motion("hop", 0.35, 0.6),
    # Calm: a blink, an ear, a slow look round; busy = the peel flaps twitch
    # in turn with the odd glance; the "!" holds while the mouth closes.
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("earL", 0.3), ("rest", 3.5),
               ("lookR", 1.2), ("rest", 0.3), ("lookL", 1.2), ("rest", 3.0), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("liftL", 0.5), ("liftR", 0.5), ("liftL", 0.5), ("liftR", 0.5),
                  ("liftLookR", 0.5), ("liftR", 0.5), ("liftLookL", 0.5), ("liftR", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)


# --------------------------------------------------------------------------
# Lirilì — Lirilì Larilà, the Italian-brainrot elephant whose body is a
# cactus, facing right. The elephant's head carries the read: a domed skull,
# a big ear marked off by a one-pixel gap, and a trunk that hangs from the
# snout and hooks up at the tip. Behind it the body is a ribbed cactus
# barrel (dim ribs), dim spines bristle off its back and crown, and it
# stands on stumpy legs in flat sandal soles. It controls time, so busy = a
# pocket watch swinging from its trunk like a pendulum; needs you = trunk
# raised high, trumpeting, beside the "!".

lirili_base = [
    "........+.....",
    ".....+#####+..",
    ".....#######..",
    "....##.###.##.",
    "....##.######.",
    ".+.+##.######.",
    "+####.######..",
    ".#+#+#+###....",
    "+#+#+#+###....",
    ".#+#+#+##.....",
    "+#+#+#+##.....",
]
lirili_legs = {
    "stand": ["..##...##.....", "..##...##.....", ".####.####...."],
    "liftB": ["..##...##.....", ".####..##.....", "......####...."],
    "liftF": ["..##...##.....", "..##..####....", ".####........."],
}
# The hanging trunk (rows 6-10, right of the jaw), cell by cell.
lirili_trunks = {
    "hook": [(6, 12), (7, 11), (8, 11), (9, 11), (10, 11), (10, 12), (10, 13), (9, 13)],
    "coil": [(6, 12), (7, 11), (8, 11), (9, 11), (10, 11), (10, 12), (10, 13), (9, 13), (8, 13), (8, 12)],
    # Holding the watch by its bow: straight down, or swung a pixel forward.
    "tick": [(6, 12), (7, 11), (8, 11), (9, 11)],
    "tock": [(6, 12), (7, 11), (8, 12), (9, 12)],
}
lirili_watch_col = {"tick": 10, "tock": 11}  # the watch's left column, rows 10-12


def lirili_frame(eyes="open", ear="down", trunk="hook", legs="stand", trumpet=True):
    f = F(*(lirili_base + lirili_legs[legs]))
    if trunk == "up":
        # Raised high in front of the face (whose front steps back a column
        # to make room). Trumpeting = the tip flared and the mouth open.
        f = rows(f, {1: ".....+#####+.#", 2: ".....#######.#", 3: "....##.###.#.#",
                     4: "....##.#####.#", 5: ".+.+##.#######"})
        if trumpet:
            f = over(f, {(0, 12): "##", (6, 9): "---", (7, 10): "#"})
        else:
            f = over(f, {(0, 13): "#"})
    else:
        for r, c in lirili_trunks[trunk]:
            f = over(f, {(r, c): "#"})
        if trunk in lirili_watch_col:
            c = lirili_watch_col[trunk]
            f = over(f, {(10, c): "###", (11, c): "#+#", (12, c): "###"})
    if eyes == "closed":
        f = over(f, {(3, 10): "#"})
    if ear == "out":  # the ear fans back a column
        f = over(f, {(2, 4): "#", (3, 3): "#", (4, 3): "#", (5, 3): "#"})
    return f


def lirili_alert(f):
    """The "!" over its back (the spine under the dot is dropped)."""
    return bang(over(f, {(5, 1): "-"}), 1)


lirili_rest = lirili_frame()
lirili_frames = dict(
    rest=lirili_rest,
    blink=lirili_frame(eyes="closed"),
    ear=lirili_frame(ear="out"),
    coil=lirili_frame(trunk="coil"),
    tick=lirili_frame(trunk="tick"),
    tock=lirili_frame(trunk="tock"),
    tickBlink=lirili_frame(trunk="tick", eyes="closed"),
    w1=lirili_frame(trunk="tick", legs="liftB"),
    w2=lirili_frame(trunk="tock"),
    w3=lirili_frame(trunk="tick", legs="liftF"),
    w4=lirili_frame(trunk="tock", ear="out"),
    alert=lirili_alert(lirili_frame(trunk="up")),
    alertShut=lirili_alert(lirili_frame(trunk="up", trumpet=False)),
)

character(
    "lirili", "Lirilì",
    frames=lirili_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.8), ("ear", 0.16), ("rest", 0.14), ("ear", 0.16),
          ("rest", 1.6), ("coil", 0.6), ("rest", 1.0)],
    working=[("w1", 0.2), ("w2", 0.2), ("w3", 0.2), ("w4", 0.2)],
    waiting=[("alert", 0.32), ("alertShut", 0.32), ("alert", 0.32), ("rest", 0.5)],
    waiting_motion=motion("hop", 0.35, 0.64),
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 5.0), ("ear", 0.3), ("rest", 4.0),
               ("coil", 1.2), ("rest", 3.0), ("blink", 0.14), ("rest", 2.0)],
    calm_working=[("tick", 0.55), ("tock", 0.55), ("tick", 0.55), ("tock", 0.55),
                  ("tickBlink", 0.25), ("tick", 0.3), ("tock", 0.55)],
    calm_waiting=[("alert", 1.4), ("alertShut", 1.0)],
)


# --------------------------------------------------------------------------
# Patapim — Brr Brr Patapim, the Italian-brainrot tree monkey, turned three
# quarters to the right: a bushy leaf crown (the dim pixels are leaves), a
# trunk of a face whose big nose droops out past its outline, one long branch
# of an arm, and huge flat bare feet on stalk legs. Busy = a slow stomp, one
# foot then the other; needs-you = the arm goes up and the crown bristles
# ("brr brr").

PATAPIM_CROWN = [
    "...###.###....",
    ".##########...",
    "############..",
    ".###########..",
    "..#########...",
]
PATAPIM_BRISTLE = [  # every leaf on end
    "..#.#.#.#.#...",
    ".##########...",
    "############..",
    ".###########..",
    "..#########...",
]
PATAPIM_LEAVES = [  # dim leaf spots; a rustle blows them one pixel over
    [(1, 3), (1, 8), (2, 2), (2, 6), (3, 5), (3, 9), (4, 8)],
    [(1, 4), (1, 9), (2, 3), (2, 7), (3, 6), (3, 10), (4, 9)],
]
PATAPIM_BODY = [
    "...######.....",
    "...#.##.###...",
    "...##########.",
    "...######.###.",
    "...###++#..#..",
    "...######.....",
    "....#..#......",
    "..............",
    "..............",
]
PATAPIM_ARMS = {  # the near arm, a thin branch pivoting at the left shoulder
    "down": [(8, 2), (9, 1), (10, 0), (11, 0)],
    "out": [(8, 2), (8, 1), (8, 0), (9, 0)],
    "up": [(8, 2), (7, 1), (6, 0), (5, 0)],
}
PATAPIM_FEET = {  # (column, instep, sole): the left foot points left, the right one right
    "left": (0, "..###.", "#####."),
    "right": (7, "###...", "######"),
}


def patapim_frame(eyes="open", leaves=0, arm="down", lift=None, toe=False, mouth="shut",
                  sniff=False, bristle=False):
    f = F(*((PATAPIM_BRISTLE if bristle else PATAPIM_CROWN) + PATAPIM_BODY))
    for r, c in PATAPIM_LEAVES[leaves]:
        f = over(f, {(r, c): "+"})
    if eyes == "closed":
        f = over(f, {(6, 4): "+", (6, 7): "+"})
    if mouth == "open":  # "brr brr"
        f = over(f, {(9, 6): "--"})
    if sniff:  # the nose tip twitches up and out
        f = over(f, {(9, 11): "-", (8, 13): "#"})
    for r, c in PATAPIM_ARMS[arm]:
        f = over(f, {(r, c): "#"})
    # A lifted foot rises a row and swallows its leg (knee up).
    for side, (col, instep, sole) in PATAPIM_FEET.items():
        top = 11 if lift == side else 12
        if lift == side:
            f = over(f, {(11, 4 if side == "left" else 7): "-"})
        f = over(f, {(top, col): instep, (top + 1, col): sole})
    if toe:  # the big toe lifts off the ground
        f = over(f, {(13, 12): "-", (12, 12): "#"})
    return f


patapim_rest = patapim_frame()
patapim_frames = dict(
    rest=patapim_rest,
    blink=patapim_frame(eyes="closed"),
    rustle=patapim_frame(leaves=1),
    sniff=patapim_frame(sniff=True),
    toe=patapim_frame(toe=True),
    # Working: knee up with the arm swung out, stomp (the leaves shake),
    # other knee up, stomp.
    w1=patapim_frame(lift="left", arm="out"),
    w2=patapim_frame(leaves=1),
    w3=patapim_frame(lift="right"),
    w4=patapim_rest,
    # Needs you: "!" beside the crown, the arm up, the mouth open, every
    # leaf on end; the alternate lets the crown settle.
    alert=bang(patapim_frame(arm="up", mouth="open", bristle=True), 13, top=0),
    alertSettle=bang(patapim_frame(arm="up", mouth="open", leaves=1), 13, top=0),
)

character(
    "patapim", "Patapim",
    frames=patapim_frames,
    idle=[("rest", 2.4), ("blink", 0.12), ("rest", 1.6), ("rustle", 0.2), ("rest", 0.2), ("rustle", 0.2),
          ("rest", 1.4), ("toe", 0.2), ("rest", 0.15), ("toe", 0.2), ("rest", 1.0), ("sniff", 0.25),
          ("rest", 0.8)],
    working=[("w1", 0.22), ("w2", 0.18), ("w3", 0.22), ("w4", 0.18)],
    waiting=[("alert", 0.25), ("alertSettle", 0.25)],
    waiting_motion=motion("wave", 0.35, 0.28, axis="x"),
    # Calm: still but for a blink, a rustle and a toe wiggle; a slow stomp.
    calm_idle=[("rest", 6.0), ("blink", 0.14), ("rest", 4.5), ("rustle", 0.6), ("rest", 4.0),
               ("toe", 0.4), ("rest", 0.3), ("toe", 0.4), ("rest", 2.5), ("blink", 0.14), ("rest", 1.5)],
    calm_working=[("w1", 0.5), ("w4", 0.5), ("w3", 0.5), ("w4", 0.5),
                  ("w1", 0.5), ("w2", 0.5), ("w3", 0.5), ("w4", 0.5)],
    calm_waiting=[("alert", 1.4), ("alertSettle", 1.0)],
)


# --------------------------------------------------------------------------
# Output

ORDER = ["dino", "ghost", "crab", "duck", "claude", "cat", "robot", "octopus", "frog", "slime",
         "blob", "poo", "johnPork", "tungTung", "tralalero", "bombardiro", "ballerina", "chimpanzini", "lirili", "patapim"]


STATES = ("idle", "working", "waiting", "calm_idle", "calm_working", "calm_waiting")
SWIFT_STATE = {"idle": "idle", "working": "working", "waiting": "waiting",
               "calm_idle": "calmIdle", "calm_working": "calmWorking", "calm_waiting": "calmWaiting"}


def swift_number(x):
    text = f"{x:.4f}".rstrip("0").rstrip(".")
    return text if "." in text else text + ".0"


def emit_swift():
    assert ORDER == list(CHARACTERS), "ORDER must list every character in definition order"
    out = [
        "// Generated by scripts/generate-pixel-sprites.py. Edit the script, then run it",
        "// again; hand edits here are overwritten.",
        "//",
        "// '#' = pixel, '+' = dim pixel, '.' = empty, on a 14x14 grid.",
        "",
        "import CoreGraphics",
        "",
        "extension PixelCharacterSprite {",
    ]
    for name in ORDER:
        ch = CHARACTERS[name]
        # One entry per distinct picture (frames drawn the same share it).
        used, index, by_content = [], {}, {}
        for state in STATES:
            for frame_name, _ in ch[state][0]:
                key = tuple(ch["frames"][frame_name])
                if key not in by_content:
                    by_content[key] = len(used)
                    used.append(frame_name)
                index[frame_name] = by_content[key]
        out.append(f"    static let {name} = PixelCharacterSprite(")
        out.append("        frames: [")
        for n in used:
            out.append(f"            // {n}")
            out.append("            PixelFrame(")
            rows_ = ch["frames"][n]
            for i, r in enumerate(rows_):
                comma = "," if i < len(rows_) - 1 else ""
                out.append(f'                "{r}"{comma}')
            out.append("            ),")
        out.append("        ],")
        for state in STATES:
            seq, mot = ch[state]
            steps = ", ".join(f"({index[n]}, {swift_number(d)})" for n, d in seq)
            if mot:
                m = (f"PixelMotion(curve: .{mot['curve']}, axis: .{mot['axis']}, "
                     f"amplitude: {swift_number(mot['amplitude'])}, period: {swift_number(mot['period'])})")
            else:
                m = "nil"
            comma = "," if state != STATES[-1] else ""
            out.append(f"        {SWIFT_STATE[state]}: PixelSequence(steps: [{steps}], motion: {m}){comma}")
        out.append("    )")
        out.append("")
    out[-1] = "}"
    out.append("")
    out.append("extension IslandCharacter {")
    out.append("    var title: String {")
    out.append("        switch self {")
    for name in ORDER:
        out.append(f'        case .{name}: "{CHARACTERS[name]["title"]}"')
    out.append("        }")
    out.append("    }")
    out.append("")
    out.append("    var sprite: PixelCharacterSprite {")
    out.append("        switch self {")
    for name in ORDER:
        out.append(f"        case .{name}: .{name}")
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")
    return "\n".join(out)


def emit_ts():
    """The website's copy: each character's rest frame and a working frame."""
    def grid(frame):
        cells = ",".join("[" + ",".join({"#": "1", "+": "2"}.get(ch, "0") for ch in row) + "]" for row in frame)
        return "[" + cells + "]"

    def working_frame(ch):
        rest = ch["frames"][ch["idle"][0][0][0]]
        for name, _ in ch["working"][0]:
            if ch["frames"][name] != rest:
                return ch["frames"][name]
        return rest

    out = [
        "// Generated by scripts/generate-pixel-sprites.py from the app's sprite data;",
        "// edit the script, not this file. 1 = cream pixel, 2 = dim pixel.",
        "export const SPRITES: Record<string, number[][]> = {",
    ]
    for name in ORDER:
        ch = CHARACTERS[name]
        out.append(f"  {name}: {grid(ch['frames'][ch['idle'][0][0][0]])},")
    out.append("};")
    out.append("")
    out.append("// A working frame per character, for the run-cycle \"dance\".")
    out.append("export const SPRITES_RUN: Record<string, number[][]> = {")
    for name in ORDER:
        out.append(f"  {name}: {grid(working_frame(CHARACTERS[name]))},")
    out.append("};")
    out.append("")
    out.append("export const spriteSVG = (grid: number[][]): string => {")
    out.append("  let rects = '';")
    out.append("  grid.forEach((row, y) =>")
    out.append("    row.forEach((v, x) => {")
    out.append("      if (v === 1) rects += `<rect x=\"${x}\" y=\"${y}\" width=\"1\" height=\"1\"/>`;")
    out.append("      else if (v === 2) rects += `<rect x=\"${x}\" y=\"${y}\" width=\"1\" height=\"1\" opacity=\".38\"/>`;")
    out.append("    })")
    out.append("  );")
    out.append("  const w = grid[0]?.length ?? 0;")
    out.append("  return `<svg viewBox=\"0 0 ${w} ${grid.length}\" shape-rendering=\"crispEdges\" fill=\"#f1ead9\" xmlns=\"http://www.w3.org/2000/svg\">${rects}</svg>`;")
    out.append("};")
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, "Sources", "NotchTuneApp", "Views", "PixelSprites.swift")
    with open(target, "w") as fh:
        fh.write(emit_swift())
    print(f"wrote {os.path.relpath(target, root)}: {len(CHARACTERS)} characters")
    site = os.path.join(root, "website", "src", "lib", "sprites.ts")
    with open(site, "w") as fh:
        fh.write(emit_ts())
    print(f"wrote {os.path.relpath(site, root)}")
