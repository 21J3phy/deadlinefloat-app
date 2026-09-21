/* DeadlineFloat — deadlinefloat.app
 *
 * The interactive panel on this page is a browser recreation of the real macOS
 * app: the same fabricated calendar the app's own `--demo` mode uses, the same
 * Google Calendar colours, the same midnight-to-midnight ruler, and the same
 * countdown wording (whole minutes, in words, truncated never rounded).
 */
(() => {
  'use strict';

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ------------------------------------------------------------ the clock */

  // Pinned to an early afternoon so there is always something happening now,
  // exactly like the screenshot renderer does — but it ticks in real time, so
  // every countdown on the page is genuinely counting down.
  const BASE = (() => { const d = new Date(); d.setHours(14, 7, 0, 0); return d; })();
  const T0 = performance.now();
  const now = () => new Date(BASE.getTime() + (performance.now() - T0));

  /* ------------------------------------------------------------- the data */

  // Colours are the ones Google Calendar *shows* (its Material palette), which
  // is what the app draws — not the 2010 hexes the API still reports.
  const CALENDARS = {
    math: { name: 'MATH 26500', color: '#d50000' },
    cs:   { name: 'CS 18000',   color: '#3f51b5' },
    engr: { name: 'ENGR 133',   color: '#0b8043' },
    me:   { name: 'Personal',   color: '#9e69af' }
  };

  const SOURCE = [
    // today
    { id: 'm0', cal: 'math', title: 'MATH 26500 lecture',              at: [0, 9, 30],  mins: 50,  loc: 'WALC 1055' },
    { id: 'c0', cal: 'cs',   title: 'CS 18000 lab',                    at: [0, 11, 30], mins: 110, loc: 'LWSN B146' },
    { id: 'm1', cal: 'math', title: 'DUE: Homework 7 — Eigenvalues',   off: -(2 * 60 + 14), mins: 30 },
    { id: 'e0', cal: 'engr', title: 'ENGR 133 studio',                 at: [0, 13, 30], mins: 110, loc: 'ARMS B071' },
    { id: 'c1', cal: 'cs',   title: 'SUBMIT Project 3 — Recursion',    off: 2 * 60 + 14, mins: 30, loc: 'Vocareum', color: '#d50000' },
    { id: 'e1', cal: 'engr', title: 'ENGR 133 report due',             at: [0, 17, 0],  mins: 15,  loc: 'Brightspace' },
    { id: 'p0', cal: 'me',   title: 'Team meeting',                    at: [0, 18, 0],  mins: 60,  loc: 'Zoom' },
    { id: 'c2', cal: 'cs',   title: 'Lab 09 deadline',                 off: 5 * 60 + 40, mins: 30, loc: 'Zoom' },
    { id: 'p4', cal: 'me',   title: 'Gym',                             at: [0, 20, 30], mins: 75 },
    { id: 'p1', cal: 'me',   title: 'Scholarship application deadline', off: 7 * 60 + 5, mins: 30, color: '#f4511e' },
    // tomorrow
    { id: 'm3', cal: 'math', title: 'MATH 26500 lecture',              at: [1, 9, 30],  mins: 50,  loc: 'WALC 1055' },
    { id: 'c4', cal: 'cs',   title: 'CS 18000 lecture',                at: [1, 14, 30], mins: 50,  loc: 'LILY 1105' },
    { id: 'c3', cal: 'cs',   title: 'Weekly reading due',              off: 26 * 60,    mins: 30 },
    { id: 'p5', cal: 'me',   title: 'Dinner',                          at: [1, 19, 0],  mins: 90 },
    { id: 'm2', cal: 'math', title: 'MATH 26500 quiz due',             at: [1, 23, 59], mins: 15 },
    { id: 'p2', cal: 'me',   title: 'Submit passport renewal',         allDay: [1, 2] },
    // the day after
    { id: 'e2', cal: 'engr', title: 'DUE Team charter',                allDay: [2, 1] },
    // excluded by the DONE rule, exactly as the app excludes it
    { id: 'p3', cal: 'me',   title: 'DONE Renew library books',        off: 3 * 60, mins: 30 }
  ];

  const startOfDay = (d, offset = 0) => {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    x.setDate(x.getDate() + offset);
    return x;
  };

  /** Titles that are deadlines: starts with DUE or SUBMIT, or contains due/deadline. */
  const isDeadline = t => /^\s*(due|submit)\b/i.test(t) || /\b(due|deadline)\b/i.test(t);
  /** Titles the app always hides. */
  const isExcluded = t => /^\s*(done|cancelled|canceled)\b/i.test(t);

  const EVENTS = SOURCE.filter(e => !isExcluded(e.title)).map(e => {
    const cal = CALENDARS[e.cal];
    const ev = { id: e.id, title: e.title, loc: e.loc, cal: cal.name, color: e.color || cal.color };
    if (e.allDay) {
      ev.allDay = true;
      ev.start = startOfDay(BASE, e.allDay[0]);
      ev.end = startOfDay(BASE, e.allDay[0] + e.allDay[1]);
      ev.span = e.allDay[1];
    } else if (e.at) {
      const d = startOfDay(BASE, e.at[0]);
      d.setHours(e.at[1], e.at[2], 0, 0);
      ev.start = d;
      ev.end = new Date(d.getTime() + e.mins * 60000);
    } else {
      const d = new Date(BASE.getTime() + e.off * 60000);
      d.setSeconds(0, 0);
      ev.start = d;
      ev.end = new Date(d.getTime() + e.mins * 60000);
    }
    ev.deadline = isDeadline(e.title);
    return ev;
  }).sort((a, b) => a.start - b.start);

  /* ------------------------------------------------- formatting, ported 1:1 */

  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

  function words(seconds) {
    const minutes = Math.floor(seconds / 60);
    const days = Math.floor(minutes / 1440);
    const hours = Math.floor((minutes % 1440) / 60);
    const mins = minutes % 60;
    if (days > 0) return hours > 0 ? `${plural(days, 'day')} ${hours} hr` : plural(days, 'day');
    if (hours > 0) return mins > 0 ? `${hours} hr ${mins} min` : `${hours} hr`;
    return `${mins} min`;
  }

  function countdown(target, at) {
    const s = Math.trunc((target - at) / 1000);
    if (s >= 0) return s < 60 ? '<1 min left' : `${words(s)} left`;
    return -s < 60 ? 'just now' : `${words(-s)} ago`;
  }

  function spotlightWords(target, at) {
    const s = Math.trunc((target - at) / 1000);
    if (s <= 0) return 'Now';
    if (s < 60) return '<1 min';
    return words(s);
  }

  /** Whole-day countdown for all-day deadlines: `Today`, `in 2 days`, `1 day ago`. */
  function allDayWords(dayStart, at) {
    const delta = Math.round((startOfDay(dayStart) - startOfDay(at)) / 86400000);
    if (delta === 0) return 'Today';
    return delta > 0 ? `in ${plural(delta, 'day')}` : `${plural(-delta, 'day')} ago`;
  }

  const fmtTime = d => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  const fmtHour = h => {
    const d = new Date(BASE); d.setHours(h, 0, 0, 0);
    return d.toLocaleTimeString([], { hour: 'numeric' });
  };
  const fmtDay = d => d.toLocaleDateString([], { month: 'short', day: 'numeric' });
  const fmtWeekday = d => d.toLocaleDateString([], { weekday: 'long' });

  const dayIndex = d => Math.round((startOfDay(d) - startOfDay(BASE)) / 86400000);
  const minutesInto = d => d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;

  /** How urgent a countdown reads: overdue, inside six hours, or neither. */
  function tone(target, at) {
    const left = (target - at) / 1000;
    if (left < 0) return 'bad';
    if (left < 6 * 3600) return 'warn';
    return '';
  }

  /* ----------------------------------------------------------- lane layout */

  /** Greedy column packing so overlapping blocks sit side by side, as the app does. */
  function lanes(list) {
    const items = list.map(e => ({
      ev: e,
      s: minutesInto(e.start),
      e: Math.max(minutesInto(e.start) + 24, minutesInto(e.end) > minutesInto(e.start) ? minutesInto(e.end) : 1440)
    })).sort((a, b) => a.s - b.s || b.e - a.e);

    const out = [];
    let cluster = [], clusterEnd = -1;

    const flush = () => {
      if (!cluster.length) return;
      const cols = [];
      cluster.forEach(it => {
        let i = 0;
        while (i < cols.length && cols[i] > it.s + 0.01) i++;
        cols[i] = it.e;
        it.lane = i;
      });
      cluster.forEach(it => { it.total = cols.length; out.push(it); });
      cluster = [];
    };

    items.forEach(it => {
      if (it.s >= clusterEnd - 0.01) { flush(); clusterEnd = it.e; }
      else clusterEnd = Math.max(clusterEnd, it.e);
      cluster.push(it);
    });
    flush();
    return out;
  }

  /* ---------------------------------------------------------------- icons */

  const ICON = {
    pin:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 4h6l-1 6 3 3H7l3-3-1-6Z"/><path d="M12 13v7"/></svg>',
    sync: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v5h-5"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.1"/><path d="M12 3v2.2M12 18.8V21M21 12h-2.2M5.2 12H3M18.4 5.6l-1.6 1.6M7.2 16.8l-1.6 1.6M18.4 18.4l-1.6-1.6M7.2 7.2 5.6 5.6"/></svg>',
    hourglass: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 3h10M7 21h10"/><path d="M8 3v3.2c0 1.1.5 2.1 1.4 2.8L12 11l2.6-2c.9-.7 1.4-1.7 1.4-2.8V3"/><path d="M8 21v-3.2c0-1.1.5-2.1 1.4-2.8L12 13l2.6 2c.9.7 1.4 1.7 1.4 2.8V21"/></svg>'
  };

  const el = (tag, cls, html) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  };
  const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  /* ---------------------------------------------------------- the panel */

  const DAY_WIDTH = { 1: 150, 2: 126, 3: 108, 7: 78 };
  const LEFT = 300, GUTTER = 46, HEAD = 58;

  function createPanel(host, options = {}) {
    const opts = Object.assign({ range: 1, open: false }, options);

    const root = el('div', 'df');
    root.innerHTML = `
      <div class="df-sheet"></div>
      <div class="df-scrim"></div>
      <div class="df-body">
        <div class="df-tasks">
          <div class="df-toolbar">
            <div class="df-seg" role="group" aria-label="How many days">
              <button type="button" data-range="1">1d</button>
              <button type="button" data-range="2">2d</button>
              <button type="button" data-range="3">3d</button>
              <button type="button" data-range="7">Week</button>
            </div>
            <div class="df-tools">
              <button type="button" title="Pin open" aria-label="Pin open">${ICON.pin}</button>
              <button type="button" title="Refresh" aria-label="Refresh" data-act="sync">${ICON.sync}</button>
              <button type="button" title="Settings" aria-label="Settings">${ICON.gear}</button>
            </div>
          </div>
          <div class="df-spot"></div>
          <div class="df-list"></div>
          <div class="df-foot"></div>
        </div>
        <div class="df-cal">
          <div class="df-cal-head"></div>
          <div class="df-cal-body">
            <div class="df-gutter"></div>
            <div class="df-days"></div>
            <div class="df-now"><b></b></div>
          </div>
        </div>
      </div>
      <div class="df-rail"><div class="df-blocks"></div><div class="df-now"><b></b></div></div>
      <div class="df-pill">
        <div class="df-pill-top"><i></i><em>NOW</em><b></b></div>
        <div class="df-pill-cd"></div>
      </div>`;
    host.appendChild(root);

    const q = s => root.querySelector(s);
    const spot = q('.df-spot'), list = q('.df-list'), foot = q('.df-foot');
    const calHead = q('.df-cal-head'), gutter = q('.df-gutter'), days = q('.df-days');
    const calNeedle = q('.df-cal-body > .df-now'), railBlocks = q('.df-rail .df-blocks');
    const railNeedle = q('.df-rail > .df-now');
    const pill = q('.df-pill'), pillTitle = q('.df-pill-top b'), pillCd = q('.df-pill-cd');

    const done = new Set();
    let range = opts.range, open = opts.open, scale = 1;

    /* ---- geometry */

    function applyMetrics() {
      const day = DAY_WIDTH[range];
      root.style.setProperty('--left', LEFT + 'px');
      root.style.setProperty('--gutter', GUTTER + 'px');
      root.style.setProperty('--day', day + 'px');
      root.style.setProperty('--head', HEAD + 'px');
      root.style.setProperty('--open-w', (LEFT + GUTTER + range * day) + 'px');
    }

    function setScale(k) { scale = k; root.style.zoom = k; }

    /* ---- the calendar */

    const pct = m => (m / 1440) * 100;

    function blockEl(ev, lane, total, withLabels) {
      const s = minutesInto(ev.start);
      const e = Math.max(s + 12, ev.end > ev.start ? minutesInto(ev.end) || 1440 : s + 12);
      const n = el('div', 'df-ev');
      n.style.top = pct(s) + '%';
      n.style.height = pct(Math.min(e, 1440) - s) + '%';
      n.style.minHeight = '15px';
      n.style.background = ev.color;
      const l = (lane / total) * 100, w = 100 / total;
      n.style.setProperty('--l', l + '%');
      n.style.setProperty('--w', `calc(${w}% - 2px)`);
      if (withLabels) { n.style.left = l + '%'; n.style.width = `calc(${w}% - 2px)`; }
      const sub = ev.loc ? `${fmtTime(ev.start)} · ${ev.loc}` : '';
      n.innerHTML = `<div class="df-ev-in"><b>${esc(ev.title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}</div>`;
      return n;
    }

    function renderCalendar() {
      calHead.innerHTML = '';
      days.innerHTML = '';
      gutter.innerHTML = '';

      for (let h = 0; h <= 22; h += 2) {
        const s = el('span', null, fmtHour(h));
        s.style.top = pct(h * 60) + '%';
        gutter.appendChild(s);
      }

      const lines = el('div', 'df-lines');
      lines.style.cssText = 'position:absolute;inset:0;pointer-events:none';
      for (let h = 1; h < 24; h++) {
        const l = el('div', 'df-hairline');
        l.style.top = pct(h * 60) + '%';
        lines.appendChild(l);
      }

      for (let i = 0; i < range; i++) {
        const date = startOfDay(BASE, i);

        const head = el('div', 'df-dayhead');
        head.style.setProperty('--i', i);
        const name = i === 0 ? 'Today' : i === 1 ? 'Tomorrow' : fmtWeekday(date);
        head.innerHTML = `<b>${esc(name)}</b><span>${fmtDay(date)}</span>`;
        const allDay = EVENTS.filter(ev => ev.allDay && !done.has(ev.id) &&
          dayIndex(ev.start) <= i && i < dayIndex(ev.start) + ev.span);
        if (allDay.length) {
          const strip = el('div', 'df-allday');
          allDay.slice(0, 2).forEach(ev => {
            const c = el('div', 'df-ad', esc(ev.title));
            c.style.background = ev.color;
            strip.appendChild(c);
          });
          head.appendChild(strip);
        }
        calHead.appendChild(head);

        const col = el('div', 'df-daycol');
        const blocks = el('div', 'df-blocks');
        if (i > 0) {
          const timed = EVENTS.filter(ev => !ev.allDay && !done.has(ev.id) && dayIndex(ev.start) === i);
          lanes(timed).forEach(it => blocks.appendChild(blockEl(it.ev, it.lane, it.total, true)));
        }
        col.appendChild(blocks);
        days.appendChild(col);
      }
      days.appendChild(lines);

      // Today's blocks live on the rail — the strip that is the sliver when
      // closed and stretches sideways into this column when open.
      railBlocks.innerHTML = '';
      const today = EVENTS.filter(ev => !ev.allDay && !done.has(ev.id) && dayIndex(ev.start) === 0);
      lanes(today).forEach(it => railBlocks.appendChild(blockEl(it.ev, it.lane, it.total, false)));
    }

    /* ---- the list */

    /** The deadlines inside the current window, still outstanding. */
    function visible() {
      return EVENTS.filter(ev => ev.deadline && !done.has(ev.id) && dayIndex(ev.start) < range);
    }

    function renderList(at) {
      const items = visible().slice().sort((a, b) => a.start - b.start);
      const groups = new Map();
      const push = (key, title, ev, overdue) => {
        if (!groups.has(key)) groups.set(key, { title, overdue, items: [] });
        groups.get(key).items.push(ev);
      };

      items.forEach(ev => {
        const overdue = ev.allDay ? dayIndex(ev.start) < 0 : ev.start < at;
        if (overdue) return push('overdue', 'Overdue', ev, true);
        const i = dayIndex(ev.start);
        if (i === 0) push('today', 'Due today', ev);
        else if (i === 1) push('tomorrow', 'Due tomorrow', ev);
        else push('d' + i, fmtWeekday(ev.start), ev);
      });

      list.innerHTML = '';
      groups.forEach(g => {
        const h = el('div', 'df-sec', `<b>${esc(g.title)}</b><span>${g.items.length}</span>`);
        if (g.overdue) h.setAttribute('data-overdue', '');
        list.appendChild(h);
        g.items.forEach(ev => list.appendChild(rowEl(ev, at, g.overdue)));
      });

      if (done.size) {
        const n = el('div', 'df-done-note',
          `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12.5 5 5L20 6.5"/></svg>
           ${done.size} done — waiting in the drawer above`);
        list.insertBefore(n, list.firstChild);
      }
      if (!groups.size && !done.size) {
        list.appendChild(el('div', 'df-done-note', 'Nothing due in this window'));
      }
    }

    function rowEl(ev, at, overdue) {
      const row = el('div', 'df-row');
      row.dataset.id = ev.id;
      if (overdue) row.setAttribute('data-overdue', '');
      const sub = [ev.cal, ev.loc].filter(Boolean).join(' · ');
      let time, cd, t;
      if (ev.allDay) {
        time = 'All day';
        cd = ev.span > 1 ? `through ${fmtDay(new Date(ev.end - 86400000))}` : allDayWords(ev.start, at);
        t = '';
      } else {
        time = fmtTime(ev.start);
        cd = countdown(ev.start, at);
        t = tone(ev.start, at);
      }
      row.innerHTML =
        `<i class="df-chip" style="background:${ev.color}"></i>
         <div class="df-m"><div class="df-t">${esc(ev.title)}</div><div class="df-s">${esc(sub)}</div></div>
         <div class="df-r"><div class="df-time">${esc(time)}</div><div class="df-cd"${t ? ` data-tone="${t}"` : ''}>${esc(cd)}</div></div>`;
      row.title = 'Swipe it done';
      row.addEventListener('click', () => markDone(ev.id, row));
      return row;
    }

    function markDone(id, row) {
      if (done.has(id)) return;
      row.classList.add('is-doing');
      window.setTimeout(() => { done.add(id); render(); }, reduced ? 0 : 340);
    }

    /* ---- the now/next card, the pill, the footer, the needle */

    function current(at) {
      const live = EVENTS.filter(ev => !ev.allDay && !done.has(ev.id) && ev.start <= at && at < ev.end)
        .sort((a, b) => a.end - b.end)[0];
      if (live) return { ev: live, kind: 'now', target: live.end };
      const next = EVENTS.filter(ev => !ev.allDay && !done.has(ev.id) && ev.deadline && ev.start > at)
        .sort((a, b) => a.start - b.start)[0];
      return next ? { ev: next, kind: 'next', target: next.start } : null;
    }

    function renderSpot(at) {
      const c = current(at);
      if (!c) { spot.innerHTML = ''; spot.style.display = 'none'; pill.style.display = 'none'; return; }
      spot.style.display = '';
      pill.style.display = '';
      spot.dataset.kind = c.kind;
      const label = c.kind === 'now' ? 'HAPPENING NOW' : 'DUE NEXT';
      const unit = c.kind === 'now' ? 'left' : 'until it';
      const tail = c.kind === 'now' ? `ends ${fmtTime(c.ev.end)}` : `at ${fmtTime(c.ev.start)}`;
      spot.innerHTML =
        `<div class="df-spot-top">
           <span class="df-spot-label">${label}</span>
           <span class="df-spot-cal"><i style="background:${c.ev.color}"></i>${esc(c.ev.cal)}</span>
         </div>
         <div class="df-spot-title">${esc(c.ev.title)}</div>
         <div class="df-spot-row">
           <span class="df-spot-big">${esc(spotlightWords(c.target, at))}</span>
           <span class="df-spot-unit">${unit}</span>
           <span class="df-spot-end">${esc(tail)}</span>
         </div>`;

      root.querySelector('.df-pill-top em').textContent = c.kind === 'now' ? 'NOW' : 'NEXT';
      pillTitle.textContent = c.ev.title;
      pillCd.textContent = c.kind === 'now'
        ? `${spotlightWords(c.target, at)} left`
        : `in ${spotlightWords(c.target, at)}`;
    }

    function renderFoot(at) {
      const overdue = visible().filter(ev => !ev.allDay && ev.start < at).length;
      foot.innerHTML = `<span>Updated ${fmtTime(at)}</span>` +
        (overdue ? `<span class="df-od"><i></i>${overdue} overdue</span>` : '');
    }

    function renderNeedle(at) {
      const y = pct(minutesInto(at)) + '%';
      calNeedle.style.top = y;
      railNeedle.style.top = y;
      calNeedle.querySelector('b').textContent = fmtTime(at);
    }

    /* ---- the whole thing */

    function render() {
      const at = now();
      applyMetrics();
      renderCalendar();
      renderList(at);
      renderSpot(at);
      renderFoot(at);
      renderNeedle(at);
      root.querySelectorAll('.df-seg button').forEach(b =>
        b.setAttribute('aria-pressed', String(Number(b.dataset.range) === range)));
    }

    function tick() {
      const at = now();
      renderSpot(at);
      renderNeedle(at);
      renderFoot(at);
      root.querySelectorAll('.df-row').forEach(row => {
        const ev = EVENTS.find(e => e.id === row.dataset.id);
        if (!ev || ev.allDay) return;
        const cd = row.querySelector('.df-cd');
        const next = countdown(ev.start, at);
        if (cd.textContent !== next) {
          cd.textContent = next;
          const t = tone(ev.start, at);
          if (t) cd.setAttribute('data-tone', t); else cd.removeAttribute('data-tone');
        }
      });
    }

    /* ---- controls */

    const api = {
      root,
      render,
      tick,
      get range() { return range; },
      get isOpen() { return open; },
      setScale,
      setRange(n) {
        if (range === n) return;
        range = n;
        applyMetrics();
        renderCalendar();
        renderList(now());
        root.querySelectorAll('.df-seg button').forEach(b =>
          b.setAttribute('aria-pressed', String(Number(b.dataset.range) === range)));
        host.dispatchEvent(new CustomEvent('df:range', { detail: n }));
      },
      setOpen(v) {
        if (open === v) return;
        open = v;
        root.classList.toggle('is-open', v);
        host.dispatchEvent(new CustomEvent('df:open', { detail: v }));
      },
      reset() { done.clear(); render(); },
      sweep() {
        const row = root.querySelector('.df-row:not([data-overdue])');
        if (row) markDone(row.dataset.id, row);
      }
    };

    root.classList.toggle('is-open', open);
    render();
    return api;
  }

  /* --------------------------------------------------------- the panel */

  const panels = [];
  const stage = document.querySelector('#demo-stage');
  let demo = null;

  if (stage) {
    demo = createPanel(stage, { range: 1, open: false });
    panels.push(demo);

    // The panel sits at the right edge of the screen with the copy at the left,
    // so it may only have what is left over: scale it until the widest state it
    // can reach — the week — still clears the copy column.
    const WIDEST = LEFT + GUTTER + 7 * DAY_WIDTH[7];
    const fit = () => {
      const vw = window.innerWidth;
      const copy = Math.min(440, vw * 0.36) + Math.max(vw * 0.05, 28) + 72;
      demo.setScale(Math.max(.5, Math.min(1, (vw - copy) / WIDEST)));
    };
    fit();
    window.addEventListener('resize', fit, { passive: true });
  }

  /* ------------------------------------------------------------ the tick */

  let visible = true;
  document.addEventListener('visibilitychange', () => { visible = !document.hidden; });
  window.setInterval(() => { if (visible) panels.forEach(p => p.tick()); }, 1000);

  /* ------------------------------------------------- scroll choreography */

  // reveals
  const io = new IntersectionObserver((entries, obs) => {
    entries.forEach(en => {
      if (!en.isIntersecting) return;
      en.target.classList.add('is-in');
      obs.unobserve(en.target);
    });
  }, { rootMargin: '0px 0px -12% 0px', threshold: .08 });

  document.querySelectorAll('.reveal').forEach((n, i) => {
    const group = n.closest('[data-stagger]');
    if (group && !n.style.getPropertyValue('--d')) {
      const kids = [...group.querySelectorAll('.reveal')];
      n.style.setProperty('--d', (kids.indexOf(n) * 90) + 'ms');
    }
    io.observe(n);
  });

  /* ----------------------------------------------------------- the show
   *
   * Everything on the first screen is a function of one number: how far you
   * are through the pinned section, 0 to 1. The title card, the bar sliding in
   * from the right edge, which description is up, what the panel is doing, and
   * the download button at the end all read off it, so the page can never be
   * caught in a state that does not match where you are.
   */

  const show = document.querySelector('.show');
  const pin = document.querySelector('.show-pin');
  const title = document.querySelector('.show-title');
  const copy = document.querySelector('.show-copy');
  const beats = [...document.querySelectorAll('.beat')];
  const getCard = document.querySelector('.show-get');

  /** 0 below `a`, 1 above `b`, smooth in between. */
  const ramp = (v, a, b) => {
    const t = Math.min(1, Math.max(0, (v - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };

  // where each description owns the screen, as a fraction of the section
  const BEATS = [[.17, .36], [.36, .55], [.55, .73], [.73, .88]];
  const actFor = [
    // at rest: a twelve-point sliver with the now-pill beside it
    () => { demo.reset(); swept = false; demo.setOpen(false); demo.setRange(1); },
    // open: the sliver stretches sideways into today's column
    () => { demo.setOpen(true); demo.setRange(1); },
    // the week: the bar widens and the calendar grows columns
    () => { demo.setOpen(true); demo.setRange(7); },
    // done: back to one day, then swipe the first deadline away
    () => {
      demo.setOpen(true);
      demo.setRange(1);
      if (!swept) { swept = true; window.setTimeout(() => demo.sweep(), 820); }
    }
  ];

  let swept = false, beat = -1;

  function runShow() {
    if (!show || !pin) return;
    const travel = show.offsetHeight - pin.offsetHeight;
    const p = travel > 0
      ? Math.min(1, Math.max(0, -show.getBoundingClientRect().top / travel))
      : 0;

    // the title card leaves before the bar arrives
    const gone = ramp(p, .02, .13);
    title.style.setProperty('--title-o', (1 - gone).toFixed(3));
    title.style.setProperty('--title-y', (gone * 60).toFixed(1));

    // the bar slides in from off the right edge, and leaves the same way
    const slide = ramp(p, .09, .19) * (1 - ramp(p, .95, 1));
    show.style.setProperty('--slide', slide.toFixed(3));

    // which description is up, and what the panel should be doing
    let next = p >= BEATS[3][1] ? 3 : -1;
    BEATS.forEach(([a, b], i) => { if (p >= a && p < b) next = i; });
    if (next >= 0 && next !== beat) {
      beat = next;
      beats.forEach((el, i) => el.classList.toggle('is-on', i === beat));
      if (demo) actFor[beat]();
    } else if (next < 0 && beat !== -1) {
      // scrolled back above the first description: put the bar away too, so it
      // slides back in as a sliver rather than mid-open
      beat = -1;
      beats.forEach(el => el.classList.remove('is-on'));
      if (demo) { demo.setOpen(false); demo.setRange(1); }
    }

    // the descriptions step aside for the download button
    const get = ramp(p, .88, .96);
    getCard.style.setProperty('--get-o', get.toFixed(3));
    getCard.classList.toggle('is-on', get > .5);
    copy.style.opacity = (1 - get).toFixed(3);
  }

  /* ------------------------------------------------------ the scroll loop */

  const nav = document.querySelector('.nav');

  function update() {
    if (nav) nav.classList.toggle('is-stuck', window.scrollY > 20);
    runShow();
  }

  // rAF-gate the scroll handler, but never let the gate latch: a tab that is
  // backgrounded mid-scroll stops servicing requestAnimationFrame, and a gate
  // still closed when it comes back would freeze the whole page.
  let ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; update(); });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll, { passive: true });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) return;
    ticking = false;
    update();
  });
  update();

  /* ---------------------------------------- keep every CTA on one version */

  const source = document.querySelector('.download .get');
  if (source) {
    document.querySelectorAll('[data-dl]').forEach(a => { a.href = source.getAttribute('href'); });
  }
  const metaSource = document.querySelector('.download .meta');
  if (metaSource) {
    document.querySelectorAll('[data-dl-meta]').forEach(p => { p.innerHTML = metaSource.innerHTML; });
  }

  /* ------------------------------------------------------------ the year */

  const year = document.querySelector('[data-year]');
  if (year) year.textContent = new Date().getFullYear();
})();
