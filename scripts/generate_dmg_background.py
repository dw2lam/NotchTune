#!/usr/bin/env python3
"""Generate the DMG installer background image for NotchTune.

Produces a 660x400 (Retina: 1320x800) PNG with:
- Clean white background
- "NotchTune" title above the install targets
- Minimal arrow with "drag to install" label between icon positions
"""

import os

from PIL import Image, ImageDraw, ImageFont

# --- Dimensions (Retina 2x) ---
W, H = 1320, 800  # DMG window will be 660x400 @2x

# --- Colors ---
BG = (255, 255, 255)
TEXT_COLOR = (16, 16, 18)
TEXT_DIM = (106, 106, 112)
ARROW_COLOR = (78, 78, 84)

# Icon center positions (in @2x coords)
# DMG window 660pt -> icons at ~180pt and ~480pt from left
APP_ICON_CENTER = (360, 460)
APPS_ICON_CENTER = (960, 460)

ARROW_Y = 420
ARROW_LEFT = 480
ARROW_RIGHT = 840


def load_font(size, preferred_names):
    for name in [
        *preferred_names,
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        if os.path.exists(name):
            try:
                return ImageFont.truetype(name, size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_title(draw, text, center_x, top_y):
    """Draw the product name above the install targets."""
    font = load_font(
        74,
        [
            "/System/Library/Fonts/SFNSDisplay.ttf",
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        ],
    )

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    x = center_x - tw // 2
    draw.text((x, top_y), text, fill=TEXT_COLOR, font=font)


def draw_dashed_arrow(draw, y, x1, x2):
    """Draw a clean arrow with 'drag to install' label."""
    thickness = 4
    color = ARROW_COLOR

    draw.rounded_rectangle([x1, y - thickness // 2, x2 - 24, y + thickness // 2], radius=thickness, fill=color)

    arrow_size = 22
    draw.line([(x2 - arrow_size, y - arrow_size), (x2, y), (x2 - arrow_size, y + arrow_size)], fill=color, width=thickness)

    label = "drag to install"
    font = load_font(28, ["/System/Library/Fonts/SFNS.ttf"])
    bbox = draw.textbbox((0, 0), label, font=font)
    lw = bbox[2] - bbox[0]
    lx = (x1 + x2) // 2 - lw // 2
    draw.text((lx, y + 34), label, fill=TEXT_DIM, font=font)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(repo_root, "Assets", "Brand", "dmg-background.png")
    retina_path = os.path.join(repo_root, "Assets", "Brand", "dmg-background@2x.png")

    img = Image.new("RGBA", (W, H), BG)
    draw = ImageDraw.Draw(img)

    draw_title(draw, "NotchTune", W // 2, 74)
    draw_dashed_arrow(draw, ARROW_Y, ARROW_LEFT, ARROW_RIGHT)

    img.save(retina_path, "PNG")

    # Also save a 1x version for non-retina
    img_1x = img.resize((W // 2, H // 2), Image.LANCZOS)
    img_1x.save(output_path, "PNG")

    print(f"DMG background: {output_path}")
    print(f"DMG background @2x: {retina_path}")


if __name__ == "__main__":
    main()
