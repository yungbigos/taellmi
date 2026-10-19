import sys, os, json
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

font_path, out_dir, tokens_path = sys.argv[1:4]
T = json.load(open(tokens_path))
f = instantiateVariableFont(TTFont(font_path), {"wght": 700})
gs = f.getGlyphSet(); cmap = f.getBestCmap(); UPM = f['head'].unitsPerEm
def gname(ch): return cmap[ord(ch)]
def adv(ch): return f['hmtx'][gname(ch)][0]
def path(ch, x, base, scale):
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}".rstrip('0').rstrip('.'))
    gs[gname(ch)].draw(TransformPen(pen, (scale, 0, 0, -scale, x, base)))
    return pen.getCommands()
def bounds(ch):
    bp = BoundsPen(gs); gs[gname(ch)].draw(bp); return bp.bounds  # xmin,ymin,xmax,ymax font units, y up

C = T['color']; L2 = T['talli']['body']
def hexop(hx, op): return f'{hx}" stop-opacity="{op}'
def write(name, svg):
    p = os.path.join(out_dir, name); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write(svg); print('wrote', name)

# ---------- wordmark (soft eyes, 2b) ----------
def wordmark(ink, pink, size=200):
    s = size / UPM; soft = T['wordmark']['soften_stroke'] * size; pad = soft
    base = size * 0.95 + pad
    x = pad; parts = []; a_box = None
    for ch in 'tallmi':
        parts.append(path(ch, x, base, s))
        if ch == 'a' and a_box is None:
            b = bounds('a'); a_box = (x + b[0]*s, base - b[3]*s, x + b[2]*s, base - b[1]*s)
        x += adv(ch) * s
    W = x + pad; dots = T['wordmark']['dots']
    cx = (a_box[0] + a_box[2]) / 2 - 0.02*size; r = dots['radius']*size; gap = dots['gap']*size
    cy = a_box[1] - dots['lift']*size - soft/2 - r
    H = base + size*0.06 + pad; top = min(0, cy - r - pad)
    d = ' '.join(parts)
    circles = ''.join(f'<circle cx="{cx+k*gap/2:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{pink}"/>' for k in (-1, 1))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {top:.2f} {W:.2f} {H-top:.2f}" role="img" aria-label="tällmi">'
            f'<path d="{d}" fill="{ink}" stroke="{ink}" stroke-width="{soft:.2f}" stroke-linejoin="round"/>{circles}</svg>\n')

# ---------- tälli / mark: the softened ä ----------
def talli_group(size, cx_c, cy_c, uid, material=True, ink=None, pink='#FF6A9C', eye=(0, 0)):
    """Draw the softened a with its bbox centre at (cx_c, cy_c). Returns svg defs+body."""
    s = size / UPM; b = bounds('a'); w = (b[2]-b[0])*s; asc = b[3]*s
    x = cx_c - w/2 - b[0]*s; base = cy_c + asc/2
    d = path('a', x, base, s); soft = T['talli']['glyph']['soften_stroke'] * size
    x0, y0 = x + b[0]*s, base - asc
    out_defs, body = '', ''
    if material:
        fl = L2['fill']
        stops = ''.join(f'<stop offset="{st["at"]}" stop-color="{st["color"]}"/>' for st in fl['stops'])
        out_defs += (f'<linearGradient id="body{uid}" gradientUnits="userSpaceOnUse" x1="{x0+fl["from"][0]*w:.2f}" y1="{y0+fl["from"][1]*asc:.2f}" '
                     f'x2="{x0+fl["to"][0]*w:.2f}" y2="{y0+fl["to"][1]*asc:.2f}">{stops}</linearGradient>')
        out_defs += f'<mask id="m{uid}"><path d="{d}" fill="#fff" stroke="#fff" stroke-width="{soft:.2f}" stroke-linejoin="round"/></mask>'
        body += f'<path d="{d}" fill="url(#body{uid})" stroke="url(#body{uid})" stroke-width="{soft:.2f}" stroke-linejoin="round"/>'
        ov = ''
        for i, o in enumerate(L2['overlays']):
            gx, gy, R = x0 + o['center'][0]*w, y0 + o['center'][1]*asc, o['radius']*size
            out_defs += (f'<radialGradient id="o{uid}{i}" gradientUnits="userSpaceOnUse" cx="{gx:.2f}" cy="{gy:.2f}" r="{R:.2f}">'
                         f'<stop offset="0" stop-color="{o["color"]}" stop-opacity="{o["opacity"]}"/><stop offset="1" stop-color="{o["color"]}" stop-opacity="0"/></radialGradient>')
            ov += f'<rect x="{x0-soft-R:.2f}" y="{y0-soft-R:.2f}" width="{w+2*soft+2*R:.2f}" height="{asc+2*soft+2*R:.2f}" fill="url(#o{uid}{i})"/>'
        body += f'<g mask="url(#m{uid})">{ov}</g>'
    else:
        body += f'<path d="{d}" fill="{ink}" stroke="{ink}" stroke-width="{soft:.2f}" stroke-linejoin="round"/>'
    E = T['talli']['eyes']; r = E['radius']*size; gap = E['gap']*size
    ecx = cx_c + E['offset_x']*size + eye[0]*size*0.06
    ecy = cy_c - (asc/2 + E['xheight_pad']*size) - E['lift_above_xheight']*size + eye[1]*size*0.045
    body += ''.join(f'<circle cx="{ecx+k*gap/2:.2f}" cy="{ecy:.2f}" r="{r:.2f}" fill="{pink}"/>' for k in (-1, 1))
    return out_defs, body

