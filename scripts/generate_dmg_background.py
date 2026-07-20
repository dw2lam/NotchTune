#!/usr/bin/env python3
"""Generate NotchTune's playful, Apple-inspired DMG background."""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


W, H = 1320, 800
APP_ICON_CENTER = (360, 420)
APPS_ICON_CENTER = (960, 420)

INK = (14, 28, 39, 255)
INK_DIM = (46, 74, 91, 210)
CYAN = (15, 166, 218, 255)


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


def centered_text(draw, text, y, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    x = (W - (bbox[2] - bbox[0])) // 2
    draw.text((x, y), text, font=font, fill=fill)


def glass_panel(base):
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    panel_bounds = (190, 258, 1130, 624)
    shadow_draw.rounded_rectangle(
        (panel_bounds[0], panel_bounds[1] + 14, panel_bounds[2], panel_bounds[3] + 18),
        radius=54,
        fill=(14, 68, 88, 54),
    )
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    glass = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glass_draw = ImageDraw.Draw(glass)
    glass_draw.rounded_rectangle(
        panel_bounds,
        radius=54,
        fill=(248, 254, 255, 178),
        outline=(255, 255, 255, 220),
        width=3,
    )
    glass_draw.rounded_rectangle(
        (198, 266, 1122, 616),
        radius=48,
        outline=(121, 218, 241, 65),
        width=2,
    )
    base.alpha_composite(glass)


def draw_pixel_arrow(draw):
    """A crisp 8-bit arrow between Finder's two install targets."""
    y = 421
    square = 13
    x = 510
    colors = [
        (76, 198, 228, 150),
        (51, 188, 224, 175),
        (27, 176, 219, 205),
        CYAN,
    ]
    for index in range(7):
        color = colors[min(index // 2, len(colors) - 1)]
        draw.rounded_rectangle(
            (x + index * 37, y - square // 2, x + index * 37 + square, y + square // 2),
            radius=3,
            fill=color,
        )

    arrow_x = 783
    pixel = 17
    draw.rectangle((arrow_x, y - pixel // 2, arrow_x + 43, y + pixel // 2), fill=CYAN)
    draw.rectangle((arrow_x + 26, y - 25, arrow_x + 43, y + 25), fill=CYAN)
    draw.rectangle((arrow_x + 43, y - 17, arrow_x + 60, y + 17), fill=CYAN)
    draw.rectangle((arrow_x + 60, y - 8, arrow_x + 77, y + 8), fill=CYAN)


def draw_sparkles(draw):
    for x, y, size, alpha in [
        (235, 300, 7, 110),
        (1080, 314, 8, 120),
        (1120, 564, 5, 90),
        (212, 552, 5, 85),
    ]:
        color = (255, 255, 255, alpha)
        draw.rectangle((x - size * 2, y - size // 2, x + size * 2, y + size // 2), fill=color)
        draw.rectangle((x - size // 2, y - size * 2, x + size // 2, y + size * 2), fill=color)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    brand_dir = os.path.join(repo_root, "Assets", "Brand")
    source_path = os.path.join(brand_dir, "dmg-pixel-landscape-source.png")
    output_path = os.path.join(brand_dir, "dmg-background.png")
    retina_path = os.path.join(brand_dir, "dmg-background@2x.png")

    source = Image.open(source_path).convert("RGBA")
    image = ImageOps.fit(
        source,
        (W, H),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.48),
    )

    # Calm the generated landscape so Finder's real app icons remain the focus.
    wash = Image.new("RGBA", (W, H), (245, 253, 255, 22))
    image.alpha_composite(wash)
    glass_panel(image)

    draw = ImageDraw.Draw(image)
    title_font = load_font(
        58,
        [
            "/System/Library/Fonts/SFNSDisplay.ttf",
            "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        ],
    )
    subtitle_font = load_font(25, ["/System/Library/Fonts/SFNS.ttf"])
    label_font = load_font(
        22,
        ["/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc"],
    )

    centered_text(draw, "Install NotchTune", 94, title_font, INK)
    centered_text(
        draw,
        "Drag the app into Applications and your notch is ready.",
        171,
        subtitle_font,
        INK_DIM,
    )
    draw_pixel_arrow(draw)
    centered_text(draw, "DRAG TO INSTALL", 535, label_font, (27, 105, 132, 185))
    draw_sparkles(draw)

    image.save(retina_path, "PNG")
    image.resize((W // 2, H // 2), Image.Resampling.LANCZOS).save(output_path, "PNG")

    print(f"DMG background: {output_path}")
    print(f"DMG background @2x: {retina_path}")


if __name__ == "__main__":
    main()
