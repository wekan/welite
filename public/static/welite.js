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
})();