def standalone(material, ink, pink, name):
    size = 400; ds, bd = talli_group(size, 250, 290, 'a', material, ink, pink)
    write(name, f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" role="img" aria-label="tälli"><defs>{ds}</defs>{bd}</svg>\n')

# ---------- app icon: peek ----------
def icon(squircle=True):
    S = 1024; I = T['app_icon']; g = T['talli']['ground_night']
    stops = ''.join(f'<stop offset="{st["at"]}" stop-color="{st["color"]}"/>' for st in g['stops'])
    ds, bd = talli_group(I['talli']['font_size']*S, I['talli']['center'][0]*S, I['talli']['center'][1]*S, 'i', True, pink=C['dark']['pink']['value'], eye=tuple(I['talli']['eyes_look']))
    clip_open = f'<clipPath id="sq"><rect width="{S}" height="{S}" rx="{S*0.225:.1f}"/></clipPath>' if squircle else ''
    g_open = '<g clip-path="url(#sq)">' if squircle else '<g>'
    edge = f'<rect x=".5" y=".5" width="{S-1}" height="{S-1}" rx="{S*0.225:.1f}" fill="none" stroke="#FFFFFF" stroke-opacity="{I["edge"]["opacity"]}" stroke-width="{S/256}"/>' if squircle else ''
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" role="img" aria-label="tällmi app icon"><defs>'
           f'<radialGradient id="ground" gradientUnits="userSpaceOnUse" cx="{S*.5}" cy="{S*.5}" fx="{S*g["center"][0]}" fy="{S*g["center"][1]}" r="{S*g["radius"]}">{stops}</radialGradient>'
           f'<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C8D6FF" stop-opacity=".10"/><stop offset=".5" stop-color="#C8D6FF" stop-opacity="0"/></linearGradient>'
           f'{clip_open}{ds}</defs>{g_open}<rect width="{S}" height="{S}" fill="url(#ground)"/><rect width="{S}" height="{S}" fill="url(#sheen)"/>{bd}</g>{edge}</svg>\n')
    write('icon/app-icon.svg' if squircle else 'icon/app-icon-fullbleed.svg', svg)

lt, dk = C['light'], C['dark']
write('logo/wordmark-light.svg', wordmark(lt['ink']['value'], lt['pink']['value']))
write('logo/wordmark-dark.svg',  wordmark(dk['ink']['value'], dk['pink']['value']))
standalone(False, lt['ink']['value'], lt['pink']['value'], 'logo/mark-light.svg')
standalone(False, dk['ink']['value'], dk['pink']['value'], 'logo/mark-dark.svg')
standalone(True, None, dk['pink']['value'], 'logo/talli.svg')
icon(True); icon(False)
