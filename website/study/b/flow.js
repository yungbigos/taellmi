// Direction B's heart: a spoken thought appears word by word, flows into a cloud of earlier thoughts,
// and the cloud connects into a structure of words in depth (brand book: space view). Driven by scroll.
// Plain 2D canvas for the study; a real build would use WebGL.
(() => {
  const RM = matchMedia('(prefers-reduced-motion: reduce)');
  const DPR = Math.min(2, window.devicePixelRatio || 1);
  const COL = { ink: '#E7ECF8', quiet: '#98A3C3', blue: '#7398FF' };
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
  const ease = t => 1 - Math.exp(-t);
  const lerp = (a, b, t) => a + (b - a) * t;
  const RASTER = 64, BLUR = [0, 2, 5];
  const canFilter = 'filter' in CanvasRenderingContext2D.prototype;

  const sprites = new Map();
  function sprite(text, color, blur, display) {
    const key = text + '|' + color + '|' + blur + '|' + (display ? 1 : 0);
    let s = sprites.get(key); if (s) return s;
    const font = display ? `500 ${RASTER}px "Funnel Display", system-ui, sans-serif` : `450 ${RASTER}px "Funnel Sans", system-ui, sans-serif`;
    const m = document.createElement('canvas').getContext('2d'); m.font = font;
    const pad = 8 + blur * 3, tw = Math.ceil(m.measureText(text).width);
    const c = document.createElement('canvas'); c.width = tw + pad * 2; c.height = Math.ceil(RASTER * 1.35) + pad * 2;
    const x = c.getContext('2d'); x.font = font; x.fillStyle = color; x.textBaseline = 'middle';
    if (blur && canFilter) x.filter = `blur(${blur}px)`;
    x.fillText(text, pad, c.height / 2);
    s = { c, w: c.width, h: c.height, pad }; sprites.set(key, s); return s;
  }

  // a few weeks of thoughts: what someone keeps talking about (constellations)
  const CLUSTERS = [
    { key: 'moving', name: 'moving', words: ['move', 'Sam', 'landlord', 'boxes', 'the old flat', 'March', 'books last'] },
    { key: 'work', name: 'the pitch', words: ['Kai', 'the pitch', 'gut feeling', 'follow up tomorrow', 'deadline', 'not convinced'] },
    { key: 'dream', name: 'dreams', words: ['dreamt', 'a lake in the kitchen', 'the sea', 'flying again', 'weird'] },
    { key: 'days', name: 'days', words: ['coffee', 'going for a run', 'grandma', 'call mum', 'Sunday', 'guitar', 'Lisbon'] },
    { key: 'feel', name: 'feelings', words: ['tired', 'excited', 'calm', 'patience', 'too much', 'finally'] },
  ];
  const AEH = ['äh', 'ähm', 'hmm', 'äh', 'ähm', 'äh', 'hm'];
  const CROSS = [['Sam', 'Lisbon'], ['tired', 'deadline'], ['calm', 'the sea'], ['excited', 'the pitch'], ['grandma', 'Sunday'], ['too much', 'boxes']];
  // the thought you hear; words that name something land on their node, the rest settle around it
  const PHRASE = [['Okay,'], ['äh,', 'aeh'], ['talked'], ['to'], ['Sam', 'Sam'], ['today'], ['about'], ['the'], ['move.', 'move'],
    ['And,'], ['ähm,', 'aeh'], ['I'], ['really'], ['need'], ['to'], ['call'], ['the'], ['landlord', 'landlord'], ['before'], ['Friday.']];

  function rng(seed) { let s = seed; return () => { s = (s * 16807) % 2147483647; return (s - 1) / 2147483646; }; }

  class Flow {
    constructor(canvas, opts = {}) {
      this.c = canvas; this.o = opts; this.p = 0; this.active = ''; this.hlAny = 0;
      this.yaw = 0; this.pitch = .22; this.look = { x: 0, y: 0 }; this.spokenAt = null; this.speaking = false;
      this.build(); this.visible = true; this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver(es => { this.visible = es[0].isIntersecting; }).observe(canvas);
      addEventListener('pointermove', e => { if (e.pointerType !== 'mouse') return; this.look.x = e.clientX / innerWidth * 2 - 1; this.look.y = e.clientY / innerHeight * 2 - 1; }, { passive: true });
      const loop = () => { const now = performance.now() / 1000, dt = Math.min(.05, now - (this.last ?? now)); this.last = now; this.frame(dt, now); requestAnimationFrame(loop); };
      document.fonts.ready.then(() => requestAnimationFrame(loop));
    }

    build() {
      const r = rng(7); this.nodes = []; this.edges = [];
      const dirs = CLUSTERS.map((_, i) => { const y = 1 - (i + .5) / CLUSTERS.length * 2, rad = Math.sqrt(1 - y * y), a = i * 2.399963; return [Math.cos(a) * rad, y * .8, Math.sin(a) * rad]; });
      CLUSTERS.forEach((cl, ci) => {
        const c = dirs[ci].map(v => v * .7); cl.center = c;
        cl.words.forEach((w, wi) => {
          const p = wi === 0 ? [0, 0, 0] : [r() - .5, r() - .5, r() - .5].map(v => v * .74);
          this.nodes.push({ text: w, kind: 'concept', cluster: cl.key, x: c[0] + p[0], y: c[1] + p[1], z: c[2] + p[2], hl: 0, size: wi === 0 ? 1.15 : 1 });
        });
      });
      AEH.forEach(w => { const p = [r() - .5, r() - .5, r() - .5].map(v => v * 1.9); this.nodes.push({ text: w, kind: 'aeh', cluster: 'aeh', x: p[0], y: p[1], z: p[2], hl: 0, size: .85 }); });
      // join each word to its nearest neighbours in the same constellation
      const byName = n => this.nodes.find(x => x.text === n);
      const d2 = (a, b) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2;
      const has = (a, b) => this.edges.some(e => (e.a === a && e.b === b) || (e.a === b && e.b === a));
      const add = (a, b) => { if (a && b && a !== b && !has(a, b)) this.edges.push({ a, b, delay: r() * .55 }); };
      CLUSTERS.forEach(cl => {
        const ns = this.nodes.filter(n => n.cluster === cl.key);
        ns.forEach(n => ns.filter(m => m !== n).sort((p, q) => d2(n, p) - d2(n, q)).slice(0, 2).forEach(m => add(n, m)));
      });
      CROSS.forEach(([a, b]) => add(byName(a), byName(b)));
      add(byName('Sam'), byName('move')); add(byName('move'), byName('landlord'));

      // where each spoken word ends up
      const moving = CLUSTERS[0].center, aeh = this.nodes.filter(n => n.kind === 'aeh');
      let ai = 0;
      this.phrase = PHRASE.map(([text, to]) => {
        let node;
        if (to === 'aeh') node = aeh[ai++];
        else if (to) node = byName(to);
        else { const p = [r() - .5, r() - .5, r() - .5].map(v => v * .7); node = { text, kind: 'filler', cluster: 'moving', x: moving[0] + p[0], y: moving[1] + p[1], z: moving[2] + p[2], hl: 0, size: .72 }; this.nodes.push(node); }
        node.from = true;
        return { text, kind: to === 'aeh' ? 'aeh' : 'w', node };
      });
      let t = 0;
      this.phrase.forEach(w => { w.at = t; w.dur = .22 + w.text.length * .035; t += w.dur + .06; if (w.kind === 'aeh') t += .95; else if (/[.]$/.test(w.text)) t += .45; });
      this.phraseLen = t;
    }

    resize() {
      const r = this.c.getBoundingClientRect(); if (!r.width) return;
      this.w = r.width; this.h = r.height; this.c.width = Math.round(r.width * DPR); this.c.height = Math.round(r.height * DPR);
      this.ctx = this.c.getContext('2d'); this.ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
      this.narrow = this.w < 760; this.laid = false;
    }

    // the page tells us where we are: 0 speaking · .3 keeping · .55 connecting · .8 searching · 1
    setProgress(p) { this.p = clamp(p); }
    speak() { if (this.spokenAt == null) this.spokenAt = performance.now() / 1000; }
    find(key) { this.active = key || ''; }

    layoutPhrase() {
      const ctx = this.ctx, w = this.w, h = this.h;
      const size = this.narrow ? clamp(w * .052, 17, 22) : clamp(w * .02, 20, 30);
      ctx.font = `450 ${size}px "Funnel Sans", system-ui, sans-serif`;
      const space = ctx.measureText(' ').width, maxW = this.narrow ? w * .86 : w * .44, lines = [[]]; let lw = 0;
      this.phrase.forEach(it => { it.ww = ctx.measureText(it.text).width; if (lw + it.ww > maxW && lines.at(-1).length) { lines.push([]); lw = 0; } lines.at(-1).push(it); lw += it.ww + space; });
      const lh = size * 1.5, cx = this.narrow ? w * .07 : w * .52, cy = this.narrow ? h * .66 : h * .5, top = cy - (lines.length - 1) * lh / 2;
      lines.forEach((ln, li) => { let x = cx; ln.forEach(it => { it.sx = x; it.sy = top + li * lh; it.ss = size; x += it.ww + space; }); });
      this.laid = true;
    }

    frame(dt, now) {
      if (!this.ctx || !this.visible) return;
      if (!this.laid) this.layoutPhrase();
      const ctx = this.ctx, w = this.w, h = this.h, rm = RM.matches, p = this.p;
      const release = smooth(.27, .5, p), cloud = smooth(.32, .54, p), connect = clamp((p - .52) / .24), names = smooth(.58, .72, p);
      if (!rm) this.yaw += dt * .045;
      const targetYaw = p * 1.1 + this.look.x * .18, targetPitch = .22 + this.look.y * .08;
      this.yawS = lerp(this.yawS ?? targetYaw, targetYaw, rm ? 1 : ease(dt / .5)); this.pitchS = lerp(this.pitchS ?? targetPitch, targetPitch, rm ? 1 : ease(dt / .5));
      const yaw = this.yaw + this.yawS, pitch = this.pitchS;
      const S = Math.min(w, h * 1.3) * (this.narrow ? .4 : .32), dist = lerp(3.2, 2.35, smooth(.3, .8, p)), ref = 2.6;
      const cx = this.narrow ? w * .5 : w * .64, cy = this.narrow ? h * .74 : h * .52;
      const cyaw = Math.cos(yaw), syaw = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
      const proj = n => {
        const x1 = n.x * cyaw - n.z * syaw, z1 = n.x * syaw + n.z * cyaw;
        const y2 = n.y * cp - z1 * sp, z2 = n.y * sp + z1 * cp, zz = z2 + dist;
        return { x: cx + x1 * S * ref / zz, y: cy + y2 * S * ref / zz, z: zz, k: ref / zz };
      };
      this.hlAny += ((this.active ? 1 : 0) - this.hlAny) * (rm ? 1 : ease(dt / .35));
      this.nodes.forEach(n => { n.q = proj(n); n.hl += ((this.active && n.cluster === this.active && n.kind !== 'filler' ? 1 : 0) - n.hl) * (rm ? 1 : ease(dt / .4)); });
      const depthA = q => clamp(1.25 - (q.z - dist + 1) * .5, .22, 1);
      const base = clamp(w * .0115, 12, 17);
      ctx.clearRect(0, 0, w, h);

      // spoken words: how many have been said
      const st = this.spokenAt == null ? -1 : now - this.spokenAt;
      this.speaking = false;
      this.phrase.forEach(it => {
        if (release > 0) it.said = 1;
        else if (st < 0) it.said = 0;
        else it.said = rm ? 1 : clamp((st - it.at) / .25);
        if (!rm && release === 0 && st >= it.at && st < it.at + it.dur) this.speaking = true;
      });
      // above the spoken part (still thinking), the phrase steps aside
      const show = release > 0 ? 1 : smooth(.08, .13, p);

      // connections, drawn in softly
      ctx.lineWidth = 1;
      ctx.globalCompositeOperation = 'lighter';
      for (const e of this.edges) {
        const prog = clamp((connect - e.delay) / .45); if (prog <= 0) continue;
        const a = e.a.q, b = e.b.q, inA = this.active && e.a.cluster === this.active && e.b.cluster === this.active;
        let al = .28 * Math.min(depthA(a), depthA(b)) * cloud * (1 - .7 * this.hlAny * (inA ? 0 : 1));
        if (inA) al = Math.max(al, .75 * this.hlAny);
        ctx.strokeStyle = `rgba(115,152,255,${al})`;
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(lerp(a.x, b.x, prog), lerp(a.y, b.y, prog)); ctx.stroke();
      }
      ctx.globalCompositeOperation = 'source-over';

      // constellation names, quiet, in display type
      if (names > .01) CLUSTERS.forEach(cl => {
        const q = proj({ x: cl.center[0], y: cl.center[1] - .36, z: cl.center[2] });
        const on = this.active === cl.key;
        const s = sprite(cl.name, on ? COL.blue : COL.quiet, 0, true), size = base * 1.2 * q.k, k = size / RASTER;
        ctx.globalAlpha = names * depthA(q) * (on ? 1 : .4 * (1 - .6 * this.hlAny));
        ctx.drawImage(s.c, q.x - s.w * k / 2, q.y - s.h * k / 2, s.w * k, s.h * k);
      });

      // the words, far to near
      const sorted = [...this.nodes].sort((a, b) => b.q.z - a.q.z);
      for (const n of sorted) {
        const q = n.q; let a = depthA(q) * cloud;
        if (n.from) a = 0;   // a spoken word draws itself below until it lands
        if (a < .01) continue;
        a *= 1 - .7 * this.hlAny * (1 - n.hl);
        this.drawNode(n, q, a, base, n.hl);
      }

      // the phrase: said word by word, then each word flies to its place
      this.phrase.forEach((it, i) => {
        if (it.said <= 0) return;
        const r = clamp(release * 1.5 - i / this.phrase.length * .5), e = r * r * (3 - 2 * r), n = it.node, q = n.q;
        const dot = this.dotR(n, q, base);
        const tx = q.x + dot + 5, ty = q.y, ts = base * n.size * q.k * (n.kind === 'filler' ? .9 : 1);
        const x = lerp(it.sx, tx, e), y = lerp(it.sy, ty, e), size = lerp(it.ss, ts, e);
        if (r >= 1) { this.drawNode(n, q, depthA(q) * cloud * (1 - .7 * this.hlAny * (1 - n.hl)), base, n.hl); return; }
        const color = it.kind === 'aeh' ? COL.quiet : COL.ink, s = sprite(it.text, color, 0), k = size / RASTER;
        ctx.globalAlpha = show * (rm ? 1 : E3(it.said)) * lerp(1, depthA(q) * (n.kind === 'filler' ? .6 : 1), e);
        ctx.drawImage(s.c, x - s.pad * k, y - s.h * k / 2, s.w * k, s.h * k);
        if (e > .05) { ctx.globalAlpha *= e; ctx.fillStyle = COL.blue; ctx.beginPath(); ctx.arc(lerp(x - 6, q.x, e), lerp(y, q.y, e), dot * e, 0, Math.PI * 2); ctx.fill(); }
      });
      ctx.globalAlpha = 1;
    }

    dotR(n, q, base) { return (n.kind === 'concept' ? 2.6 : 1.8) * q.k * (1 + .6 * n.hl) * (base / 14); }
    drawNode(n, q, a, base, hl) {
      if (a < .01) return;
      const ctx = this.ctx, blur = RM.matches ? 0 : q.z > 3.1 ? 2 : q.z > 2.7 ? 1 : 0;
      const color = hl > .5 ? COL.blue : n.kind === 'concept' ? COL.ink : COL.quiet;
      const size = base * n.size * q.k * (1 + .25 * hl), s = sprite(n.text, color, BLUR[blur]), k = size / RASTER, dot = this.dotR(n, q, base);
      ctx.globalAlpha = a * (n.kind === 'filler' ? .6 : n.kind === 'aeh' ? .8 : 1);
      ctx.drawImage(s.c, q.x + dot + 5 - s.pad * k, q.y - s.h * k / 2, s.w * k, s.h * k);
      if (n.kind !== 'aeh') { ctx.globalAlpha = a * (.55 + .45 * hl); ctx.fillStyle = COL.blue; ctx.beginPath(); ctx.arc(q.x, q.y, dot, 0, Math.PI * 2); ctx.fill(); }
    }
  }
  const E3 = t => 1 - Math.pow(1 - clamp(t), 3);
  window.Flow = Flow;
})();
