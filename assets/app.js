(function () {
  var C = window.BEAZA_CONFIG || {};
  var AR = window.BEAZA_AR || {};
  var root = document.documentElement;
  var EN = {};
  var EN_TITLE = document.title;
  document.querySelectorAll('[data-i18n]').forEach(function (el) { EN[el.getAttribute('data-i18n')] = el.textContent; });

  function store(l) { try { localStorage.setItem('beaza-lang', l); } catch (e) {} }

  function apply(lang) {
    var ar = lang === 'ar';
    root.lang = ar ? 'ar' : 'en';
    root.dir = ar ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var k = el.getAttribute('data-i18n');
      var v = ar ? AR[k] : EN[k];
      if (v != null) el.textContent = v;
    });
    var tk = document.body.getAttribute('data-title');
    var name = ar ? 'بيزة' : 'Beaza';
    if (tk) document.title = ar ? (AR[tk] || '') + ' · ' + name : EN_TITLE;
    var b = document.getElementById('langBtn');
    if (b) { b.setAttribute('lang', ar ? 'en' : 'ar'); }
    // keep ?lang in internal links so the choice survives when storage is blocked
    document.querySelectorAll('a[href$=".html"], a[href*=".html#"]').forEach(function (a) {
      var h = a.getAttribute('href').replace(/[?&]lang=(ar|en)/, '');
      var parts = h.split('#');
      a.setAttribute('href', parts[0] + (ar ? '?lang=ar' : '') + (parts[1] ? '#' + parts[1] : ''));
    });
  }

  var start = root.lang === 'ar' ? 'ar' : 'en';
  apply(start);

  var lb = document.getElementById('langBtn');
  if (lb) lb.addEventListener('click', function () {
    var next = root.lang === 'ar' ? 'en' : 'ar';
    store(next); apply(next);
    try { var u = new URL(location.href); if (next === 'ar') u.searchParams.set('lang', 'ar'); else u.searchParams.delete('lang'); history.replaceState(null, '', u); } catch (e) {}
  });

  var mb = document.getElementById('menuBtn');
  if (mb) mb.addEventListener('click', function () {
    var open = document.body.classList.toggle('nav-open');
    mb.setAttribute('aria-expanded', open ? 'true' : 'false');
  });

  // ---------- config bindings ----------
  document.querySelectorAll('[data-cfg-mail]').forEach(function (a) {
    if (!C.email) { a.parentElement && a.parentElement.tagName === 'LI' ? a.parentElement.remove() : a.remove(); return; }
    a.href = 'mailto:' + C.email; a.textContent = C.email;
  });
  document.querySelectorAll('[data-cfg-href]').forEach(function (a) {
    var v = C[a.getAttribute('data-cfg-href')];
    if (v) a.href = v; else if (a.getAttribute('data-cfg-href') === 'githubUrl') a.remove();
  });
  document.querySelectorAll('[data-cfg-li]').forEach(function (a) {
    var v = (C.linkedin || {})[a.getAttribute('data-cfg-li')];
    if (v) a.href = v; else { a.style.display = 'none'; var n = a.nextSibling; if (n && n.nodeName === 'BR') n.remove(); }
  });
  document.querySelectorAll('.info .row').forEach(function (r) {
    var ls = r.querySelectorAll('a[data-cfg-li]');
    if (ls.length && [].every.call(ls, function (a) { return a.style.display === 'none'; })) r.style.display = 'none';
  });
  var y = document.getElementById('yr'); if (y) y.textContent = new Date().getFullYear();

  // ---------- demo video ----------
  var vb = document.getElementById('videoBox');
  if (vb && C.videoUrl) {
    var url = C.videoUrl, id = null, m;
    if ((m = url.match(/youtu\.be\/([\w-]{6,})/)) || (m = url.match(/[?&]v=([\w-]{6,})/)) || (m = url.match(/youtube\.com\/(?:embed|shorts)\/([\w-]{6,})/))) id = m[1];
    if (id) {
      vb.innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/' + id + '" title="Beaza demo video" allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen loading="lazy"></iframe>';
    } else {
      vb.innerHTML = '<video controls preload="metadata" playsinline src="' + url.replace(/"/g, '') + '"></video>';
    }
    vb.classList.add('has-video');
  }

  // ---------- contact form ----------
  var f = document.getElementById('contactForm');
  if (f) f.addEventListener('submit', function (e) {
    e.preventDefault();
    var st = f.querySelector('.form-status');
    var ar = root.lang === 'ar';
    var msg = function (k, ok) { st.textContent = (ar ? AR[k] : EN[k]) || ''; st.className = 'form-status ' + (ok ? 'ok' : 'err'); };
    if (!f.checkValidity()) { f.reportValidity(); return; }
    if (f._gotcha && f._gotcha.value) return;
    var data = { name: f.name.value.trim(), email: f.email.value.trim(), message: f.message.value.trim() };
    if (C.formEndpoint) {
      var btn = f.querySelector('button'); btn.disabled = true;
      fetch(C.formEndpoint, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' }, body: JSON.stringify(data) })
        .then(function (r) { if (!r.ok) throw 0; f.reset(); msg('form.ok', true); })
        .catch(function () { msg('form.err', false); })
        .then(function () { btn.disabled = false; });
    } else if (C.email) {
      var body = data.message + '\n\n— ' + data.name + ' <' + data.email + '>';
      location.href = 'mailto:' + C.email + '?subject=' + encodeURIComponent('Beaza website: ' + data.name) + '&body=' + encodeURIComponent(body);
      msg('form.mail', true);
    } else { msg('form.err', false); }
  });
})();
