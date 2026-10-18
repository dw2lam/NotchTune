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
# Output

ORDER = ["dino", "ghost", "crab", "duck", "claude", "cat", "robot", "octopus", "frog", "slime"]


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
