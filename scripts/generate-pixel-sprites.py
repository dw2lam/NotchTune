#!/usr/bin/env python3
"""Source of truth for the closed-notch pixel characters.

Each character is drawn on a 14x14 grid ('#' = pixel, '+' = dim pixel,
'.' = empty) and animated as three frame sequences: idle, working and
waiting, each optionally with a smooth Core Animation motion (hop / wave).

    python3 scripts/generate-pixel-sprites.py            # writes the Swift data
    python3 scripts/generate-pixel-sprites.py --sheet D  # also renders contact sheets into D

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
              idle_motion=None, working_motion=None, waiting_motion=None):
    for seq in (idle, working, waiting):
        for frame_name, duration in seq:
            assert frame_name in frames, f"{name}: missing frame {frame_name}"
            assert duration > 0
    CHARACTERS[name] = dict(title=title, frames=frames,
                            idle=(idle, idle_motion), working=(working, working_motion),
                            waiting=(waiting, waiting_motion))


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
)

# --------------------------------------------------------------------------
# Claude — the chunky, stubby-legged Claude Code critter. Its working
# sparkle turns like Claude Code's own spinner.

claude_rest = F(
    "..............",
    "..............",
    "..............",
    "..............",
    "..##########..",
    "..##.####.##..",
    "..##.####.##..",
    "##############",
    "..##########..",
    "...#.#..#.#...",
    "...#.#..#.#...",
    "..............",
    "..............",
    "..............",
)
claude_blink = rows(claude_rest, {5: "..##########.."})
claude_look_l = rows(claude_rest, {5: "..#.####.###..", 6: "..#.####.###.."})
claude_look_r = rows(claude_rest, {5: "..###.####.#..", 6: "..###.####.#.."})
claude_legs_a = {9: "...#.#..#.#...", 10: "...#....#....."}
claude_legs_b = {9: "...#.#..#.#...", 10: ".....#....#..."}
# Arms are stubs on body row 4 of 5; a raised stub moves up a row, still attached.
claude_arm_l_up = {6: "####.####.##..", 7: "..############"}
claude_arm_r_up = {6: "..##.####.####", 7: "############.."}
claude_arms_up = {6: "####.####.####", 7: "..##########.."}
spark_plus = {(0, 6): ".#.", (1, 6): "###", (2, 6): ".#."}
spark_x = {(0, 6): "#.#", (1, 6): ".#.", (2, 6): "#.#"}
spark_dim = {(0, 6): ".+.", (1, 6): "+#+", (2, 6): ".+."}


def claude(*edits_rows, spark=None):
    f = claude_rest
    for e in edits_rows:
        f = rows(f, e)
    if spark:
        f = over(f, spark)
    return f


claude_w1 = claude(claude_legs_a, claude_arm_l_up, spark=spark_plus)
claude_w2 = claude(spark=spark_dim)
claude_w3 = claude(claude_legs_b, claude_arm_r_up, spark=spark_x)
claude_w4 = claude(spark=spark_dim)
claude_stretch = claude(claude_arms_up)
# Waiting: the right arm waves overhead, "!" on the left.
claude_wave_a = bang(claude({4: "..##########.#", 5: "..##.####.##.#", 6: "..##.####.###.",
                             7: "############.."}), 0, top=0)
claude_wave_b = bang(claude(claude_arm_r_up), 0, top=0)

character(
    "claude", "Claude",
    frames=dict(rest=claude_rest, blink=claude_blink, lookL=claude_look_l, lookR=claude_look_r,
                stretch=claude_stretch, w1=claude_w1, w2=claude_w2, w3=claude_w3, w4=claude_w4,
                waveA=claude_wave_a, waveB=claude_wave_b),
    idle=[("rest", 2.5), ("blink", 0.12), ("rest", 1.9), ("lookL", 0.8), ("rest", 0.25),
          ("lookR", 0.8), ("rest", 1.6), ("stretch", 0.4), ("rest", 0.4)],
    working=[("w1", 0.12), ("w2", 0.12), ("w3", 0.12), ("w4", 0.12)],
    working_motion=motion("hop", 0.5, 0.24),
    waiting=[("waveA", 0.26), ("waveB", 0.26)],
    waiting_motion=motion("hop", 0.3, 0.52),
)

# --------------------------------------------------------------------------
# Cat — sits with its tail curled; kneads while working.

cat_rest = F(
    "..............",
    "...#....#.....",
    "...##..##.....",
    "...######.....",
    "...#.##.#.....",
    "...##++##....#",
    "....####.....#",
    "...#######..#.",
    "..#########.#.",
    "..##########..",
    "..#########...",
    "...##..##.....",
    "...##..##.....",
    "..............",
)
cat_blink = over(cat_rest, {(4, 4): "+", (4, 7): "+"})
cat_ear = rows(cat_rest, {1: "....#...#.....", 2: "...##..##....."})
cat_tail_up = rows(cat_rest, {5: "...##++##...#.", 6: "....####....#.", 7: "...#######..#.", 8: "..#########.#."})
cat_tail_out = rows(cat_rest, {5: "...##++##.....", 6: "....####......", 7: "...#######...#",
                               8: "..#########.#."})
cat_paw_l = {11: "...##..##.....", 12: "........##...."}
cat_paw_r = {11: "...##..##.....", 12: "...##........."}
cat_w1 = rows(cat_rest, cat_paw_l)
cat_w2 = rows(cat_tail_up, cat_paw_r)
cat_w3 = rows(cat_tail_out, cat_paw_l)
cat_w4 = rows(cat_tail_up, cat_paw_r)
cat_meow = rows(cat_tail_up, {6: "....#..#....#."})
cat_alert = bang(cat_meow, 0)
cat_alert_shut = bang(cat_tail_up, 0)

character(
    "cat", "Cat",
    frames=dict(rest=cat_rest, blink=cat_blink, ear=cat_ear, tailUp=cat_tail_up, tailOut=cat_tail_out,
                w1=cat_w1, w2=cat_w2, w3=cat_w3, w4=cat_w4, alert=cat_alert, alertShut=cat_alert_shut),
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 1.8), ("ear", 0.12), ("rest", 0.1), ("ear", 0.12),
          ("rest", 1.6), ("tailUp", 0.5), ("rest", 0.4), ("tailOut", 0.5), ("rest", 1.2)],
    working=[("w1", 0.13), ("w2", 0.13), ("w3", 0.13), ("w4", 0.13)],
    working_motion=motion("hop", 0.25, 0.26),
    waiting=[("alert", 0.3), ("alertShut", 0.3), ("alert", 0.3), ("tailUp", 0.5)],
)

# --------------------------------------------------------------------------
# Robot — antenna light, visor eyes, a chest panel that chases while busy.

robot_rest = F(
    "......++......",
    "......##......",
    "....######....",
    "...########...",
    "...#..##..#...",
    "...########...",
    "...##++++##...",
    "....######....",
    "..##########..",
    "#.##########.#",
    "#.###++++###.#",
    "..##########..",
    "...##....##...",
    "...###...###..",
)
robot_lit = over(robot_rest, {(0, 6): "##"})
robot_blink = rows(robot_rest, {4: "...########..."})
robot_blink = over(robot_blink, {(4, 4): "++", (4, 8): "++"})
robot_look = over(robot_rest, {(4, 5): "+", (4, 9): "+"})


def robot_panel(f, lit):
    panel = "".join("#" if i == lit else "+" for i in range(4))
    return over(f, {(10, 5): panel})


def robot_arms(f, up):
    if up == "l":
        return rows(f, {8: "#.##########..", 9: "#.##########.#", 10: f[10][:12] + ".#"})
    if up == "r":
        return rows(f, {8: "..##########.#", 9: "#.##########.#", 10: "#." + f[10][2:]})
    return f


robot_legs_b = {12: "...##....##...", 13: "..###....###.."}
robot_w1 = robot_arms(robot_panel(robot_lit, 0), "l")
robot_w2 = rows(robot_panel(robot_rest, 1), robot_legs_b)
robot_w3 = robot_arms(robot_panel(robot_lit, 2), "r")
robot_w4 = rows(robot_panel(robot_rest, 3), robot_legs_b)
robot_alert = bang(robot_arms(robot_lit, "l"), 13, top=0)
robot_alert_shut = robot_arms(robot_rest, "l")

character(
    "robot", "Robot",
    frames=dict(rest=robot_rest, lit=robot_lit, blink=robot_blink, look=robot_look,
                w1=robot_w1, w2=robot_w2, w3=robot_w3, w4=robot_w4,
                alert=robot_alert, alertShut=robot_alert_shut),
    idle=[("rest", 1.6), ("lit", 0.5), ("rest", 1.4), ("blink", 0.14), ("rest", 1.2), ("lit", 0.5),
          ("rest", 0.9), ("look", 0.9), ("rest", 0.5)],
    working=[("w1", 0.12), ("w2", 0.12), ("w3", 0.12), ("w4", 0.12)],
    working_motion=motion("hop", 0.3, 0.24),
    waiting=[("alert", 0.25), ("alertShut", 0.25)],
)

# --------------------------------------------------------------------------
# Octopus — eight-ish tentacles that ripple as it swims.

octo_head = [
    "..............",
    ".....####.....",
    "...########...",
    "..##########..",
    "..##########..",
    "..##..##..##..",
    "..##..##..##..",
    "..##########..",
    "..##########..",
]
OCTO_LEGS = [1, 3, 5, 8, 10, 12]


def octo(t, head=None, raised=False):
    g = [list(r) for r in (head or octo_head)] + [list("." * W) for _ in range(5)]
    for i, c in enumerate(OCTO_LEGS):
        g[9][c] = "#"
        for depth, row in enumerate((10, 11, 12)):
            wave = [0, 1, 0, -1][(t + i + depth) % 4] if depth else 0
            col = c + wave
            if 0 <= col < W:
                g[row][col] = "#" if depth < 2 else "+"
    if raised:
        for row in (9, 10, 11, 12):
            g[row][1] = "."
            g[row][12] = "."
        for row, c in ((8, 1), (7, 0), (6, 0), (8, 12), (7, 13), (6, 13)):
            g[row][c] = "#"
    return F(*["".join(r) for r in g])


octo_blink_head = list(octo_head)
octo_blink_head[5] = "..##########.."
octo_look_head = list(octo_head)
octo_look_head[6] = "..##+.##+.##.."
octo_alert_head = list(octo_head)

character(
    "octopus", "Octopus",
    frames=dict(rest=octo(0), blink=octo(0, octo_blink_head), look=octo(0, octo_look_head),
                c1=octo(1), c2=octo(2), c3=octo(3),
                raisedA=bang(octo(0, raised=True), 13), raisedB=octo(2, raised=True)),
    idle=[("rest", 2.6), ("blink", 0.14), ("rest", 1.8), ("look", 0.9), ("rest", 1.4),
          ("c1", 0.18), ("c2", 0.18), ("rest", 0.8)],
    idle_motion=motion("wave", 0.3, 3.0),
    working=[("rest", 0.14), ("c1", 0.14), ("c2", 0.14), ("c3", 0.14)],
    working_motion=motion("wave", 0.6, 1.12),
    waiting=[("raisedA", 0.3), ("raisedB", 0.3)],
    waiting_motion=motion("wave", 0.35, 0.6),
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
)

# --------------------------------------------------------------------------
# Slime — a blob that squashes and stretches.

slime_rest = F(
    "..............",
    "..............",
    "..............",
    "......##......",
    ".....####.....",
    "....######....",
    "...########...",
    "..##########..",
    "..##..##..##..",
    ".###..##..###.",
    ".############.",
    "##############",
    ".############.",
    "..............",
)
slime_blink = rows(slime_rest, {8: "..##########..", 9: ".###++##++###."})
slime_squash = F(
    "..............",
    "..............",
    "..............",
    "..............",
    "..............",
    "......##......",
    "....######....",
    "..##########..",
    ".###..##..###.",
    ".###..##..###.",
    "##############",
    "##############",
    "##############",
    "..............",
)
slime_stretch = F(
    "..............",
    "......##......",
    ".....####.....",
    ".....####.....",
    "....######....",
    "....######....",
    "...########...",
    "...#..##..#...",
    "...#..##..#...",
    "...########...",
    "..##########..",
    "..##########..",
    "...########...",
    "..............",
)
slime_alert = bang(slime_stretch, 12, top=0)
slime_alert_shut = slime_rest

character(
    "slime", "Slime",
    frames=dict(rest=slime_rest, blink=slime_blink, squash=slime_squash, stretch=slime_stretch,
                alert=slime_alert, alertShut=slime_alert_shut),
    idle=[("rest", 2.4), ("blink", 0.14), ("rest", 2.0), ("squash", 0.16), ("rest", 0.16),
          ("squash", 0.16), ("rest", 1.6)],
    working=[("squash", 0.12), ("stretch", 0.14), ("rest", 0.12), ("stretch", 0.14)],
    working_motion=motion("hop", 0.7, 0.52),
    waiting=[("alert", 0.3), ("alertShut", 0.3)],
    waiting_motion=motion("hop", 0.5, 0.6),
)


# --------------------------------------------------------------------------
# Output

ORDER = ["dino", "ghost", "crab", "duck", "claude", "cat", "robot", "octopus", "frog", "slime"]


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
        for state in ("idle", "working", "waiting"):
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
        for state in ("idle", "working", "waiting"):
            seq, mot = ch[state]
            steps = ", ".join(f"({index[n]}, {swift_number(d)})" for n, d in seq)
            if mot:
                m = (f"PixelMotion(curve: .{mot['curve']}, axis: .{mot['axis']}, "
                     f"amplitude: {swift_number(mot['amplitude'])}, period: {swift_number(mot['period'])})")
            else:
                m = "nil"
            comma = "," if state != "waiting" else ""
            out.append(f"        {state}: PixelSequence(steps: [{steps}], motion: {m}){comma}")
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
