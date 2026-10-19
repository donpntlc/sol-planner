// Übergangs-Shim für alte, noch zwischengespeicherte index.html: lädt die neueste Version.
(function () {
  if (!document.getElementById('flutter_host')) {
    var st = document.createElement('style');
    st.textContent = '#flutter_host{position:fixed;inset:0}';
    document.head.appendChild(st);
    var h = document.createElement('div');
    h.id = 'flutter_host';
    document.body.appendChild(h);
  }
  fetch('/sol-planner/latest.json?t=' + Date.now(), { cache: 'no-store' })
    .then(function (r) { return r.json(); })
    .then(function (j) {
      var old = document.querySelector('base');
      if (old) old.href = j.base; else { var b = document.createElement('base'); b.href = j.base; document.head.appendChild(b); }
      var s = document.createElement('script');
      s.src = j.base + 'flutter_bootstrap.js';
      document.body.appendChild(s);
    });
})();
