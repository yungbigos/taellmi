// direction B as a page: tälli peeks in the hero, the thought flows into space, tälli sits locked in a cage by privacy and peeks once more.
(() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const RM = TalliKit.reduceMotion;

  // ---------- this page, counted ----------
  function counts() {
    const req = performance.getEntriesByType('resource').filter(e => { try { const u = new URL(e.name, location.href); return /^https?:$/.test(u.protocol) && u.host !== location.host; } catch { return false; } }).length;
    let store = 0; try { store = localStorage.length + sessionStorage.length; } catch { /* storage blocked counts as none */ }
    const v = { cookies: document.cookie ? document.cookie.split(';').filter(s => s.trim()).length : 0, req, store };
    $$('[data-count]').forEach(el => { el.textContent = v[el.dataset.count]; });
  }
  counts();
  try { new PerformanceObserver(counts).observe({ type: 'resource', buffered: true }); } catch { setInterval(counts, 5000); }

  TalliKit.ready.then(() => { hero(); flow(); cage(); foot(); });

  // ---------- 1 · tälli peeks; click it and it rises ----------
  function hero() {
    const H = { rise: 0, riseT: 0 }, invite = $('#invite'), cv = $('#peek');
    const size = (w, h) => Math.min(h * .5, w * .42, 440);
    const center = (w, h) => { const GS = size(w, h); return { x: w / 2, y: h + GS * (w < 560 ? -.1 : .03) - H.rise * GS * .34 }; };
    const t = new Talli(cv, { size, center, pink: 'night', look: { x: .3, y: -.55 }, start: 'gone' });
    t.afterAppear = 'idle'; t.set('appear', { entrance: 'rise' });
    cv.addEventListener('pointerdown', e => { if (t.hit(e.clientX, e.clientY)) H.riseT = H.riseT ? 0 : 1; });
    (function tick() {
      H.rise += (H.riseT - H.rise) * (RM.matches ? 1 : .1);
      const r = cv.getBoundingClientRect(), GS = size(r.width, r.height), c = center(r.width, r.height);
      invite.style.bottom = (r.height - c.y + GS * .72) + 'px';
      invite.classList.toggle('on', H.rise > .7);
      requestAnimationFrame(tick);
    })();
  }

  // ---------- 2 · think → speak → keep → connect → find ----------
  function flow() {
    const sec = $('#idea'), steps = $$('.step'), cue = $('#cue'), q = $('#q'), found = $('#found');
    const f = new Flow($('#flow'));
    // tälli: big while it thinks, small beside the words while it listens
    let pose = 0, want = null, picked = false;
    const think = (w, h) => w < 760 ? { s: Math.min(w * .22, 96), x: w * .5, y: h * .66 } : { s: Math.min(w * .1, h * .2, 150), x: w * .68, y: h * .52 };
    const listen = (w, h) => w < 760 ? { s: 40, x: w * .07 + 24, y: h * .66 - 118 } : { s: Math.min(w * .036, 54), x: w * .52 + 30, y: h * .5 - 122 };
    const at = (w, h) => { const a = think(w, h), b = listen(w, h); return { s: lerp(a.s, b.s, pose), x: lerp(a.x, b.x, pose), y: lerp(a.y, b.y, pose) }; };
    const T = new Talli($('#flowTalli'), { pink: 'night', centerGroup: true, size: (w, h) => at(w, h).s, center: (w, h) => at(w, h), start: 'gone' });
    T.lettersTarget = '';
    T.voice = now => f.speaking ? .4 + .45 * Math.abs(Math.sin(now * 9.3) * .6 + Math.sin(now * 15.7) * .4) : 0;
    const LETTERS = ['', 'h', 'hh', 'hm', 'hmmm'];

    function to(state) {
      const s = T.S.state, away = s === 'gone' || s === 'hide' || s === 'saving';
      // it saves what it heard; if it never got to listen, it leaves at once
      if (state === 'away') { if (!away) T.set(s === 'listening' ? 'saving' : 'hide'); return; }
      if (away) { T.afterAppear = state; T.set('appear', { entrance: 'rise' }); } else T.set(state);
    }

    const GROUPS = {
      moving: ['moving', 'move', 'flat', 'apartment', 'home', 'boxes', 'box', 'pack', 'landlord', 'rent', 'sam', 'march', 'books'],
      work: ['kai', 'pitch', 'work', 'job', 'deadline', 'meeting', 'client', 'follow'],
      dream: ['dream', 'sleep', 'night', 'sea', 'lake', 'flying', 'fly'],
      days: ['coffee', 'grandma', 'mum', 'mom', 'sunday', 'weekend', 'guitar', 'lisbon', 'run', 'trip'],
      feel: ['tired', 'excited', 'calm', 'patience', 'feeling', 'mood', 'stress'],
      aeh: ['äh', 'ähm', 'hmm', 'uh', 'um', 'aeh'],
    };
    const WORDS = { moving: 'move, Sam, landlord, boxes, the old flat, March', work: 'Kai, the pitch, gut feeling, deadline', dream: 'dreamt, a lake in the kitchen, the sea, flying again',
      days: 'coffee, grandma, call mum, Sunday, Lisbon', feel: 'tired, excited, calm, patience', aeh: 'äh, ähm, hmm: kept, never cleaned up' };
    const groupFor = s => { const v = s.trim().toLowerCase(); if (v.length < 2) return ''; return Object.keys(GROUPS).find(k => GROUPS[k].some(t => t.startsWith(v) || (v.length > 3 && v.startsWith(t)))) || null; };
    function show(g, query) {
      f.find(g || '');
      $$('#chips button').forEach(b => b.setAttribute('aria-pressed', String(!!g && b.dataset.g === g)));
      found.innerHTML = g ? `found: <b>${WORDS[g]}</b>` : query ? `nothing found for “${query.replace(/[<>&]/g, '')}”.` : '';
    }
    $$('#chips button').forEach(b => b.addEventListener('click', () => { picked = true; const on = b.getAttribute('aria-pressed') !== 'true'; q.value = on ? b.textContent : ''; show(on ? b.dataset.g : '', ''); }));
    q.addEventListener('input', () => { picked = true; show(groupFor(q.value), q.value.trim()); });

    (function tick() {
      const r = sec.getBoundingClientRect(), p = clamp(-r.top / Math.max(1, r.height - innerHeight));
      f.setProgress(p);
      steps.forEach(s => s.classList.toggle('on', p >= +s.dataset.from && p < +s.dataset.to));
      cue.style.opacity = p < .015 ? .9 : 0;

      // what tälli does here
      const next = p < .13 ? 'thinking' : p < .27 ? 'listening' : 'away';
      if (next !== want) { want = next; to(next); if (next === 'listening') f.speak(); }
      if (p < .1) f.spokenAt = null;   // scrolling back up lets the thought be spoken again
      T.lettersTarget = next === 'thinking' ? LETTERS[Math.min(4, Math.floor(p / .13 * 5))] : '';
      pose += ((next === 'thinking' ? 0 : 1) - pose) * (RM.matches ? 1 : .08);

      // search: show one by itself, until someone tries their own
      if (p >= .8 && !picked && !f.active) { q.value = 'moving'; show('moving', ''); }
      if (p < .8 && (f.active || q.value)) { picked = false; q.value = ''; show('', ''); }
      requestAnimationFrame(tick);
    })();
  }

  // ---------- 4 · privacy: tälli, locked in a cage with your thoughts ----------
  function cage() {
    // a birdcage seen from the front, in the 400 × 520 units of the two svg layers
    const CX = 200, R = 150, RY = 22, TOP = 66, DOME = 190, MID = 322, BASE = 455, N = 13;
    const bar = dx => `M${CX},${TOP} C${CX + dx * .55},${TOP} ${CX + dx},${TOP + 44} ${CX + dx},${DOME} L${CX + dx},${BASE}`;
    const ring = (y, front) => `M${CX - R},${y} A${R},${RY} 0 0 ${front ? 0 : 1} ${CX + R},${y}`;
    let back = `<ellipse class="floor" cx="${CX}" cy="${BASE}" rx="${R}" ry="${RY}"/>`, front = '';
    for (let i = 0; i < N; i++) {
      const a = (i + .5) / N * Math.PI * 2, p = `<path class="bar" d="${bar(Math.sin(a) * R)}"/>`;
      if (Math.cos(a) > 0) front += p; else back += p;
    }
    [DOME, MID, BASE].forEach(y => { back += `<path class="ring" d="${ring(y, false)}"/>`; front += `<path class="ring" d="${ring(y, true)}"/>`; });
    front += `<path class="plinth" d="M${CX - R},${BASE} L${CX - R},${BASE + 21} A${R},${RY} 0 0 0 ${CX + R},${BASE + 21} L${CX + R},${BASE} A${R},${RY} 0 0 1 ${CX - R},${BASE} Z"/>`
      + `<circle class="hook" cx="${CX}" cy="36" r="13"/><path class="bar" d="M${CX},49 V${TOP}"/><ellipse class="cap" cx="${CX}" cy="${TOP}" rx="13" ry="5"/>`
      + `<path class="door" d="M158,446 V262 Q158,236 200,236 Q242,236 242,262 V446"/>`
      + `<g class="lock" id="lock" transform="translate(242 330)"><path class="shackle" d="M-9,9 V1 a9,9 0 0 1 18,0 V9"/><rect class="body" x="-15" y="7" width="30" height="25" rx="6"/><circle class="hole" cx="0" cy="17" r="3.4"/><rect class="hole" x="-1.4" y="17" width="2.8" height="8" rx="1.2"/></g>`;
    $('#cageBack').innerHTML = back; $('#cageFront').innerHTML = front;

    new Talli($('#cageTalli'), { pink: 'night', size: w => w * .36, center: (w, h) => ({ x: w * .5, y: h * (380 / 520) }) });

    // your thoughts float around inside and bounce off the bars
    const cv = $('#cageWords'), lock = $('#lock'), dpr = Math.min(2, devicePixelRatio || 1);
    const B = { x0: 74, x1: 326, y0: 206, y1: 440 };
    const words = ['move', 'Sam', 'the pitch', 'dreamt', 'tired', 'äh', 'coffee', 'Sunday', 'ähm', 'boxes'].map((t, i) => {
      const a = i * 2.4 + .7, v = 9 + (i % 4) * 3;
      return { t, x: B.x0 + 30 + (i * 53) % (B.x1 - B.x0 - 60), y: B.y0 + 16 + (i * 37) % (B.y1 - B.y0 - 32), vx: Math.cos(a) * v, vy: Math.sin(a) * v, aeh: /^äh/.test(t) };
    });
    let visible = false, last = performance.now() / 1000, ctx, s = 1;
    new IntersectionObserver(es => { visible = es[0].isIntersecting; }).observe(cv);
    const fit = () => { const r = cv.getBoundingClientRect(); cv.width = Math.round(r.width * dpr); cv.height = Math.round(r.height * dpr); ctx = cv.getContext('2d'); s = r.width / 400; ctx.setTransform(dpr * s, 0, 0, dpr * s, 0, 0); };
    new ResizeObserver(fit).observe(cv); fit();
    (function tick() {
      const now = performance.now() / 1000, dt = Math.min(.05, now - last); last = now;
      if (visible && ctx) {
        ctx.clearRect(0, 0, 400, 520); ctx.font = '450 15px "Funnel Sans", system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        for (const w of words) {
          const hw = ctx.measureText(w.t).width / 2;
          if (!RM.matches) { w.x += w.vx * dt; w.y += w.vy * dt; }
          if (w.x - hw < B.x0) w.vx = Math.abs(w.vx); else if (w.x + hw > B.x1) w.vx = -Math.abs(w.vx);
          if (w.y - 8 < B.y0) w.vy = Math.abs(w.vy); else if (w.y + 8 > B.y1) w.vy = -Math.abs(w.vy);
          ctx.globalAlpha = w.aeh ? .55 : .8; ctx.fillStyle = '#98A3C3'; ctx.fillText(w.t, w.x, w.y);
        }
        ctx.globalAlpha = 1;
      }
      requestAnimationFrame(tick);
    })();
    lock.addEventListener('click', () => { lock.classList.remove('jiggle'); void lock.getBoundingClientRect(); lock.classList.add('jiggle'); });
  }

  // ---------- footer: tälli peeks once more ----------
  function foot() {
    const size = (w, h) => Math.min(h * .9, w * .42);
    new Talli($('#footPeek'), { pink: 'night', size, look: { x: -.4, y: -.5 }, center: (w, h) => ({ x: w > 860 ? w * .78 : w * .72, y: h + size(w, h) * .06 }) });
  }
})();
