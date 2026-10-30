"""Draws the EphemeraAI launcher icon and splash mark into android/app/src/main/res.

A cream ticket stub with a serif "E", tilted, with a strip of washi tape, on
terracotta. Run from app/:  ../proxy/.venv/Scripts/python tool/make_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RES = Path(__file__).resolve().parent.parent / "android/app/src/main/res"
FONT = "C:/Windows/Fonts/georgiab.ttf"

TERRACOTTA = (181, 96, 63, 255)
PAPER = (244, 236, 221, 255)
PAPER_DEEP = (226, 213, 190, 255)
INK = (47, 42, 38, 255)
TAPE = (111, 127, 90, 190)  # moss, translucent

SIZE = 1024  # working canvas; downscaled for each density
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {k: v * 108 // 48 for k, v in LEGACY.items()}  # 108dp foreground
SPLASH = {k: v * 2 for k, v in LEGACY.items()}  # 96dp splash mark


def ticket(scale: float) -> Image.Image:
    """The tilted ticket + tape, transparent around it, on a SIZE canvas."""
    w, h = int(560 * scale), int(400 * scale)
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=int(26 * scale), fill=PAPER)
    notch = int(46 * scale)
    for y in (h // 2,):
        d.ellipse((-notch, y - notch, notch, y + notch), fill=(0, 0, 0, 0))
        d.ellipse((w - notch, y - notch, w + notch, y + notch), fill=(0, 0, 0, 0))
    # perforation line before the stub
    x = int(w * 0.72)
    for y in range(int(24 * scale), h - int(24 * scale), int(28 * scale)):
        d.ellipse((x - 5 * scale, y, x + 5 * scale, y + 10 * scale), fill=PAPER_DEEP)
    font = ImageFont.truetype(FONT, int(300 * scale))
    d.text((w * 0.36, h * 0.52), "E", font=font, fill=INK, anchor="mm")
    d.line(
        (w * 0.78, h * 0.3, w * 0.92, h * 0.3), fill=PAPER_DEEP, width=int(10 * scale)
    )
    d.line(
        (w * 0.78, h * 0.45, w * 0.9, h * 0.45), fill=PAPER_DEEP, width=int(10 * scale)
    )

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow.paste((60, 30, 20, 90), mask=card.split()[3])
    spun_shadow = shadow.rotate(8, expand=True, resample=Image.BICUBIC).filter(
        ImageFilter.GaussianBlur(14 * scale)
    )
    spun = card.rotate(8, expand=True, resample=Image.BICUBIC)
    ox, oy = (SIZE - spun.width) // 2, (SIZE - spun.height) // 2
    canvas.alpha_composite(spun_shadow, (ox + int(10 * scale), oy + int(18 * scale)))
    canvas.alpha_composite(spun, (ox, oy))

    tape = Image.new("RGBA", (int(300 * scale), int(86 * scale)), TAPE)
    tape = tape.rotate(-14, expand=True, resample=Image.BICUBIC)
    canvas.alpha_composite(
        tape, (SIZE // 2 - tape.width // 2 + int(150 * scale), oy - int(8 * scale))
    )
    return canvas


def save(img: Image.Image, folder: str, name: str, px: int) -> None:
    out = RES / folder
    out.mkdir(parents=True, exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(out / name)


def main() -> None:
    legacy = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(legacy).rounded_rectangle(
        (0, 0, SIZE - 1, SIZE - 1), radius=220, fill=TERRACOTTA
    )
    legacy.alpha_composite(ticket(1.0))
    # The adaptive foreground keeps the art inside the 66dp safe zone.
    foreground = ticket(0.62)
    splash = ticket(0.95)
    for density, px in LEGACY.items():
        save(legacy, f"mipmap-{density}", "ic_launcher.png", px)
        save(foreground, f"mipmap-{density}", "ic_launcher_foreground.png", ADAPTIVE[density])
        save(splash, f"drawable-{density}", "splash_mark.png", SPLASH[density])
    print("icons written to", RES)


if __name__ == "__main__":
    main()
