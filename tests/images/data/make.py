#!/usr/bin/env python3
# The pictures of tests/images: each as a WebP file (written by
# libwebp, through Pillow) and as the PNG of what libwebp reads back
# from it -- the answer our decoder must give. Run once, by hand, in
# this directory; its outputs are kept in the repository.
#
#   lossless-*.webp   VP8L: decoded exactly
#   lossy-*.webp      VP8: decoded exactly too (the conversion from
#                     YUV and the chroma's enlargement are libwebp's,
#                     done its way)
#   alpha-*.webp      a lossy picture and its alpha plane (VP8X, ALPH)
import math, random
from PIL import Image

random.seed(7)

def gradient(w, h):
    im = Image.new("RGB", (w, h))
    im.putdata([(x * 255 // (w - 1), y * 255 // (h - 1), (x + y) * 255 // (w + h - 2)) for y in range(h) for x in range(w)])
    return im

def scene(w, h, alpha=False):
    """smooth shapes, an edge, and some grain: what a photograph has"""
    px = []
    for y in range(h):
        for x in range(w):
            r = int(127 + 120 * math.sin(x / 9.0) * math.cos(y / 13.0))
            g = int(127 + 100 * math.sin((x + y) / 17.0))
            b = 220 if (x - w / 2) ** 2 + (y - h / 2) ** 2 < (h / 3) ** 2 else int(40 + 60 * y / h)
            n = random.randint(-6, 6)
            c = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))
            px.append(c + (max(0, min(255, int(255 * x / w))),) if alpha else c)
    im = Image.new("RGBA" if alpha else "RGB", (w, h))
    im.putdata(px)
    return im

def flat(w, h, colours):
    """a drawing of a few flat colours: a palette"""
    im = Image.new("RGB", (w, h))
    im.putdata([colours[((x // 5) + (y // 3) * 3) % len(colours)] for y in range(h) for x in range(w)])
    return im

palette = [(0, 0, 0), (255, 255, 255), (200, 30, 30), (30, 160, 60), (30, 60, 200), (240, 200, 20), (120, 120, 120), (250, 120, 200),
           (10, 200, 200), (90, 40, 10), (160, 220, 120), (60, 0, 90), (255, 128, 0), (0, 80, 80), (220, 220, 250), (40, 40, 40), (128, 0, 0)]

def save(name, im, **options):
    im.save(name + ".webp", **options)
    Image.open(name + ".webp").convert("RGBA").save(name + ".png")

save("lossless-gradient", gradient(32, 24), lossless=True)
save("lossless-scene", scene(64, 48), lossless=True)
save("lossless-large", scene(300, 200), lossless=True, quality=100, method=6)
save("lossless-2-colours", flat(41, 30, palette[:2]), lossless=True)
save("lossless-4-colours", flat(41, 30, palette[:4]), lossless=True)
save("lossless-16-colours", flat(41, 30, palette[:16]), lossless=True)
save("lossless-17-colours", flat(41, 30, palette[:17]), lossless=True)
save("lossless-alpha", scene(48, 40, alpha=True), lossless=True)
save("lossless-1x1", Image.new("RGB", (1, 1), (10, 20, 30)), lossless=True)
save("lossy-gradient", gradient(32, 24), quality=80)
save("lossy-scene", scene(64, 48), quality=75)
save("lossy-large", scene(300, 200), quality=50)
save("lossy-odd", scene(37, 21), quality=90)
save("lossy-low", scene(120, 90), quality=10)
save("lossy-flat", flat(41, 30, palette[:6]), quality=60)
save("alpha-scene", scene(48, 40, alpha=True), quality=80)
