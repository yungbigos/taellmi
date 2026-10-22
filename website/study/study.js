// tällmi website design study: picks, the three directions, the demo pieces.
(() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const onView = (el, fn) => new IntersectionObserver((es, io) => { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { threshold: .35 }).observe(el);

  // ---------- theme (not remembered: this page stores nothing) ----------
  const root = document.documentElement, themeBtn = $('#theme'), sysDark = matchMedia('(prefers-color-scheme: dark)');
  const effective = () => root.dataset.theme || (sysDark.matches ? 'dark' : 'light');
  const themeLabel = () => { themeBtn.textContent = effective() === 'dark' ? 'light' : 'dark'; themeBtn.setAttribute('aria-label', 'switch to ' + themeBtn.textContent); };
  themeBtn.addEventListener('click', () => { root.dataset.theme = effective() === 'dark' ? 'light' : 'dark'; themeLabel(); });
  sysDark.addEventListener('change', themeLabel); themeLabel();

  // ---------- picks ----------
  const picks = {}, chosen = {}, dirs = { A: 'paper', B: 'night', C: 'space' };
  let dir = null;
  const COPY = { sub: ['sub', 'text'], idea: ['idea', 'text'], priv: ['priv', 'text'], privSub: ['priv', 'sub'], try: ['try', 'text'], contrib: ['contrib', 'text'], close: ['close', 'text'], closeSub: ['close', 'sub'] };
  function applyCopy() { $$('[data-copy]').forEach(el => { const [g, f] = COPY[el.dataset.copy] || []; if (picks[g]) el.textContent = picks[g][f] || ''; }); }
  $$('.group[data-group]').forEach(g => {
    const key = g.dataset.group, opts = $$('.opt', g);
    const choose = (b, explicit) => {
      opts.forEach(o => o.setAttribute('aria-pressed', String(o === b)));
      picks[key] = { v: b.dataset.v, text: $('[data-text]', b)?.textContent || '', sub: $('[data-sub]', b)?.textContent || '', name: g.dataset.name };
      if (explicit) chosen[key] = true;
      applyCopy(); summary();
    };
    opts.forEach(o => o.addEventListener('click', () => choose(o, true)));
    choose(opts.find(o => o.hasAttribute('data-sug')) || opts[0], false);
  });
  $$('.pick').forEach(b => b.addEventListener('click', () => { dir = dir === b.dataset.dir ? null : b.dataset.dir; $$('.pick').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.dir === dir))); summary(); }));
  $$('.check').forEach(b => { b.setAttribute('aria-pressed', String(b.hasAttribute('data-sug'))); b.addEventListener('click', () => { b.setAttribute('aria-pressed', String(b.getAttribute('aria-pressed') !== 'true')); summary(); }); });
  summary();
  function summary() {
    const out = $('#summary'); if (!out) return;
    const lines = [`direction: ${dir ? dir + ' · ' + dirs[dir] : 'not picked yet'}`];
    Object.entries(picks).forEach(([k, p]) => lines.push(`${p.name}: ${p.text ? `“${p.text}”` : p.v}${p.sub ? ` / “${p.sub}”` : ''}${chosen[k] ? '' : ' (suggested, not picked)'}`));
    lines.push('pieces: ' + ($$('.check[aria-pressed="true"]').map(b => b.dataset.v).join(', ') || 'none'));
    out.textContent = lines.join('\n');
  }
  $('#copy').addEventListener('click', async e => {
    const text = $('#summary').textContent;
    try { await navigator.clipboard.writeText(text); e.target.textContent = 'copied.'; }
    catch { const r = document.createRange(); r.selectNodeContents($('#summary')); getSelection().removeAllRanges(); getSelection().addRange(r); e.target.textContent = 'selected. press ⌘C to copy.'; }
    setTimeout(() => { e.target.textContent = 'copy picks'; }, 2200);
  });

  // ---------- full screen ----------
  $$('.fs').forEach(b => b.addEventListener('click', () => { const f = b.closest('.frame'); (f.requestFullscreen || f.webkitRequestFullscreen).call(f); }));

  // ---------- this page, counted ----------
  function counts() {
    const host = location.host;
    const req = performance.getEntriesByType('resource').filter(e => { try { const u = new URL(e.name, location.href); return /^https?:$/.test(u.protocol) && u.host !== host; } catch { return false; } }).length;
    let store = 0; try { store = localStorage.length + sessionStorage.length; } catch { /* storage blocked counts as none */ }
    const cookies = document.cookie ? document.cookie.split(';').filter(s => s.trim()).length : 0;
    const v = { cookies, req, store };
    $$('[data-count]').forEach(el => { el.textContent = v[el.dataset.count]; });
  }
  counts();
  try { new PerformanceObserver(counts).observe({ type: 'resource', buffered: true }); } catch { setInterval(counts, 5000); }

  TalliKit.ready.then(() => { dirA(); dirB(); dirC(); desk(); play(); });

  // ---------- A · paper ----------
  function dirA() {
    const hero = new Talli($('#aHero'), { size: (w, h) => Math.min(w * .6, h * .46, 300), center: (w, h) => ({ x: w * .5, y: h * .52 }), start: 'gone' });
    onView($('#aHero'), () => hero.set('appear', { entrance: 'roll' }));

    const aeh = new Talli($('#aAeh'), { size: (w, h) => Math.min(w / 2.7, h * .3, 120), centerGroup: true, center: (w, h) => ({ x: w / 2, y: h * .56 }), start: 'thinking' });
    aeh.lettersTarget = '';
    const STEPS = ['', 'h', 'hh', 'hm', 'hmmm'], sc = $('#aScroll'), lines = $$('#aLines li'), hint = $('#aHint');
    const onScroll = () => {
      const p = clamp(sc.scrollTop / Math.max(1, sc.scrollHeight - sc.clientHeight)), i = Math.min(4, Math.floor(p * 5));
      aeh.lettersTarget = STEPS[i]; lines.forEach((l, k) => l.classList.toggle('on', k <= i)); hint.style.opacity = p > .04 ? 0 : 1;
    };
    sc.addEventListener('scroll', onScroll, { passive: true }); onScroll();
  }

  // ---------- B · night ----------
  function dirB() {
    const B = { rise: 0, riseT: 0 }, bubble = $('#bBubble');
    const size = (w, h) => Math.min(h * .55, w * .4);
    const peek = new Talli($('#bHero'), { size, pink: 'night', look: { x: .3, y: -.55 },
      center: (w, h) => { const GS = size(w, h); return { x: w / 2, y: h + GS * .03 - B.rise * GS * .34 }; } });
    $('#bHero').addEventListener('pointerdown', e => { if (peek.hit(e.clientX, e.clientY)) B.riseT = B.riseT ? 0 : 1; });
    (function tick() { B.rise += (B.riseT - B.rise) * (TalliKit.reduceMotion.matches ? 1 : .1); bubble.classList.toggle('on', B.rise > .7); requestAnimationFrame(tick); })();

    // the äh stays in: tälli listens to a short thought, on a loop
    const SAY = 'Okay, äh, before I forget: talked to Sam today about the move. I think we’ll do it in March after all. And, ähm, I really need to call the landlord before Friday.';
    const tr = $('#bTranscript');
    const listen = new Talli($('#bListen'), { pink: 'night', size: (w, h) => w < 520 ? Math.min(w * .2, 64) : Math.min(w * .16, h * .28, 90),
      center: (w, h) => w < 520 ? { x: w / 2, y: h * .26 } : { x: w * .22, y: h * .56 }, start: 'gone' });
    let speaking = false;
    listen.voice = now => speaking ? .4 + .45 * Math.abs(Math.sin(now * 9.3) * .6 + Math.sin(now * 15.7) * .4) : 0;
    const words = SAY.split(' ');
    tr.innerHTML = `<span class="lab">spoken · now</span>` + words.map(w => `<span class="w${/^äh|^ähm/i.test(w) ? ' aeh' : ''}">${esc(w)}</span>`).join(' ');
    const spans = $$('.w', tr);
    async function loop() {
      for (;;) {
        spans.forEach(s => s.classList.remove('on'));
        listen.afterAppear = 'listening'; listen.set('appear'); await wait(1100);
        for (let i = 0; i < spans.length; i++) {
          speaking = true; spans[i].classList.add('on');
          await wait(170 + words[i].length * 30);
          if (/,$/.test(words[i]) && spans[i].classList.contains('aeh')) { speaking = false; await wait(1100); }
          else if (/[.:]$/.test(words[i])) { speaking = false; await wait(420); }
        }
        speaking = false; await wait(1300);
        listen.set('saving'); await new Promise(r => { listen.on.gone = r; }); await wait(1400);
      }
    }
    onView($('#bListen'), loop);

    // dozing: the clock says it's 3 am
    new Talli($('#bSleep'), { pink: 'night', hour: 3, follow: false, look: { x: -.2, y: .3 }, size: (w, h) => Math.min(w * .22, h * .34, 120),
      center: (w, h) => ({ x: w * .74, y: h * .42 }) });
  }

  // ---------- C · space ----------
  function dirC() {
    const hero = new WordField($('#cHero'), { count: 52, clear: { rx: .4, ry: .3, y: .5 } });
    $$('#cChips button').forEach(b => b.addEventListener('click', () => {
      const on = b.getAttribute('aria-pressed') !== 'true';
      $$('#cChips button').forEach(x => x.setAttribute('aria-pressed', 'false'));
      b.setAttribute('aria-pressed', String(on)); hero.find(on ? b.dataset.g : '');
    }));

    const sc = $('#cScroll'), fly = new WordField($('#cFly'), { count: 56, scroll: sc, size: 54 }), end = $('#cEnd'), hint = $('#cHint');
    (function tick() { end.classList.toggle('on', fly.end > .5); hint.style.opacity = sc.scrollTop > 20 ? 0 : 1; requestAnimationFrame(tick); })();

    const land = new WordField($('#cLand'), { count: 36, drift: 18, size: 48, clear: { rx: .42, ry: .22 } });
    const PHRASE = [['Okay,', 'w'], ['äh,', 'aeh'], ['talked', 'w'], ['to', 'w'], ['Sam', 'w'], ['today', 'w'], ['about', 'w'], ['the', 'w'], ['move.', 'w'], ['And,', 'w'], ['ähm,', 'aeh'], ['I', 'w'], ['really', 'w'], ['need', 'w'], ['to', 'w'], ['call', 'w'], ['the', 'w'], ['landlord.', 'w']];
    land.on = { done: () => setTimeout(() => land.say(PHRASE), 1600) };
    onView($('#cLand'), () => land.say(PHRASE));
  }

  // ---------- the full demo ----------
  function desk() {
    const free = $('#free'), bubble = $('#bubble'), live = $('#live'), note = $('#bubbleNote'), hint = $('#deskHint'), q = $('#q'), stream = $('#stream');
    const t = new Talli($('#deskTalli'), { size: (w, h) => clamp(Math.min(w, h) * .14, 44, 72), pokeable: false, start: 'gone' });
    let mode = 'off', run = 0, speaking = false, spoken = [], deskVisible = false, lastId = null;
    t.voice = now => speaking ? .4 + .45 * Math.abs(Math.sin(now * 9.3) * .6 + Math.sin(now * 15.7) * .4) : 0;
    new IntersectionObserver(es => { deskVisible = es[0].isIntersecting; }).observe($('#desk'));

    const SCRIPT = [['Okay,', .28], ['äh,', .32], 1.1, ['before', .22], ['I', .1], ['forget.', .4], .5, ['Talked', .24], ['to', .1], ['Sam', .3], ['today', .26], ['about', .2], ['the', .1], ['move.', .4], .6,
      ['I', .1], ['think', .2], ['we’ll', .2], ['do', .12], ['it', .1], ['in', .1], ['March', .3], ['after', .2], ['all.', .36], .55, ['And,', .26], ['ähm,', .36], 1.2, ['I', .12], ['really', .22], ['need', .18], ['to', .1], ['call', .2], ['the', .1], ['landlord', .36], ['before', .24], ['Friday.', .5]];

    const autosize = () => { live.style.height = 'auto'; live.style.height = Math.min(180, live.scrollHeight) + 'px'; };
    function place(x, y) {
      const w = free.clientWidth, h = free.clientHeight, GS = t.GS;
      x = clamp(x, GS * .8, w - GS * .8); y = clamp(y, GS * 1.2 + 30, h - GS * .5); t.pos = { x, y };
      const bw = Math.min(300, w - 24); let left = x + GS * .8, top = y - GS * 1.1;
      if (left + bw > w - 12) left = x - GS * .8 - bw;
      if (left < 12) { left = clamp(x - bw / 2, 12, w - bw - 12); top = y + GS * .7; }
      bubble.style.left = left + 'px'; bubble.style.top = clamp(top, 34, h - 130) + 'px';
    }
    function done(msg) {
      bubble.classList.add('done'); note.textContent = msg;
      t.on.gone = () => { bubble.hidden = true; mode = 'off'; t.pos = null; hint.textContent = 'call tälli again, or search on the right'; hint.classList.remove('off'); };
    }
    function call(x, y) {
      if (mode !== 'off') return;
      mode = 'listening'; spoken = []; live.value = ''; note.textContent = ''; bubble.classList.remove('done');
      place(x, y); hint.classList.add('off'); bubble.hidden = false; autosize();
      t.afterAppear = 'listening'; t.set('appear', { entrance: 'rise' });
      speak(++run);
    }
    async function speak(id) {
      await wait(900);
      for (const step of SCRIPT) {
        if (id !== run || mode !== 'listening') return;
        if (typeof step === 'number') { speaking = false; await wait(step * 1000); continue; }
        speaking = true; spoken.push(step[0]); live.value = spoken.join(' '); autosize();
        await wait(step[1] * 1000);
      }
      speaking = false;
      if (id !== run || mode !== 'listening') return;
      note.textContent = 'click the desk to keep it · esc discards';
      await wait(2600);
      if (id === run && mode === 'listening') keep();
    }
    function keep() {
      if (mode !== 'listening' && mode !== 'typing') return;
      const text = live.value.trim(); if (!text) return discard();
      const scripted = spoken.length > 0 && text === spoken.join(' ') && spoken.length === SCRIPT.filter(s => typeof s !== 'number').length;
      mode = 'saving'; run++; speaking = false; live.blur();
      const th = { id: 'n' + Date.now(), source: spoken.length ? 'spoken' : 'typed', at: new Date(), text, concepts: scripted ? ['Sam', 'move', 'March', 'landlord'] : [],
        summary: scripted ? 'the move with Sam is likely in March; call the landlord before Friday.' : null, fresh: true, pending: true };
      thoughts.unshift(th); lastId = th.id; q.value = ''; render(); th.fresh = false;
      t.on.say = v => { if (v) done('saved.'); };
      t.set('saving');
      setTimeout(() => { th.pending = false; $$(`[data-id="${th.id}"] .pending`, stream).forEach(el => el.classList.remove('pending')); }, 1500);
    }
    function discard() {
      if (mode !== 'listening' && mode !== 'typing') return;
      mode = 'saving'; run++; speaking = false; live.blur(); t.on.say = null;
      done('discarded.'); setTimeout(() => t.set('hide'), 700);
    }

    free.addEventListener('click', e => {
      if (bubble.contains(e.target)) return;
      const r = free.getBoundingClientRect();
      if (mode === 'off') call(e.clientX - r.left, e.clientY - r.top);
      else if (mode === 'listening' || mode === 'typing') { if (t.hit(e.clientX, e.clientY)) t.poke(); else keep(); }
    });
    live.addEventListener('focus', () => { if (mode === 'listening') { mode = 'typing'; run++; speaking = false; t.set('idle'); note.textContent = 'return keeps it · esc discards'; } });
    live.addEventListener('input', autosize);
    live.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); keep(); } else if (e.key === 'Escape') discard(); });
    note.addEventListener('click', () => {
      const li = lastId && $(`[data-id="${lastId}"]`, stream); if (!li || note.textContent !== 'saved.') return;
      li.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); li.classList.remove('fresh'); void li.offsetWidth; li.classList.add('fresh');
    });
    addEventListener('keydown', e => {
      if (!deskVisible) return;
      if (e.code === 'KeyT' && e.ctrlKey && e.altKey) { e.preventDefault(); if (mode === 'off') call(free.clientWidth * .38, free.clientHeight * .58); else keep(); }
      else if (e.key === 'Escape') discard();
    });

    // a small archive to search, dated relative to today
    const day = (n, h, m) => { const d = new Date(); d.setDate(d.getDate() - n); d.setHours(h, m, 0, 0); return d; };
    const thoughts = [
      { id: 'c', source: 'spoken', at: day(1, 18, 30), text: 'The pitch went well, äh, I think. Kai nodded a lot but barely said anything. Follow up tomorrow.', concepts: ['Kai', 'pitch'] },
      { id: 'b', source: 'typed', at: day(2, 22, 10), h: 'Boxes', list: ['14 packed, 20 to go', 'books last', 'don’t forget the lamp for Sam'], concepts: ['Sam', 'Boxes'] },
      { id: 'a', source: 'spoken', at: day(3, 7, 48), text: 'Ähm, I dreamt I was back in the old flat. All the rooms were bigger, and somehow there was a lake in the kitchen.', concepts: ['flat'] },
    ];
    // search by meaning, faked with a few word families; the app uses an embedding model on the mac
    const MEANING = [
      ['moving', 'move', 'flat', 'apartment', 'home', 'boxes', 'box', 'packed', 'pack', 'landlord', 'rent'],
      ['dream', 'sleep', 'night', 'bed'],
      ['work', 'job', 'pitch', 'meeting', 'client'],
    ];
    const plain = th => th.text || [th.h, ...th.list].join(' ');
    const tokens = s => s.toLowerCase().match(/[\p{L}\p{N}]+/gu) || [];
    function match(th, qv) {
      if (!qv) return null;
      const ws = tokens(plain(th));
      if (qv.length >= 2 && ws.some(w => w.includes(qv))) return { kind: 'word', q: qv };
      if (qv.length >= 3) {
        const rel = MEANING.filter(g => g.some(term => term.startsWith(qv) || qv.startsWith(term))).flat();
        if (rel.length && ws.some(w => rel.some(r => w.startsWith(r)))) return { kind: 'meaning', rel };
      }
      return null;
    }
    function mark(str, th, m) {
      return str.split(/([\p{L}\p{N}’']+)/u).map((part, i) => {
        if (i % 2 === 0) return esc(part);
        const lw = part.toLowerCase(); let html = esc(part);
        if (th.concepts.some(c => c.toLowerCase() === lw)) html = `<span class="concept${th.pending ? ' pending' : ''}">${html}</span>`;
        if (m && m.kind === 'word' && lw.includes(m.q)) html = `<mark class="hit">${html}</mark>`;
        else if (m && m.kind === 'meaning' && m.rel.some(r => lw.startsWith(r))) html = `<mark class="rel">${html}</mark>`;
        return html;
      }).join('');
    }
    const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'], MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    const two = n => String(n).padStart(2, '0');
    const fmt = d => `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]} · ${two(d.getHours())}:${two(d.getMinutes())}`;
    function render() {
      const qv = q.value.trim().toLowerCase();
      let rows = thoughts.map(th => ({ th, m: match(th, qv) }));
      if (qv) rows = rows.filter(r => r.m).sort((a, b) => (a.m.kind === 'word' ? 0 : 1) - (b.m.kind === 'word' ? 0 : 1) || b.th.at - a.th.at);
      stream.innerHTML = rows.length ? rows.map(({ th, m }) => `<li data-id="${th.id}" class="${m ? 'match' : ''}${th.fresh ? ' fresh' : ''}">
        <p class="meta">${th.source} · ${fmt(th.at)}${m ? ` · ${m.kind === 'word' ? 'by word' : 'by meaning'}` : ''}</p>
        ${th.text ? `<p class="tx">${mark(th.text, th, m)}</p>` : `<p class="h">${mark(th.h, th, m)}</p><ul>${th.list.map(x => `<li>${mark(x, th, m)}</li>`).join('')}</ul>`}
        ${th.summary ? `<p class="sum${th.pending ? ' pending' : ''}"><b>summary</b> · made on this mac · ${esc(th.summary)}</p>` : ''}
      </li>`).join('') : `<li class="empty">nothing found for “${esc(qv)}”.</li>`;
    }
    q.addEventListener('input', render);
    $$('#chips button').forEach(b => b.addEventListener('click', () => { q.value = b.textContent; render(); }));
    render();

    const clock = () => { const d = new Date(); $('#clock').textContent = `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}  ${two(d.getHours())}:${two(d.getMinutes())}`; };
    clock(); setInterval(clock, 20000);
  }

  // ---------- tälli up close ----------
  function play() {
    const t = new Talli($('#playTalli'), { pink: 'night', centerGroup: true, size: (w, h) => Math.min(w * .3, h * .4, 150), center: (w, h) => ({ x: w / 2, y: h * .58 }) });
    const say = $('#playSay'), mic = $('#mic'), micNote = $('#micNote'), tod = $('#tod'), todV = $('#todV');
    const press = s => $$('#states button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.s === s)));
    function setState(s) {
      press(s); say.style.opacity = 0;
      if (s === 'saving') {
        t.on.say = v => { say.style.opacity = v ? 1 : 0; };
        t.on.gone = () => setTimeout(() => { t.afterAppear = 'idle'; t.set('appear'); press('idle'); }, 700);
      }
      t.set(s);
    }
    $$('#states button').forEach(b => b.addEventListener('click', () => setState(b.dataset.s)));

    let stream = null, actx = null;
    mic.addEventListener('click', async () => {
      if (stream) { stopMic(); return; }
      try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } }); }
      catch { micNote.textContent = 'couldn’t use the microphone. allow it for this page in your browser, then try again.'; return; }
      actx = new AudioContext(); const an = actx.createAnalyser(); an.fftSize = 1024; actx.createMediaStreamSource(stream).connect(an);
      const buf = new Float32Array(an.fftSize);
      t.voice = () => { an.getFloatTimeDomainData(buf); let s = 0; for (const v of buf) s += v * v; return clamp((Math.sqrt(s / buf.length) - .008) * 9); };
      setState('listening'); mic.textContent = 'stop listening';
    });
    function stopMic() { stream.getTracks().forEach(k => k.stop()); stream = null; actx.close(); actx = null; t.voice = null; mic.textContent = 'let tälli hear you'; setState('idle'); }

    const now = new Date(); tod.value = now.getHours() + Math.round(now.getMinutes() / 15) / 4;
    tod.addEventListener('input', () => { const h = +tod.value; t.o.hour = h; todV.textContent = `${String(Math.floor(h) % 24).padStart(2, '0')}:${String(Math.round((h % 1) * 60)).padStart(2, '0')}`; });
  }
})();
