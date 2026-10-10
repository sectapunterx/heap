"""Build the lowkey logo package: outlined wordmark SVGs, app icon SVG/PNG/ICO, favicon.

Wordmark: «lowkey» in Golos Text Medium, shaped with HarfBuzz (font kerning), tracking −3.5 %,
«low» underlined by a rounded bar. Icon: «l» with the low bar on a dark tile (canvas LK-06, column C).
Run: python build_logo.py   (needs fontTools, uharfbuzz, Pillow)
"""
import json, os
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, 'fonts', 'GolosText-Medium.ttf')
OUT = os.path.join(HERE, 'lowkey')
os.makedirs(OUT, exist_ok=True)

INK_DARK, LAV_DARK = '#e9edf2', '#b1a7f0'   # on dark backgrounds
INK_LIGHT, LAV_LIGHT = '#0c0e11', '#5a4fb3'  # on light backgrounds
TILE, TILE_EDGE = '#16191f', '#262c34'

TEXT = 'lowkey'
TRACK = -0.035          # em
BAR_H = 0.075           # em, underline thickness
BAR_GAP = 0.135         # em, from baseline down to the bar's top

# ---------- wordmark geometry (font units, y up) ----------
font = TTFont(FONT)
upem = font['head'].unitsPerEm
gs = font.getGlyphSet()
blob = hb.Blob.from_file_path(FONT)
hbfont = hb.Font(hb.Face(blob))
buf = hb.Buffer()
buf.add_str(TEXT)
buf.guess_segment_properties()
hb.shape(hbfont, buf, {'kern': True, 'liga': False})
names = [font.getGlyphName(i.codepoint) for i in buf.glyph_infos]
track = TRACK * upem

paths, x, starts = [], 0.0, []
for name, pos in zip(names, buf.glyph_positions):
    starts.append(x)
    pen = SVGPathPen(gs)
    # flip y: SVG y down. Baseline at y=0.
    gs[name].draw(TransformPen(pen, (1, 0, 0, -1, x + pos.x_offset, -pos.y_offset)))
    paths.append(pen.getCommands())
    x += pos.x_advance + track
width = x - track

# ink bounds of «low»: from l's left side bearing to w's right edge
def bounds(name, dx):
    from fontTools.pens.boundsPen import BoundsPen
    bp = BoundsPen(gs)
    gs[name].draw(bp)
    xmin, ymin, xmax, ymax = bp.bounds
    return xmin + dx, ymin, xmax + dx, ymax

l_box = bounds(names[0], starts[0])
w_box = bounds(names[2], starts[2])
y_box = bounds(names[5], starts[5])
ink_left = l_box[0]
ink_right = bounds(names[5], starts[5])[2]
bar = dict(x=l_box[0], y=BAR_GAP * upem, w=w_box[2] - l_box[0], h=BAR_H * upem)
asc = bounds(names[0], starts[0])[3]           # top of l
desc = max(-y_box[1], bar['y'] + bar['h'])      # lowest of y's tail and the bar

pad = 0.0
vb = (ink_left - pad, -asc - pad, (ink_right - ink_left) + 2 * pad, asc + desc + 2 * pad)
glyph_d = ' '.join(paths)
r = bar['h'] / 2


def wordmark_svg(ink, acc, title='lowkey'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb[0]:.1f} {vb[1]:.1f} {vb[2]:.1f} {vb[3]:.1f}" role="img" aria-label="{title}">'
            f'<path d="{glyph_d}" fill="{ink}"/>'
            f'<rect x="{bar["x"]:.1f}" y="{bar["y"]:.1f}" width="{bar["w"]:.1f}" height="{bar["h"]:.1f}" rx="{r:.1f}" fill="{acc}"/></svg>\n')


variants = {
    'lowkey-wordmark-on-dark.svg': (INK_DARK, LAV_DARK),
    'lowkey-wordmark-on-light.svg': (INK_LIGHT, LAV_LIGHT),
    'lowkey-wordmark-black.svg': ('#000000', '#000000'),
    'lowkey-wordmark-white.svg': ('#ffffff', '#ffffff'),
}
for fn, (ink, acc) in variants.items():
    open(os.path.join(OUT, fn), 'w', encoding='utf-8').write(wordmark_svg(ink, acc))

