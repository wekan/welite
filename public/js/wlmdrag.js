/* Optional card movement. The ordinary checkbox/arrow form remains usable. */
(function () {
  'use strict';
  if (!window.interact || !window.fetch || !window.FormData || !window.DOMParser) return;
  var form = document.querySelector('form[action="/board/move"]');
  if (!form) return;
  var active = new Map(), queue = [], busy = false, changed = false, failed = false;
  var status = document.createElement('p');
  status.setAttribute('role', 'status');
  form.appendChild(status);
  function settle() {
    if (!busy && !queue.length && !active.size && changed && !failed) window.location.reload();
  }
  function pump() {
    if (busy || failed || !queue.length) { settle(); return; }
    busy = true;
    var job = queue.shift(), data = new URLSearchParams();
    form.querySelectorAll('input[type=hidden]').forEach(function (input) { data.append(input.name, input.value); });
    data.set('dir', 'drop');
    data.set('targetList', job.list);
    data.set('targetLane', job.lane);
    job.ids.forEach(function (id) { data.append('sel_card', id); });
    fetch(form.getAttribute('action'), { method: 'POST', body: data, credentials: 'omit', redirect: 'follow' })
      .then(function (response) {
        if (!response.ok) throw new Error('Move refused (' + response.status + '). Reload before trying again.');
        return response.text();
      }).then(function (html) {
        var next = new DOMParser().parseFromString(html, 'text/html').querySelector('form[action="/board/move"]');
        if (!next) throw new Error('Session changed. Reload before trying again.');
        form.querySelectorAll('input[type=hidden]').forEach(function (input) {
          var replacement = Array.from(next.elements).find(function (item) { return item.name === input.name; });
          if (replacement) input.value = replacement.value;
        });
        changed = true; status.textContent = 'Cards moved.';
      }).catch(function (error) {
        failed = true; queue = []; status.textContent = error.message;
      }).finally(function () { busy = false; pump(); });
  }
  interact.maxInteractions(Infinity);
  form.querySelectorAll('.draggable[data-kind="card"]').forEach(function (card) {
    card.style.touchAction = 'none'; card.style.userSelect = 'none';
  });
  interact('form[action="/board/move"] .draggable[data-kind="card"]').draggable({
    inertia: false, autoScroll: true, ignoreFrom: 'input,button,a',
    listeners: {
      start: function (event) {
        if (failed) return;
        var card = event.target, checkbox = card.querySelector('input[name=sel_card]');
        var ids = checkbox && checkbox.checked ? Array.from(form.querySelectorAll('input[name=sel_card]:checked')).map(function (item) { return item.value; }) : [card.dataset.id];
        // Simultaneous fingers own disjoint selections; never submit the same card twice.
        var claimed = new Set(); active.forEach(function (job) { job.ids.forEach(function (id) { claimed.add(id); }); });
        ids = ids.filter(function (id) { return !claimed.has(id); });
        active.set(card, { ids: ids, x: 0, y: 0 });
        card.style.position = 'relative'; card.style.zIndex = '1';
      },
      move: function (event) {
        var job = active.get(event.target); if (!job) return;
        job.x += event.dx; job.y += event.dy;
        event.target.style.transform = 'translate(' + job.x + 'px,' + job.y + 'px)';
      },
      end: function (event) {
        event.target.style.transform = ''; event.target.style.zIndex = '';
        active.delete(event.target); pump();
      }
    }
  });
  interact('form[action="/board/move"] td[data-list][data-lane]').dropzone({
    accept: '.draggable[data-kind="card"]', overlap: 'pointer',
    ondrop: function (event) {
      var job = active.get(event.relatedTarget);
      if (!job || !job.ids.length || failed) return;
      queue.push({ ids: job.ids, list: event.target.dataset.list, lane: event.target.dataset.lane });
      status.textContent = 'Moving cards...'; pump();
    }
  });
}());
