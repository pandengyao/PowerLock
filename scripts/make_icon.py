#!/usr/bin/env python3
"""Generate AppIcon.iconset for PowerLock.app."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersampled canvas
TOP = (74, 141, 255)
BOTTOM = (26, 74, 208)

OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"


def gradient(size):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        col = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (size, y)], fill=col)
    return img


canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    [210, 230, S - 210, S - 190], radius=440, fill=(10, 30, 80, 80)
)
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(38)))

# squircle mask
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([200, 200, S - 200, S - 200], radius=450, fill=255)

# blue gradient + soft top highlight
plate = gradient(S)
highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(highlight).ellipse([-200, -1150, S + 200, 700], fill=(255, 255, 255, 30))
plate = Image.alpha_composite(plate, highlight.filter(ImageFilter.GaussianBlur(140)))
canvas.paste(plate, (0, 0), mask)

d = ImageDraw.Draw(canvas)

# lock body
body_w = int(S * 0.40)
body_h = int(S * 0.28)
bx0 = (S - body_w) // 2
by0 = int(S * 0.475)
bx1 = bx0 + body_w
by1 = by0 + body_h
d.rounded_rectangle([bx0, by0, bx1, by1], radius=int(S * 0.06), fill=(255, 255, 255, 255))

# shackle, open on the right
r = int(S * 0.137)
cy = by0 - int(S * 0.045)
w = int(S * 0.072)
d.arc([S // 2 - r, cy - r, S // 2 + r, cy + r], 180, 330,
      fill=(255, 255, 255, 255), width=w)
d.rectangle([S // 2 - r - w // 2, cy, S // 2 - r + w // 2, by0 + 12],
            fill=(255, 255, 255, 255))
cap = w // 2
for ang in (180, 330):
    x = S // 2 + r * math.cos(math.radians(ang))
    y = cy + r * math.sin(math.radians(ang))
    d.ellipse([x - cap, y - cap, x + cap, y + cap], fill=(255, 255, 255, 255))

icon = canvas.resize((1024, 1024), Image.LANCZOS)

os.makedirs(OUT, exist_ok=True)
sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
for name, px in sizes.items():
    icon.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
icon.save(os.path.join(OUT, "..", "AppIcon-1024.png"))
print("wrote", OUT)
