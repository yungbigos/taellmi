// Direction C: a field of words from thoughts, in depth. Sharp near the focus plane, fading and
// blurring far away (brand book: space view). Plain 2D canvas for the study; a real build would use WebGL.
(() => {
  const RM = matchMedia('(prefers-reduced-motion: reduce)');
  const DPR = Math.min(2, window.devicePixelRatio || 1);
  const isDark = () => { const t = document.documentElement.dataset.theme; return t === 'dark' || (!t && matchMedia('(prefers-color-scheme: dark)').matches); };
  const COL = () => isDark() ? { ink: '#E7ECF8', quiet: '#98A3C3', blue: '#7398FF', paper: '#0A1230' } : { ink: '#0C1638', quiet: '#586282', blue: '#2852D2', paper: '#FFFFFF' };
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
  const ease = t => 1 - Math.exp(-t);
  const enter = t => 1 - Math.pow(1 - clamp(t), 3);
  const RASTER = 64, BLUR = [0, 2, 5];
  const canFilter = 'filter' in CanvasRenderingContext2D.prototype;

  // words people say into a journal; groups make the search work
  const WORDS = [
    ['äh', 'aeh', 'aeh'], ['ähm', 'aeh', 'aeh'], ['äh', 'aeh', 'aeh'], ['hmm', 'aeh', 'aeh'], ['ähm', 'aeh', 'aeh'], ['äh', 'aeh', 'aeh'],
    ['the move', 'w', 'moving'], ['boxes', 'w', 'moving'], ['the old flat', 'w', 'moving'], ['landlord', 'w', 'moving'], ['March', 'w', 'moving'], ['Sam', 'w', 'moving'],
    ['Kai', 'w', 'kai'], ['the pitch', 'w', 'kai'], ['gut feeling', 'w', 'kai'], ['follow up tomorrow', 'w', 'kai'], ['deadline', 'w', 'kai'], ['not convinced', 'w', 'kai'],
    ['dreamt', 'w', 'dream'], ['a lake in the kitchen', 'w', 'dream'], ['the sea', 'w', 'dream'], ['weird', 'w', 'dream'], ['flying again', 'w', 'dream'],
    ['I think', 'w', ''], ['somehow', 'w', ''], ['maybe', 'w', ''], ['grandma', 'w', ''], ['going for a run', 'w', ''], ['tired', 'w', ''], ['finally', 'w', ''],
    ['dentist', 'w', ''], ['call mum', 'w', ''], ['Sunday', 'w', ''], ['coffee', 'w', ''], ['Lisbon', 'w', ''], ['patience', 'w', ''], ['too much', 'w', ''],
    ['guitar', 'w', ''], ['why, really', 'w', ''], ['the bike', 'w', ''], ['calm', 'w', ''], ['excited', 'w', ''], ['don’t forget', 'w', ''], ['Friday', 'w', ''],
  ];

  const P = { x: 0, y: 0, has: false };
  addEventListener('pointermove', e => { P.x = e.clientX; P.y = e.clientY; P.has = e.pointerType === 'mouse'; }, { passive: true });

  const ALL = new Set();
  const sprites = new Map();
  function sprite(text, color, blur) {
    const key = text + '|' + color + '|' + blur;
    let s = sprites.get(key); if (s) return s;
    const m = document.createElement('canvas').getContext('2d');
    const font = `450 ${RASTER}px "Funnel Sans", system-ui, sans-serif`; m.font = font;
    const pad = 10 + blur * 3, tw = Math.ceil(m.measureText(text).width);
    const c = document.createElement('canvas'); c.width = tw + pad * 2; c.height = Math.ceil(RASTER * 1.35) + pad * 2;
    const x = c.getContext('2d'); x.font = font; x.fillStyle = color; x.textBaseline = 'middle'; x.textAlign = 'center';
    if (blur && canFilter) x.filter = `blur(${blur}px)`;
    x.fillText(text, c.width / 2, c.height / 2);
    s = { c, w: c.width, h: c.height }; sprites.set(key, s); return s;
  }

  class WordField {
    // opts: count · depth (world units) · drift (units/s) · scroll (element whose scroll drives the camera)
    //       size (word size at the focus plane) · clear {rx, ry, y} (a calm zone behind a headline)
    constructor(canvas, opts = {}) {
      this.c = canvas; this.o = { count: 70, depth: 2200, drift: 34, spreadX: 1100, spreadY: 640, size: 38, ...opts };
      this.cam = { x: 0, y: 0, z: 0 }; this.active = ''; this.hlAny = 0; this.end = 0; this.phrase = null;
      this.parts = [];
      for (let i = 0; i < this.o.count; i++) this.add(WORDS[i % WORDS.length], Math.random() * this.o.depth);
      this.visible = true; this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver(es => { this.visible = es[0].isIntersecting; }).observe(canvas);
      ALL.add(this);
    }
    add([text, kind, group], z) {
      const p = { text, kind, group, x: (Math.random() * 2 - 1) * this.o.spreadX, y: (Math.random() * 2 - 1) * this.o.spreadY, z, hl: 0, hidden: 0 };
      // keep the middle a little clearer, where the headline sits
      if (Math.abs(p.x) < this.o.spreadX * .25 && Math.abs(p.y) < this.o.spreadY * .2) p.y += Math.sign(p.y || 1) * this.o.spreadY * .25;
      this.parts.push(p); return p;
    }
    resize() {
      const r = this.c.getBoundingClientRect(); if (!r.width) return;
      this.w = r.width; this.h = r.height; this.c.width = Math.round(r.width * DPR); this.c.height = Math.round(r.height * DPR);
      this.ctx = this.c.getContext('2d'); this.ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
      this.focal = Math.max(this.w, this.h * 1.2) * .62;
    }
    find(group) {
      this.active = group || '';
      const seen = new Set();
      // one of each word comes forward; the duplicates fade with the rest
      const hits = this.parts.filter(p => this.active && p.group === this.active && !seen.has(p.text) && seen.add(p.text));
      this.parts.forEach(p => { p.lead = hits.includes(p); });
      hits.forEach((p, i) => { const a = -Math.PI / 2 + (i + .5) / hits.length * Math.PI * 2; p.pull = { ax: Math.cos(a), ay: Math.sin(a) }; });
    }
    // a spoken thought appears in front, word by word, then joins the field
    say(words) { this.phrase = { words, t0: performance.now() / 1000, items: null }; }

    project(p) {
      const D = this.o.depth, near = 60;
      const rel = ((p.z - this.cam.z) % D + D) % D + near;
      const f = this.focal / rel;
      return { rel, f, x: this.w / 2 + (p.x - this.cam.x) * f, y: this.h / 2 + (p.y - this.cam.y) * f };
    }

    frame(dt, now) {
      if (!this.ctx || !this.visible) return;
      const rm = RM.matches, ctx = this.ctx, w = this.w, h = this.h, col = COL();
      if (this.o.scroll) {
        const s = this.o.scroll, prog = clamp(s.scrollTop / Math.max(1, s.scrollHeight - s.clientHeight));
        this.cam.z += (prog * this.o.depth * 1.3 - this.cam.z) * (rm ? 1 : ease(dt / .18));
        this.end = smooth(.78, .98, prog);
      } else if (!rm) this.cam.z += this.o.drift * dt;
      const r = this.c.getBoundingClientRect();
      const px = P.has ? clamp((P.x - r.left) / w * 2 - 1, -1.5, 1.5) : 0, py = P.has ? clamp((P.y - r.top) / h * 2 - 1, -1.5, 1.5) : 0;
      if (!rm) { this.cam.x += (px * 70 - this.cam.x) * ease(dt / .6); this.cam.y += (py * 45 - this.cam.y) * ease(dt / .6); }
      this.hlAny += ((this.active ? 1 : 0) - this.hlAny) * (rm ? 1 : ease(dt / .35));
      ctx.clearRect(0, 0, w, h);

      const D = this.o.depth, focusRel = this.focal, unit = clamp(w / 1000, .62, 1.4), clr = this.o.clear;
      const items = this.parts.map(p => {
        p.hl += ((this.active && p.lead ? 1 : 0) - p.hl) * (rm ? 1 : ease(dt / .4));
        return { p, q: this.project(p) };
      }).sort((a, b) => b.q.rel - a.q.rel);

      for (const { p, q } of items) {
        if (now < p.hidden) continue;
        let alpha = smooth(70, 260, q.rel) * (1 - smooth(D * .55, D * .98, q.rel));
        alpha *= 1 - .8 * this.hlAny * (1 - p.hl);
        alpha *= 1 - this.end;
        let x = q.x, y = q.y, size = this.o.size * q.f * unit;
        // keep a calm zone behind the headline
        if (clr) { const ex = (x - w / 2) / (w * clr.rx), ey = (y - h * (clr.y ?? .5)) / (h * clr.ry); alpha *= .12 + .88 * smooth(.55, 1.25, ex * ex + ey * ey); }
        const off = Math.abs(Math.log(q.rel / focusRel));
        let blur = off > 1.05 ? 2 : off > .55 ? 1 : 0;
        if (p.hl > .01 && p.pull) {
          const tx = w / 2 + p.pull.ax * w * .42, ty = h / 2 + p.pull.ay * h * .38, ts = 30 * unit + 6;
          const k = enter(p.hl);
          x += (tx - x) * k; y += (ty - y) * k; size += (ts - size) * k; alpha += (1 - alpha) * k;
          if (k > .5) blur = 0;
        }
        if (alpha < .02 || size < 3) continue;
        const color = p.hl > .5 ? col.blue : p.kind === 'aeh' ? col.quiet : col.ink;
        const s = sprite(p.text, color, BLUR[blur]);
        const k = size / RASTER;
        ctx.globalAlpha = alpha * (p.kind === 'aeh' ? .9 : 1);
        ctx.drawImage(s.c, x - s.w * k / 2, y - s.h * k / 2, s.w * k, s.h * k);
      }
      ctx.globalAlpha = 1;
      this.drawPhrase(now, col, unit);
    }

    drawPhrase(now, col, unit) {
      const ph = this.phrase; if (!ph) return;
      const ctx = this.ctx, w = this.w, h = this.h, t = now - ph.t0, rm = RM.matches;
      const size = Math.max(18, 30 * unit);
      if (!ph.items) {
        // lay the words out in centred lines, at reading size
        const m = ctx; m.font = `450 ${size}px "Funnel Sans", system-ui, sans-serif`;
        const space = m.measureText(' ').width, maxW = w * .72, lines = [[]]; let lw = 0;
        ph.words.forEach(([text, kind]) => { const ww = m.measureText(text).width; if (lw + ww > maxW && lines.at(-1).length) { lines.push([]); lw = 0; } lines.at(-1).push({ text, kind, ww }); lw += ww + space; });
        const lh = size * 1.45, top = h / 2 - (lines.length - 1) * lh / 2; ph.items = [];
        lines.forEach((ln, li) => { const tot = ln.reduce((n, x) => n + x.ww, 0) + space * (ln.length - 1); let x = w / 2 - tot / 2; ln.forEach(it => { ph.items.push({ ...it, sx: x + it.ww / 2, sy: top + li * lh }); x += it.ww + space; }); });
        ph.items.forEach((it, i) => { it.at = i * .32 + (it.kind === 'aeh' ? .5 : 0) + ph.items.slice(0, i).filter(x => x.kind === 'aeh').length * .5; });
        ph.release = ph.items.at(-1).at + 2.2;
      }
      if (t > ph.release && !ph.parts) {
        ph.parts = ph.items.map(it => { const p = this.add([it.text, it.kind, ''], this.cam.z + this.o.depth * (.25 + Math.random() * .3)); p.hidden = now + 1.6; return p; });
      }
      ph.items.forEach((it, i) => {
        let a = rm ? (t >= it.at ? 1 : 0) : enter((t - it.at) / .28), x = it.sx, y = it.sy, s = size;
        if (ph.parts) {
          const k = rm ? 1 : clamp((t - ph.release) / 1.6), e = k * k * (3 - 2 * k), q = this.project(ph.parts[i]);
          x += (q.x - x) * e; y += (q.y - y) * e; s += (this.o.size * q.f * unit - s) * e; a *= 1 - .4 * e;
          if (k >= 1) a = 0;
        }
        if (a <= .01) return;
        const sp = sprite(it.text, it.kind === 'aeh' ? col.quiet : col.ink, 0), k = s / RASTER;
        ctx.globalAlpha = a; ctx.drawImage(sp.c, x - sp.w * k / 2, y - sp.h * k / 2, sp.w * k, sp.h * k);
      });
      ctx.globalAlpha = 1;
      if (ph.parts && t > ph.release + 1.7) {
        this.phrase = null;
        if (this.parts.length > this.o.count + 30) this.parts.splice(0, this.parts.length - this.o.count);
        this.on && this.on.done && this.on.done();
      }
    }
  }

  let last = performance.now() / 1000;
  function loop() { const now = performance.now() / 1000, dt = Math.min(.05, now - last); last = now; ALL.forEach(f => f.frame(dt, now)); requestAnimationFrame(loop); }
  // sprites carry colour; drop them when the theme changes
  new MutationObserver(() => sprites.clear()).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => sprites.clear());
  document.fonts.load('450 64px "Funnel Sans"').then(() => requestAnimationFrame(loop));
  window.WordField = WordField;
})();
