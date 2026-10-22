// tälli on the web. The painter and the behaviour come from docs/brand/prototype.html,
// every number from docs/brand/tokens.json (lighting L2, entrances A1 rise and A2 roll in).
// One requestAnimationFrame loop draws every tälli that is on screen.
(() => {
  const FD = '"Funnel Display", system-ui, sans-serif';
  const DPR = Math.min(2, window.devicePixelRatio || 1);
  const BODY = [['#6F8FE2', 0], ['#5479DC', .22], ['#3B65D6', .48], ['#2F58C9', .72], ['#2D54C2', .88], ['#3460CC', 1]];
  const OVER = [{ x: .26, y: .14, r: .5, rgb: '190,206,245', a: .12 }, { x: .9, y: 1.02, r: .55, rgb: '122,156,255', a: .2 }];
  const GROUND = [['#1B2B66', 0], ['#111D4A', .45], ['#0A1230', .8], ['#060B1F', 1]];
  const PINK = { light: '#F0397C', dark: '#FF6A9C' };
  const RM = matchMedia('(prefers-reduced-motion: reduce)');

  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const ease = t => 1 - Math.exp(-t);
  function bez([x1, y1, x2, y2]) {
    return t => { let a = 0, b = 1, u = t; for (let i = 0; i < 22; i++) { u = (a + b) / 2; const x = 3 * (1 - u) ** 2 * u * x1 + 3 * (1 - u) * u * u * x2 + u ** 3; if (x < t) a = u; else b = u; } return 3 * (1 - u) ** 2 * u * y1 + 3 * (1 - u) * u * u * y2 + u ** 3; };
  }
  const E = { soft: bez([.33, 0, .2, 1]), enter: bez([.16, 1, .3, 1]), exit: bez([.4, 0, 1, 1]) };
  // one soft overshoot: damping 0.72 is about 4 %, then still
  function spring(t, resp, z) { if (t <= 0) return 0; const w = 2 * Math.PI / resp, wd = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + z / Math.sqrt(1 - z * z) * Math.sin(wd * t)); }
  // a stand-in voice when nothing real is listening
  const fakeVoice = t => { if (t % 7 > 4.6) return 0; const s = Math.max(0, Math.sin(t * 9.3) * .6 + Math.sin(t * 4.1) * .5 + Math.sin(t * 15.7) * .25); return Math.min(1, s * (.7 + .3 * Math.sin(t * .9))); };
  const isDark = () => { const t = document.documentElement.dataset.theme; return t === 'dark' || (!t && matchMedia('(prefers-color-scheme: dark)').matches); };

  const ENTER = {
    rise: { dur: .85, pose: (t, GS) => { const s = spring(t, .46, .72); return { alpha: clamp(t / .12), sc: .62 + .38 * s, dy: GS * .16 * (1 - s), lid: t < .22 ? 1 : 1 - E.soft(clamp((t - .22) / .16)) }; } },
    roll: { dur: 1.1, pose: (t, GS) => { const s = spring(t, .62, .78); return { alpha: clamp(t / .15), sc: .86 + .14 * s, dx: -GS * 1.1 * (1 - s), rot: -1.15 * (1 - s), lid: t < .45 ? 1 : 1 - E.soft(clamp((t - .45) / .16)), eye: t < .62 ? { x: .9, y: 0 } : null }; } },
  };
  const EXIT = (t, GS) => { const p = E.exit(clamp((t - .08) / .2)); return { alpha: 1 - p, sc: 1 - .18 * p, dy: GS * .08 * p, lid: clamp(t / .08) }; };

  // the Mac's clock only: livelier in the morning, sleepier at night
  function dayFeel(hour) {
    const h = hour ?? (new Date().getHours() + new Date().getMinutes() / 60);
    const d = Math.min(Math.abs(h - 3), 24 - Math.abs(h - 3));
    return { sleepy: clamp((5.5 - d) / 3.5), morning: Math.max(0, 1 - Math.abs(h - 8) / 2.5) };
  }

  // the pointer, shared by every tälli on the page
  const P = { x: -1e4, y: -1e4, moved: -1e4, speed: 0, has: false };
  let lastPE = null;
  addEventListener('pointermove', e => {
    const now = performance.now() / 1000;
    if (lastPE) { const dt = Math.max(.001, now - lastPE.t); P.speed = Math.hypot(e.clientX - lastPE.x, e.clientY - lastPE.y) / dt; }
    lastPE = { x: e.clientX, y: e.clientY, t: now };
    P.x = e.clientX; P.y = e.clientY; P.moved = now; P.has = e.pointerType === 'mouse' || e.pointerType === 'pen';
  }, { passive: true });

  const ALL = new Set();

  class Talli {
    // opts: size(w,h) → font size · center(w,h) → {x,y} · ground 'night' | null · pink 'auto' | 'night'
    //       entrance 'rise' | 'roll' · centerGroup (keep ä + letters centred) · pokeable · hour (override the clock)
    //       follow (eyes follow the pointer, default on) · look {x,y} (where the eyes rest)
    constructor(canvas, opts = {}) {
      this.c = canvas; this.o = { pink: 'auto', entrance: 'rise', pokeable: true, ...opts };
      this.layer = document.createElement('canvas'); this.lctx = this.layer.getContext('2d');
      this.mctx = document.createElement('canvas').getContext('2d');
      this.seed = Math.random() * 3;
      this.voice = null; this.lettersTarget = null; this.pos = null; this.on = {};
      const now = performance.now() / 1000;
      this.S = { state: opts.start || 'idle', t0: now, level: 0, silence: 0, eye: { x: 0, y: 0, tx: 0, ty: 0, vx: 0, vy: 0 },
        nextBlink: now + 1 + this.seed, blinkStart: -9, letters: [], nextLetter: 0, mouth: 0, browAt: null,
        drift: { x: 0, y: 0, tx: 0, ty: 0, next: 0 }, say: 0, shift: 0, prox: 0, rest: 0, pokeAt: -9, pokes: [],
        squeezeUntil: -9, startleAt: -9, dim: 0, born: now };
      this.visible = true; this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver(es => { this.visible = es[0].isIntersecting; }).observe(canvas);
      if (this.o.pokeable) {
        canvas.addEventListener('pointerdown', e => { if (this.hit(e.clientX, e.clientY)) { this.poke(); } });
        canvas.addEventListener('pointermove', e => { canvas.style.cursor = this.hit(e.clientX, e.clientY) ? 'pointer' : ''; });
      }
      ALL.add(this);
    }

    resize() {
      const r = this.c.getBoundingClientRect(); if (!r.width || !r.height) return;
      this.w = r.width; this.h = r.height;
      this.c.width = Math.round(r.width * DPR); this.c.height = Math.round(r.height * DPR);
      this.ctx = this.c.getContext('2d'); this.ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    }

    get GS() { return this.o.size ? this.o.size(this.w, this.h) : Math.min(this.w, this.h) * .5; }
    center() { if (this.pos) return this.pos; return this.o.center ? this.o.center(this.w, this.h) : { x: this.w / 2, y: this.h * .56 }; }

    set(state, extra = {}) {
      const S = this.S, now = performance.now() / 1000;
      if (S.state === 'thinking' && state !== 'thinking' && this.lettersTarget == null) S.letters.forEach(l => l.out = l.out || now);
      S.state = state; S.t0 = now; S.say = 0; S.sayAt = S.endAt = S.blinkAt = null;
      if (state === 'appear') S.entrance = extra.entrance || this.o.entrance;
      if (state === 'thinking') S.nextLetter = now + 1;
      if (state === 'saving') { S.settle = now; S.blinkAt = now + .18; S.sayAt = now + .32; S.endAt = extra.stay ? null : now + 1.9; }
      if (state === 'idle') this.on.idle && this.on.idle();
      return this;
    }
    say(open) { this.S.say = open ? 1 : 0; }

    hit(x, y) {
      if (this.S.state === 'gone') return false;
      const r = this.c.getBoundingClientRect(), c = this.center(), GS = this.GS;
      return Math.hypot(x - r.left - c.x - this.S.shift, y - r.top - c.y + GS * .1) < GS * .62;
    }
    poke() {
      const S = this.S, now = performance.now() / 1000;
      if (RM.matches) { S.dim = now; return; }
      S.pokeAt = now; S.pokes = S.pokes.filter(t => now - t < 1.6); S.pokes.push(now);
      if (S.pokes.length >= 3) { S.squeezeUntil = now + 1.1; S.pokes = []; }
      P.moved = now; S.rest = 0;
    }

    step(dt, now) {
      const S = this.S, rm = RM.matches, GS = this.GS, el = now - S.t0;
      const { sleepy: sl, morning: mo } = dayFeel(this.o.hour);
      if (S.state === 'gone') return null;
      let pose = { alpha: 1, sc: 1 };
      if (S.state === 'appear') {
        const A = ENTER[S.entrance] || ENTER.rise;
        pose = rm ? { alpha: clamp(el / .26), sc: 1 } : A.pose(el, GS);
        if (el >= (rm ? .26 : A.dur)) this.set(this.afterAppear || 'idle');
      } else if (S.state === 'hide') {
        pose = rm ? { alpha: 1 - clamp(el / .2), sc: 1 } : EXIT(el, GS);
        if (el > .32) { S.state = 'gone'; this.on.gone && this.on.gone(); return null; }
      }

      // voice: swell with it, pause when it stops (the "äh")
      const listening = S.state === 'listening';
      const v = typeof this.voice === 'function' ? this.voice(now) : this.voice;
      const target = listening ? (v != null ? v : fakeVoice(now + this.seed)) : 0;
      S.level += (target - S.level) * (target > S.level ? ease(dt / .08) : ease(dt / .26));
      S.silence = listening ? (target < .05 ? S.silence + dt : 0) : 0;
      const pausing = listening && S.silence > .7;

      // attention: where is the pointer, relative to tälli's centre
      const r = this.c.getBoundingClientRect(), c = this.center();
      const dx = P.x - (r.left + c.x + S.shift), dy = P.y - (r.top + c.y - GS * .2), dist = Math.hypot(dx, dy);
      const since = now - P.moved, following = this.o.follow !== false && P.has && since < 6 && !rm;
      if (following && P.speed > 1400 && dist < 320 && now - S.startleAt > 1.5) S.startleAt = now;
      S.prox += ((following ? clamp((320 - dist) / (320 - 110)) : 0) - S.prox) * ease(dt / .25);
      const restT = !rm && S.state === 'idle' && since > 9 && now - S.born > 9 ? 1 : 0;
      S.rest += (restT - S.rest) * ease(dt / (restT > S.rest ? 1.2 : .2));

      const ey = S.eye, look = this.o.look || { x: 0, y: 0 }; ey.tx = look.x; ey.ty = look.y + .35 * S.rest;
      const squeezing = now < S.squeezeUntil;
      if (following && !pausing && S.state !== 'thinking') {
        const k = Math.min(1, dist / 170) * 1.7 / Math.max(dist, 1);
        ey.tx = clamp(dx * k, -1.7, 1.7); ey.ty = clamp(dy * k, -1.2, 1.2);
      }
      if (S.state === 'thinking') { ey.tx = .9 + .5 * Math.sin(now * .7); ey.ty = -.9; }
      if (pausing) {
        const d = S.drift; if (now > d.next) { d.tx = (Math.random() * 2 - 1) * .7; d.ty = (Math.random() * 2 - 1) * .45; d.next = now + 1.6 + Math.random() * 1.4; }
        d.x += (d.tx - d.x) * ease(dt / .9); d.y += (d.ty - d.y) * ease(dt / .9); ey.tx = d.x; ey.ty = d.y;
      }
      if (squeezing) { ey.tx = (dx > 0 ? -1 : 1) * .6; ey.ty = .2; }
      if (pose.eye) { ey.tx = pose.eye.x; ey.ty = pose.eye.y; }
      if (rm) { const keep = S.state === 'thinking' || pausing; ey.x = keep ? ey.tx : 0; ey.y = keep ? ey.ty : 0; ey.vx = ey.vy = 0; }
      else {
        const w = 2 * Math.PI / (following ? .45 : .72);
        ['x', 'y'].forEach(a => { const f = -w * w * (ey[a] - ey['t' + a]) - 2 * w * ey['v' + a]; ey['v' + a] += f * dt; ey[a] += ey['v' + a] * dt; });
      }

      // lids
      let lid = 0; const bd = .17 * (1 + .9 * sl);
      if (S.state === 'saving' && S.blinkAt && now > S.blinkAt) { if (!rm) S.blinkStart = now; S.blinkAt = null; }
      if (S.state === 'saving' && S.sayAt && now > S.sayAt) { S.say = 1; S.sayAt = null; this.on.say && this.on.say(true); }
      if (S.state === 'saving' && S.endAt && now > S.endAt) { S.endAt = null; this.on.say && this.on.say(false); this.set('hide'); }
      if (!rm) {
        if (['idle', 'listening', 'thinking'].includes(S.state) && now > S.nextBlink) { S.blinkStart = now; S.nextBlink = now + (2.8 + Math.random() * 4) * (1 - .3 * mo); }
        const p = (now - S.blinkStart) / bd; if (p >= 0 && p < 1) lid = Math.sin(Math.PI * p);
        lid = Math.max(lid, .45 * sl * (S.state === 'idle' ? 1 : .4), .55 * S.rest);
        if (now - S.pokeAt < .22) lid = 1;
        if (squeezing) lid = Math.max(lid, .85);
      }
      if (pose.lid != null) lid = Math.max(lid, pose.lid);

      // the rare raised brow while thinking
      let brow = 0;
      if (S.state === 'thinking' && !rm) { if (!S.browAt) S.browAt = now + 2.5 + Math.random() * 3; const p = (now - S.browAt) / .9; if (p >= 0 && p < 1) brow = Math.sin(Math.PI * p); else if (p >= 1) S.browAt = null; } else S.browAt = null;
      S.mouth += ((S.say ? 1 : 0) - S.mouth) * ease(dt / .12);

      // the thinking letters: äh → ähh → ähm → ähmmm
      const live = S.letters.filter(l => !l.out);
      if (this.lettersTarget != null) {
        const want = this.lettersTarget; let i = 0;
        while (i < live.length && i < want.length && live[i].ch === want[i]) i++;
        live.slice(i).forEach(l => l.out = now);
        for (let j = i; j < want.length; j++) S.letters.push({ ch: want[j], t: now + (j - i) * .12 });
      } else if (S.state === 'thinking' && now > S.nextLetter && live.length < 6) {
        const n = live.length, hasM = live.some(l => l.ch === 'm');
        S.letters.push({ ch: n === 0 ? 'h' : hasM ? 'm' : (n < 3 && Math.random() < .5 ? 'h' : 'm'), t: now });
        S.nextLetter = now + .7 + Math.random() * .9;
      }
      S.letters = S.letters.filter(l => !(l.out && now - l.out > .4));
      const letters = S.letters.map(l => { let a = E.enter(clamp((now - l.t) / .22)); if (l.out) a *= 1 - Math.min(1, (now - l.out) / .4); if (rm) a = l.out ? 0 : (now >= l.t ? 1 : 0); return { ch: l.ch, a }; });

      // body
      const period = 4.5 * (1 + .45 * sl - .15 * mo) * (1 + .5 * S.rest);
      const breath = rm ? 0 : .022 * Math.sin((now + this.seed) * 2 * Math.PI / period);
      const swell = rm ? 0 : .1 * S.level;
      let settle = 0; if (S.state === 'saving' && !rm) settle = -.03 * Math.sin(Math.PI * E.soft(Math.min(1, (now - S.settle) / .32)));
      const st = now - S.startleAt, startle = !rm && st < .45 ? Math.sin(Math.PI * st / .45) : 0;
      let kx = pose.kx || 1, ky = pose.ky || 1, hop = 0;
      const pt = now - S.pokeAt;
      if (!rm && pt < 1.4) { const e = Math.exp(-pt * 5) * Math.cos(2 * Math.PI * 2.7 * pt); kx *= 1 + .16 * e; ky *= 1 - .2 * e; if (pt < .36) hop = GS * .14 * Math.sin(Math.PI * pt / .36); }
      if (squeezing && !rm) { kx *= 1.04; ky *= .96; }
      const lean = following && S.state !== 'thinking' ? clamp(ey.x / 1.7, -1, 1) : 0;
      return {
        sc: (1 + breath + swell + settle + .1 * S.prox) * (pose.sc ?? 1), sy: 1 - .012 * S.level,
        alpha: pose.alpha ?? 1, dx: (pose.dx || 0) + GS * .07 * lean * .5, dy: (pose.dy || 0) - hop - GS * .06 * startle,
        rot: (pose.rot || 0) + .09 * lean * .5, kx, ky, eye: { x: ey.x, y: ey.y }, lid, brow, mouth: S.mouth, letters,
        dotScale: 1 + (rm ? 0 : .28 * S.level + .35 * S.prox + .3 * startle),
        dotAlpha: rm ? (listening ? .55 + .45 * S.level : 1) * (now - S.dim < .3 ? .55 : 1) : 1,
        bob: pausing && !rm ? [2 * Math.sin(now * 1.3), 2 * Math.sin(now * 1.3 + 1)] : null,
      };
    }

    paint(o) {
      const ctx = this.ctx, GS = this.GS, sc = o.sc, mctx = this.mctx, lctx = this.lctx, layer = this.layer;
      mctx.font = `700 ${GS}px ${FD}`; const m = mctx.measureText('a');
      const gw = m.actualBoundingBoxRight + m.actualBoundingBoxLeft, asc = m.actualBoundingBoxAscent;
      const LS = GS * .62; mctx.font = `700 ${LS}px ${FD}`;
      const lets = o.letters.map(l => ({ ...l, w: mctx.measureText(l.ch).width })); const LW = lets.reduce((n, l) => n + l.w * l.a, 0);
      const pad = GS * .12, w = pad + gw + GS * .05 + LW + pad * 2 + LS * .2, h = asc + pad * 2;
      const px = Math.ceil(w * DPR * sc), py = Math.ceil(h * DPR * sc);
      if (layer.width < px || layer.height < py) { layer.width = Math.max(px, layer.width); layer.height = Math.max(py, layer.height); }
      lctx.setTransform(1, 0, 0, 1, 0, 0); lctx.globalCompositeOperation = 'source-over'; lctx.globalAlpha = 1; lctx.clearRect(0, 0, layer.width, layer.height);
      lctx.setTransform(DPR * sc, 0, 0, DPR * sc, 0, 0);
      const base = pad + asc;
      const b = softGlyph(lctx, 'a', pad + m.actualBoundingBoxLeft, base, GS);
      let lx = pad + gw + GS * .05;
      lets.forEach(l => { lctx.globalAlpha = l.a; softGlyph(lctx, l.ch, lx - (RM.matches ? 0 : (1 - l.a) * l.w * .6), base, LS); lx += l.w * l.a; });
      lctx.globalAlpha = 1; lctx.globalCompositeOperation = 'source-atop';
      OVER.forEach(v => { const X = b.x + b.w * v.x, Y = b.y + b.h * v.y, R = GS * v.r; const g = lctx.createRadialGradient(X, Y, 0, X, Y, R); g.addColorStop(0, `rgba(${v.rgb},${v.a})`); g.addColorStop(1, `rgba(${v.rgb},0)`); lctx.fillStyle = g; lctx.fillRect(0, 0, w, h); });
      if (o.mouth > .02) {
        lctx.globalCompositeOperation = 'destination-out'; lctx.globalAlpha = o.mouth; lctx.beginPath();
        lctx.ellipse(pad + gw * .43, base - asc * .27, gw * .15 * (1 + .2 * o.mouth), asc * .1 * (1 + .9 * o.mouth), 0, 0, Math.PI * 2); lctx.fill(); lctx.globalAlpha = 1;
      }
      lctx.globalCompositeOperation = 'source-over';

      // keep the ä and its letters centred as a group, if asked
      if (this.o.centerGroup) this.S.shift += (-LW * sc / 2 - this.S.shift) * (RM.matches ? 1 : .08); else this.S.shift = 0;
      const c = this.center();
      ctx.save();
      ctx.translate(c.x + this.S.shift + o.dx, c.y + o.dy + (1 - o.ky) * asc * sc * .5);
      ctx.rotate(o.rot); ctx.scale(o.kx, o.ky * o.sy); ctx.globalAlpha = o.alpha;
      ctx.drawImage(layer, 0, 0, px, py, -(pad + gw / 2) * sc, -(pad + asc / 2) * sc, px / DPR, py / DPR);
      const e = o.eye, rr = GS * .068 * sc * o.dotScale, top = -(asc / 2 + GS * .035) * sc - GS * .16 * sc;
      ctx.globalAlpha = o.alpha * o.dotAlpha;
      ctx.fillStyle = this.o.pink === 'night' || isDark() ? PINK.dark : PINK.light;
      [-1, 1].forEach((s, i) => {
        const x = (-GS * .015 + s * GS * .27 / 2) * sc + e.x * GS * .06 * sc, y = top + e.y * GS * .045 * sc + (o.bob ? o.bob[i] * sc : 0);
        if (o.brow > .01 && i === 0) {
          ctx.save(); ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = rr * 2 * (1 - .35 * o.brow); ctx.lineCap = 'round'; ctx.beginPath();
          ctx.arc(x, y + rr * 2.2 * o.brow, rr * 2.6 * o.brow + .01, Math.PI * (1.5 - .22 * o.brow), Math.PI * (1.5 + .22 * o.brow)); ctx.stroke(); ctx.restore(); return;
        }
        ctx.beginPath(); ctx.ellipse(x, y, rr, Math.max(.6, rr * (1 - o.lid)), 0, 0, Math.PI * 2); ctx.fill();
      });
      ctx.restore();
    }

    frame(dt, now) {
      // off screen, tälli rests; an entrance, a save or an exit still runs to its end
      if (!this.ctx || (!this.visible && !['appear', 'saving', 'hide'].includes(this.S.state))) return;
      const pose = this.step(dt, now);
      if (!this.visible) return;
      this.ctx.clearRect(0, 0, this.w, this.h);
      if (this.o.ground === 'night') nightGround(this.ctx, this.w, this.h);
      if (pose) this.paint(pose);
    }
  }

  function softGlyph(c, ch, x, base, size) {
    c.font = `700 ${size}px ${FD}`; const m = c.measureText(ch);
    const b = { x: x - m.actualBoundingBoxLeft, y: base - m.actualBoundingBoxAscent, w: m.actualBoundingBoxRight + m.actualBoundingBoxLeft, h: m.actualBoundingBoxAscent };
    const g = c.createLinearGradient(b.x, b.y, b.x + b.w * .55, b.y + b.h * 1.05); BODY.forEach(([k, o]) => g.addColorStop(o, k));
    c.fillStyle = g; c.strokeStyle = g; c.lineWidth = size * .07; c.lineJoin = 'round'; c.strokeText(ch, x, base); c.fillText(ch, x, base);
    return b;
  }
  function nightGround(ctx, w, h) {
    const g = ctx.createRadialGradient(w * .5, h * .36, 0, w * .5, h * .5, Math.max(w, h) * .85);
    GROUND.forEach(([c, o]) => g.addColorStop(o, c)); ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }

  let last = performance.now() / 1000;
  function loop() {
    const now = performance.now() / 1000, dt = Math.min(.05, now - last); last = now;
    ALL.forEach(t => t.frame(dt, now));
    requestAnimationFrame(loop);
  }

  window.Talli = Talli;
  window.TalliKit = { E, clamp, dayFeel, reduceMotion: RM, ready: document.fonts.load(`700 100px ${FD}`).then(() => { requestAnimationFrame(loop); }) };
})();
