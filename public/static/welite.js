// WeKan-Lite's own additions to Weddy's weddy.js in the HTML5 view, kept here
// so that Weddy's static files stay as Weddy ships them.
(function () {
  'use strict';
  if (!window.up) return;

  // A card's Requested By and Assigned By (cardDetails.jade): Edit or Add
  // opens the field's inlined form, and its x closes it again.
  up.on('click', '.card-details-item-name .js-open-inlined-form', function (event, el) {
    event.preventDefault();
    var item = el.closest('.card-details-item-name');
    var form = item && item.querySelector('form.js-inlined-form');
    if (!form) return;
    form.classList.remove('is-hidden');
    var input = form.querySelector('input[type=text]');
    if (input) input.focus();
  });
  up.on('click', '.card-details-item-name .js-close-inlined-form', function (event, el) {
    event.preventDefault();
    var form = el.closest('form.js-inlined-form');
    if (form) form.classList.add('is-hidden');
  });

  // WeKan's EscapeActions for what weddy.js's Escape leaves open: the inline
  // Add List composer (#6865) and the card's Requested By and Assigned By
  // forms. A pop-over still closes first, as weddy.js does it.
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape' || document.querySelector('.js-pop-over')) return;
    document.querySelectorAll('.js-add-list-inline').forEach(function (n) { n.remove(); });
    document.querySelectorAll('.js-card-details .card-details-item-name form.js-inlined-form:not(.is-hidden)')
      .forEach(function (f) { f.classList.add('is-hidden'); });
  });
  // WeKan's comment editor @ mention (client/components/main/editor.js,
  // client/lib/textComplete.js, #6704): typing @ and part of a board
  // member's username or full name - any case - opens .textcomplete-dropdown
  // above the card; a click, Enter or Tab puts "@username (Full Name) " in
  // place of what was typed, and Enter then does not send the comment.
  var mention = null;
  function mentionClose() {
    if (mention) mention.menu.remove();
    mention = null;
  }
  function mentionMembers(editor) {
    try { return JSON.parse(editor.getAttribute('data-mentions') || '[]'); } catch (e) { return []; }
  }
  function mentionText(m) { return m.f ? '@' + m.u + ' (' + m.f + ') ' : '@' + m.u + ' '; }
  function mentionPick(index) {
    var at = mention, m = at && at.items[index];
    if (!m) return;
    var editor = at.editor, end = editor.selectionEnd, value = editor.value;
    var start = end - at.typed.length;
    editor.value = value.slice(0, start) + mentionText(m) + value.slice(end);
    var caret = start + mentionText(m).length;
    editor.setSelectionRange(caret, caret);
    mentionClose();
    editor.focus();
    editor.dispatchEvent(new Event('input', { bubbles: true }));
  }
  function mentionActive(index) {
    mention.active = index;
    Array.prototype.forEach.call(mention.menu.children, function (li, i) { li.classList.toggle('active', i === index); });
  }
  function mentionUpdate(editor) {
    var before = editor.value.slice(0, editor.selectionEnd);
    var found = /(^|[^\w])(@([\w.-]*))$/.exec(before);
    if (!found || editor.selectionStart !== editor.selectionEnd) return mentionClose();
    var term = found[3].toLowerCase();
    var items = mentionMembers(editor).filter(function (m) {
      return String(m.u || '').toLowerCase().indexOf(term) > -1 || String(m.f || '').toLowerCase().indexOf(term) > -1;
    });
    mentionClose();
    if (!items.length) return;
    var menu = document.createElement('ul');
    menu.className = 'dropdown-menu textcomplete-dropdown';
    items.forEach(function (m, i) {
      var li = document.createElement('li'), span = document.createElement('span');
      li.className = 'textcomplete-item';
      span.textContent = m.f ? m.f + ' (' + m.u + ')' : m.u;
      li.appendChild(span);
      // Pressing keeps the editor focused; the click then picks.
      li.addEventListener('mousedown', function (e) { e.preventDefault(); });
      li.addEventListener('click', function (e) { e.preventDefault(); mentionPick(i); });
      menu.appendChild(li);
    });
    var r = editor.getBoundingClientRect();
    menu.style.position = 'fixed';
    menu.style.left = Math.max(0, r.left) + 'px';
    menu.style.top = Math.min(r.bottom, window.innerHeight - 40) + 'px';
    document.body.appendChild(menu);
    mention = { editor: editor, items: items, typed: found[2], menu: menu, active: 0 };
    mentionActive(0);
  }
  document.addEventListener('input', function (event) {
    var editor = event.target;
    if (editor && editor.tagName === 'TEXTAREA' && editor.hasAttribute('data-mentions')) mentionUpdate(editor);
  });
  document.addEventListener('focusout', function (event) {
    if (mention && event.target === mention.editor) mentionClose();
  });
  // Before weddy.js's submit on Enter and Escape: while the menu is open its
  // keys are the menu's.
  document.addEventListener('keydown', function (event) {
    if (!mention || event.target !== mention.editor || event.isComposing) return;
    var n = mention.items.length;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') mentionActive((mention.active + (event.key === 'ArrowDown' ? 1 : n - 1)) % n);
    else if (event.key === 'Enter' || event.key === 'Tab') mentionPick(mention.active);
    else if (event.key === 'Escape') mentionClose();
    else return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);
  up.on('up:fragment:inserted', function () {
    if (mention && !document.contains(mention.editor)) mentionClose();
  });
  // Member Settings' Change Language (WeKan's changeLanguagePopup): the
  // member menu's link fetches the languages and opens them as weddy.js
  // opens a pop-over; a language chosen is setLanguage, and the page is
  // drawn again in it.
  function showPopOver(t) {
    document.querySelectorAll('.js-pop-over').forEach(function (n) { n.remove(); });
    var p = document.createElement('div');
    p.className = 'pop-over js-pop-over';
    p.setAttribute('role', 'dialog');
    p.setAttribute('aria-label', t.getAttribute('data-title') || '');
    if (t.dataset.popup) p.setAttribute('data-popup', t.dataset.popup);
    p.appendChild(t.content.cloneNode(true));
    document.body.appendChild(p);
    up.hello(p);
  }
  up.on('click', '.js-change-language', function (event, link) {
    event.preventDefault();
    fetch(link.getAttribute('href'), { credentials: 'same-origin' }).then(function (r) {
      return r.ok ? r.text() : '';
    }).then(function (html) {
      var box = document.createElement('div');
      box.innerHTML = html;
      var t = box.querySelector('template.js-pop-over-template[data-pop="change-language"]');
      if (t) showPopOver(t);
    }).catch(function () {});
  });
  up.on('click', '.js-set-language', function (event, link) {
    event.preventDefault();
    if (window.Meteor) window.Meteor.callAsync('setLanguage', link.getAttribute('data-language')).catch(function () {});
  });
  // WeKan's preferredLanguage: with no language chosen, the page is in the
  // browser's own (navigator.languages), which only the page knows - kept in
  // the welite-languages cookie for the server, and the page drawn again in
  // it once when the list changed. Nothing is saved in the profile.
  (function () {
    if (document.documentElement.getAttribute('data-language-source') !== 'browser') return;
    var list = [].concat(navigator.languages || [], navigator.language || [], navigator.userLanguage || [])
      .filter(function (v) { return typeof v === 'string' && /^[A-Za-z0-9@_-]{1,35}$/.test(v); }).slice(0, 20).join(',');
    var now = (document.cookie.match(/(?:^|;\s*)welite-languages=([^;]*)/) || [])[1];
    var want = encodeURIComponent(list);
    if (!list || now === want) return;
    document.cookie = 'welite-languages=' + want + '; path=/; max-age=31536000; samesite=lax';
    // WeKan's matchBrowserLanguage over the tags the server has: drawn again
    // only when that is another language than the page's.
    var tags = (document.documentElement.getAttribute('data-language-tags') || '').split(' ');
    var norm = function (t) { return String(t).toLowerCase().replace(/[_@]/g, '-'); };
    var aliases = { vep: 've-PP', vec: 've-CC', vls: 'vl-SS', war: 'wa-RR', 'es-419': 'es-LA', 'be-by': 'be-BE',
      'uz-arab': 'uz-AR', 'uz-latn': 'uz-LA', iw: 'he', ji: 'yi', 'in': 'id', no: 'nb', yue: 'yue_CN', wuu: 'wuu-Hans', 'zh-mo': 'zh-Hant' };
    var find = function (t) { for (var i = 0; i < tags.length; i++) if (tags[i] && norm(tags[i]) === norm(t)) return tags[i]; return ''; };
    var match = function (value) {
      var c = value.replace(/[_@]/g, '-');
      while (c) {
        var hit = find(c) || (aliases[c.toLowerCase()] && find(aliases[c.toLowerCase()]));
        if (hit) return hit;
        var cut = c.lastIndexOf('-');
        c = cut > 0 ? c.slice(0, cut) : '';
      }
      return '';
    };
    var chosen = '';
    list.split(',').some(function (v) { chosen = match(v); return !!chosen; });
    if (!chosen || norm(chosen) === norm(document.documentElement.getAttribute('lang') || '')) return;
    try {
      if (sessionStorage.getItem('welite-languages-reload') === want) return;
      sessionStorage.setItem('welite-languages-reload', want);
    } catch (e) { /* no storage: one reload still */ }
    window.location.reload();
  })();
  // WeKan's mobile view (isMiniScreen): the server draws a swimlane's lists
  // as compact rows when weddy.js has put the page in mobile mode, told in
  // the welite-mobile cookie; the page is drawn again once when it differs,
  // and at each mobile/desktop toggle. A row opens its list in its own
  // swimlane (Session currentList, the welite-list cookie).
  function cookie(name) { return (document.cookie.match(new RegExp('(?:^|;\\s*)' + name + '=([^;]*)')) || [])[1] || ''; }
  function setCookie(name, value) { document.cookie = name + '=' + value + '; path=/; max-age=31536000; samesite=lax'; }
  // No cookie is desktop, as the server draws it.
  function drawnMobile() { return cookie('welite-mobile') === '1' ? '1' : '0'; }
  function syncMobile(reload) {
    var on = document.body.classList.contains('mobile-mode') ? '1' : '0';
    if (drawnMobile() === on) return;
    setCookie('welite-mobile', on);
    if (reload && document.querySelector('.board-wrapper')) up.reload('.board-wrapper');
  }
  // A compiler runs after weddy.js's, which decides the mode, on each board drawn.
  up.compiler('.board-wrapper', function () {
    var before = drawnMobile();
    syncMobile(false);
    if (before !== drawnMobile()) setTimeout(function () { up.reload('.board-wrapper'); }, 0);
  });
  up.on('click', '.js-mobile-mode-toggle', function () { setTimeout(function () { syncMobile(true); }, 0); });
  up.on('click', '.js-select-list', function (event, row) {
    event.preventDefault();
    setCookie('welite-list', encodeURIComponent(row.getAttribute('data-list') + ':' + row.getAttribute('data-swimlane')));
    up.reload('.board-wrapper');
  });
})();
