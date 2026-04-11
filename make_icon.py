#!/usr/bin/env python3
"""
Generates AppIcon.icns for Notaty.

Minimal design: a rounded blue square with three white horizontal
"note lines" centered on it.
"""

import os
import shutil
import subprocess
from PIL import Image, ImageDraw

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(OUT_DIR, "build_iconset", "AppIcon.iconset")
ICNS_OUT = os.path.join(OUT_DIR, "AppIcon.icns")

BLUE = (10, 132, 255, 255)   # macOS system blue
WHITE = (255, 255, 255, 255)


def draw_icon(size: int) -> Image.Image:
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    margin = int(s * 0.08)
    radius = int(s * 0.22)
    d.rounded_rectangle(
        (margin, margin, s - margin, s - margin),
        radius=radius,
        fill=BLUE,
    )

    line_count = 3
    gap = int(s * 0.14)
    total_height = (line_count - 1) * gap
    line_left = int(s * 0.28)
    line_right = int(s * 0.72)
    line_thickness = max(3, int(s * 0.045))
    top = (s - total_height) // 2 - line_thickness // 2

    for i in range(line_count):
        y = top + i * gap
        x_end = line_right if i != line_count - 1 else int(line_left + (line_right - line_left) * 0.7)
        d.rounded_rectangle(
            (line_left, y, x_end, y + line_thickness),
            radius=line_thickness // 2,
            fill=WHITE,
        )

    return img


def main():
    if os.path.exists(ICONSET):
        shutil.rmtree(ICONSET)
    os.makedirs(ICONSET)

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, filename in sizes:
        img = draw_icon(size)
        img.save(os.path.join(ICONSET, filename))

    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS_OUT], check=True)
    print(f"Built {ICNS_OUT}")

    shutil.rmtree(os.path.dirname(ICONSET))


if __name__ == "__main__":
    main()