# ---------- icon: «l» with the low bar on a tile, 1024 grid ----------
# the 32-grid mark (stem x8 y5 4x20, bar x8 y21 18x4) scaled ×19 and centred in the tile
ICON = dict(size=1024, radius=230, stem=(341, 303, 76, 380), bar=(341, 607, 342, 76))


def icon_svg(tile, edge, ink, acc, size=1024):
    i, (sx, sy, sw, sh), (bx, by, bw, bh) = ICON, ICON['stem'], ICON['bar']
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024" role="img" aria-label="lowkey">'
            f'<rect x="8" y="8" width="1008" height="1008" rx="{i["radius"]}" fill="{tile}" stroke="{edge}" stroke-width="16"/>'
            f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="{sw // 2}" fill="{ink}"/>'
            f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{bh // 2}" fill="{acc}"/></svg>\n')


open(os.path.join(OUT, 'lowkey-icon.svg'), 'w').write(icon_svg(TILE, TILE_EDGE, INK_DARK, LAV_DARK))
open(os.path.join(OUT, 'lowkey-icon-light.svg'), 'w').write(icon_svg('#ffffff', '#dde3ec', INK_LIGHT, LAV_LIGHT))
# favicon: the mark alone, transparent; colours follow the browser theme
open(os.path.join(OUT, 'favicon.svg'), 'w').write(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<style>.s{fill:#0c0e11}.b{fill:#5a4fb3}@media (prefers-color-scheme:dark){.s{fill:#e9edf2}.b{fill:#b1a7f0}}</style>'
    '<rect class="s" x="7" y="4" width="5" height="22" rx="2.5"/><rect class="b" x="7" y="21" width="20" height="5" rx="2.5"/></svg>\n')


def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def icon_png(px, tile=TILE, edge=TILE_EDGE, ink=INK_DARK, acc=LAV_DARK):
    if px <= 32:   # hand-snapped to the pixel grid: whole-pixel stem and bar, no blur
        im = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, px - 1, px - 1), max(3, round(px * 0.22)), fill=hex2rgb(tile) + (255,), outline=hex2rgb(edge) + (255,))
        t = 2 if px <= 16 else (3 if px <= 24 else 4)       # stroke
        x0 = round(px * 0.33)
        top, bottom = round(px * 0.27), round(px * 0.70)
        bar_w = round(px * 0.34)
        d.rectangle((x0, top, x0 + t - 1, bottom - 1), fill=hex2rgb(ink) + (255,))
        d.rectangle((x0, bottom - t, x0 + bar_w - 1, bottom - 1), fill=hex2rgb(acc) + (255,))
        return im
    s = 4  # supersample
    big = Image.new('RGBA', (px * s, px * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    k = px * s / 1024
    i = ICON
    d.rounded_rectangle((8 * k, 8 * k, 1016 * k, 1016 * k), i['radius'] * k, fill=hex2rgb(tile) + (255,),
                        outline=hex2rgb(edge) + (255,), width=max(1, round(16 * k)))
    for (x, y, w, h), col in ((i['stem'], ink), (i['bar'], acc)):
        d.rounded_rectangle((x * k, y * k, (x + w) * k, (y + h) * k), min(w, h) * k / 2, fill=hex2rgb(col) + (255,))
    return big.resize((px, px), Image.LANCZOS)


png_dir = os.path.join(OUT, 'png')
os.makedirs(png_dir, exist_ok=True)
sizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024]
imgs = {}
for px in sizes:
    imgs[px] = icon_png(px)
    imgs[px].save(os.path.join(png_dir, f'lowkey-icon-{px}.png'))
    icon_png(px, '#ffffff', '#dde3ec', INK_LIGHT, LAV_LIGHT).save(os.path.join(png_dir, f'lowkey-icon-light-{px}.png'))
imgs[256].save(os.path.join(OUT, 'lowkey.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
               append_images=[imgs[p] for p in (16, 24, 32, 48, 64, 128)])

# geometry for other tools (canvas artboard, site)
json.dump({'viewBox': vb, 'glyphs': glyph_d, 'bar': bar, 'radius': r, 'upem': upem, 'icon': ICON},
          open(os.path.join(OUT, 'geometry.json'), 'w'))
print('wordmark', [round(v) for v in vb], 'bar', {k: round(v) for k, v in bar.items()}, 'files', sorted(os.listdir(OUT)))
