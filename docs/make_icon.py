# Draws the MA Compass app icon: a compass whose ring is split into the five tabs
# (Tasks blue, Health green, Food orange, People purple, Net Worth teal).
# Usage: python3 docs/make_icon.py icon-1024.png, then resize into AppIcon.appiconset.
import math, sys
from PIL import Image, ImageDraw, ImageFilter

N = 4096                      # draw large, downscale for smooth edges
s = N / 1024
img = Image.new("RGB", (N, N))
d = ImageDraw.Draw(img)

# Background: deep navy, slightly lighter at the top.
top, bottom = (24, 44, 84), (10, 20, 42)
for y in range(N):
    t = y / (N - 1)
    d.line([(0, y), (N, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))

c = N / 2
# Soft glow behind the dial.
glow = Image.new("L", (N, N), 0)
ImageDraw.Draw(glow).ellipse([c - 360*s, c - 360*s, c + 360*s, c + 360*s], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(90*s))
img.paste(Image.new("RGB", (N, N), (60, 110, 190)), (0, 0), glow)
d = ImageDraw.Draw(img)

# Dial face.
d.ellipse([c - 300*s, c - 300*s, c + 300*s, c + 300*s], fill=(18, 34, 66))

# The ring: five arcs, one per tab (Tasks, Health, Food, People, Net Worth).
colors = [(59, 130, 246), (34, 197, 94), (249, 158, 11), (168, 85, 247), (20, 184, 166)]
R, w, gap = 352*s, 58*s, 7
for i, col in enumerate(colors):
    start = -90 + i * 72 + gap / 2 - 36   # centre the first arc on north
    d.arc([c - R, c - R, c + R, c + R], start, start + 72 - gap, fill=col, width=int(w))

# Cardinal ticks on the face.
for k in range(4):
    a = math.radians(k * 90)
    r1, r2 = 262*s, 292*s
    d.line([(c + r1*math.sin(a), c - r1*math.cos(a)), (c + r2*math.sin(a), c - r2*math.cos(a))],
           fill=(120, 150, 200), width=int(12*s))

# Needle: a long diamond pointing north-east, split lengthwise for a lit edge.
ang = math.radians(32)
L, W = 255*s, 62*s
ux, uy = math.sin(ang), -math.cos(ang)         # towards the tip
px, py = -uy, ux                               # perpendicular
tipN = (c + ux*L, c + uy*L)
tipS = (c - ux*L, c - uy*L)
left = (c + px*W, c + py*W)
right = (c - px*W, c - py*W)
mid = (c, c)
d.polygon([tipN, left, mid], fill=(255, 112, 92))     # north, lit side
d.polygon([tipN, right, mid], fill=(214, 70, 58))     # north, shade
d.polygon([tipS, left, mid], fill=(240, 244, 250))    # south, lit side
d.polygon([tipS, right, mid], fill=(184, 196, 214))   # south, shade

# Centre pin.
d.ellipse([c - 30*s, c - 30*s, c + 30*s, c + 30*s], fill=(240, 244, 250))
d.ellipse([c - 15*s, c - 15*s, c + 15*s, c + 15*s], fill=(18, 34, 66))

out = img.resize((1024, 1024), Image.LANCZOS)
out.save(sys.argv[1])
