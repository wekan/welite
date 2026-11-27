// WeKan-Lite's own additions to Weddy's weddy.js in the HTML5 view, kept here
// so that Weddy's static files stay as Weddy ships them.
(function () {
  'use strict';
  if (!window.up) return;

  var searchBoard = null;
  var searchTerm = '';
  var searchCardId = null;
  var searchDirection = 1;
  var searchMatches = [];
  var searchRequest = 0;

  function setBoardSearch(sidebar, open) {
    var search = sidebar.querySelector('.js-board-search');
    if (!search) return;
    search.classList.toggle('is-hidden', !open);
    sidebar.querySelector('.js-board-sidebar-content').classList.toggle('is-hidden', open);
    if (open) sidebar.classList.add('is-open');
  }

  up.on('click', '.js-open-search-view', function (event, button) {
    event.preventDefault();
    var board = button.closest('.board-wrapper');
    var sidebar = board.querySelector('.board-sidebar');
    if (searchBoard !== board.dataset.board) {
      searchTerm = '';
      searchCardId = null;
      searchMatches = [];
    }
    searchBoard = board.dataset.board;
    setBoardSearch(sidebar, true);
    sidebar.querySelector('.js-board-search input').focus();
  });

  up.on('click', '.js-board-search .js-back-home', function (event, link) {
    event.preventDefault();
    var sidebar = link.closest('.board-sidebar');
    sidebar.querySelector('.js-close-sidebar').click();
    sidebar.closest('.board-wrapper').querySelector('.js-open-search-view').focus();
  });

  up.on('click', '.board-sidebar .js-close-sidebar, .js-open-filter-view, .js-toggle-page-sidebar', function (event, button) {
    var sidebar = document.querySelector('.board-sidebar');
    searchBoard = null;
    searchTerm = '';
    searchCardId = null;
    searchMatches = [];
    searchRequest++;
    if (sidebar) {
      setBoardSearch(sidebar, false);
      sidebar.closest('.board-wrapper').querySelectorAll('.is-search-highlight').forEach(function (card) {
        card.classList.remove('is-search-highlight');
      });
    }
  });

  up.on('keydown', '.js-board-search input', function (event) {
    if (event.key === 'Enter') searchDirection = event.shiftKey ? -1 : 1;
  });
  up.on('submit', '.js-board-search .js-search-term-form', function (event, form) {
    event.preventDefault();
    var term = form.elements.searchTerm.value.trim();
    var direction = searchDirection;
    searchDirection = 1;
    if (term === searchTerm) {
      renderBoardSearch(form, direction);
      return;
    }
    searchTerm = term;
    searchCardId = null;
    searchMatches = [];
    var request = ++searchRequest;
    renderBoardSearch(form);
    if (!term) return;
    var boardId = searchBoard;
    fetch('/b/' + encodeURIComponent(boardId) + '/search/matches?q=' + encodeURIComponent(term))
      .then(function (response) { return response.ok ? response.json() : []; })
      .then(function (matches) {
        if (request !== searchRequest || boardId !== searchBoard) return;
        var current = document.querySelector('.js-board-search .js-search-term-form');
        if (!current || current.closest('.board-wrapper').dataset.board !== boardId) return;
        searchMatches = matches;
        renderBoardSearch(current, direction);
      }).catch(function () { /* A failed search leaves the existing board visible. */ });
  });
  up.on('click', '.js-board-search .js-search-step', function (event, button) {
    renderBoardSearch(button.closest('.js-board-search').querySelector('form'), Number(button.dataset.direction));
  });

  up.compiler('.js-board-search', function (search) {
    if (searchBoard === null || search.closest('.board-wrapper').dataset.board !== searchBoard) return;
    setBoardSearch(search.closest('.board-sidebar'), true);
    var form = search.querySelector('form');
    form.elements.searchTerm.value = searchTerm;
    renderBoardSearch(form);
  });

  function renderBoardSearch(form, direction) {
    var term = searchTerm.toLocaleLowerCase();
    var results = form.parentElement.querySelector('.js-board-search-results');
    var counter = form.parentElement.querySelector('.search-step');
    var board = form.closest('.board-wrapper');
    var cards = [];
    results.replaceChildren();
    counter.classList.add('is-hidden');
    board.querySelectorAll('.is-search-highlight').forEach(function (card) { card.classList.remove('is-search-highlight'); });
    if (!term) return;
    function appendResult(title, href, isCard) {
      var item = document.createElement('li');
      var link = document.createElement('a');
      link.href = href;
      if (isCard) {
        link.className = 'minicard-wrapper js-minicard js-board-search-card';
        var preview = document.createElement('span');
        preview.className = 'minicard';
        var name = document.createElement('span');
        name.className = 'minicard-title';
        name.textContent = title;
        preview.append(name);
        link.append(preview);
        link.setAttribute('up-follow', '');
        link.setAttribute('up-target', '.board-wrapper');
      } else link.textContent = title;
      link.addEventListener('click', function () { form.closest('.board-sidebar').querySelector('.js-close-sidebar').click(); });
      item.append(link);
      results.append(item);
    }
    board.querySelectorAll('.board-canvas .list-header-name').forEach(function (title) {
      var list = title.closest('.list');
      if (list && list.id && title.textContent.toLocaleLowerCase().includes(term)) {
        appendResult(title.textContent, '#' + list.id, false);
      }
    });
    var visible = new Map();
    board.querySelectorAll('.board-canvas .minicard-wrapper').forEach(function (card) {
      visible.set(card.dataset.cardId, card);
    });
    searchMatches.forEach(function (match) {
      appendResult(match.title, match.url, true);
      if (visible.has(match.id)) cards.push(visible.get(match.id));
    });
    if (!cards.length) { searchCardId = null; return; }
    var index = cards.findIndex(function (card) { return card.dataset.cardId === searchCardId; });
    if (direction) {
      index = index < 0 ? (direction > 0 ? 0 : cards.length - 1) : (index + direction + cards.length) % cards.length;
    }
    if (index < 0) return;
    var chosen = cards[index];
    searchCardId = chosen.dataset.cardId;
    chosen.classList.add('is-search-highlight');
    if (direction) chosen.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    var caption = counter.querySelector('.js-search-step-count');
    caption.textContent = caption.dataset.caption.replace('%s', String(index + 1)).replace('%s', String(cards.length));
    counter.classList.remove('is-hidden');
  }

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
  up.on('click', '.js-close-mobile-list', function () {
    setCookie('welite-list', '');
    up.reload('.board-wrapper');
  });
  up.on('click', '.js-select-list', function (event, row) {
    event.preventDefault();
    setCookie('welite-list', encodeURIComponent(row.getAttribute('data-list') + ':' + row.getAttribute('data-swimlane')));
    up.reload('.board-wrapper');
  });
})();

// Member Settings / Date and Change Settings, and Board Settings / Date
// (WeKan's dateFormatSettings.js, userHeader.js changeSettingsPopup).
(function () {
  'use strict';
  if (!window.up) return;
  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    return window.Meteor.callAsync.apply(window.Meteor, [name].concat(args));
  }
  // A pop-over is a copy of its page template: what changes in it changes in
  // the template too, so it opens again as it was left.
  function inTemplate(pop, selector, change) {
    var t = document.querySelector('template.js-pop-over-template[data-pop="' + pop + '"]');
    if (t) t.content.querySelectorAll(selector).forEach(change);
  }
  function backTo(name) {
    var p = document.querySelector('.js-pop-over');
    if (p) p.dataset.back = name;
  }
  up.on('click', '.js-open-board-date-settings', function (event) {
    event.preventDefault();
    window.Popup.open('boardDateSettings')();
    backTo('board-menu');
  });
  // The member's Enabled / Disabled follows the box before Save.
  up.on('change', '.js-pop-over .js-date-format-form .js-date-format-override', function (event, box) {
    var text = box.form.querySelector('.js-member-date-format-enabled');
    if (text) text.textContent = box.checked ? text.dataset.enabled : text.dataset.disabled;
  });
  // The board's form saves setBoardDateFormat; weddy.js's handler is the
  // member's, and is not reached for it.
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!form.matches || !form.matches('.js-pop-over form.js-date-format-form[data-board]')) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (form.dataset.saving) return;
    form.dataset.saving = '1';
    var format = form.querySelector('.js-date-format-select').value, on = form.querySelector('.js-date-format-override').checked;
    var err = form.querySelector('.js-date-format-error');
    call('setBoardDateFormat', form.dataset.board, format, on).then(function () {
      inTemplate('board-date-settings', '.js-date-format-select option', function (o) {
        if (o.value === format) o.setAttribute('selected', ''); else o.removeAttribute('selected');
      });
      inTemplate('board-date-settings', '.js-date-format-override', function (b) {
        if (on) b.setAttribute('checked', ''); else b.removeAttribute('checked');
      });
      var wrapper = document.querySelector('.board-wrapper');
      return wrapper ? Promise.resolve(up.reload('.board-wrapper')).catch(function () {}) : null;
    }, function (e) { err.textContent = e.reason || e.message; err.hidden = false; throw e; })
      .then(function () { window.Popup.back(); }, function () {})
      .finally(function () { delete form.dataset.saving; });
  }, true);
  up.on('click', '.js-pop-over .js-show-week-of-year-toggle', function (event, el) {
    event.preventDefault();
    if (el.disabled) return;
    el.disabled = true;
    call('toggleShowWeekOfYear').then(function () {
      var on = !el.querySelector('.fa').classList.contains('fa-check');
      var flip = function (i) { i.classList.toggle('fa-check', on); i.classList.toggle('fa-square-o', !on); };
      flip(el.querySelector('.fa'));
      inTemplate('board-date-settings', '.js-show-week-of-year-toggle .fa', flip);
      return up.reload('.board-wrapper');
    }).finally(function () { el.disabled = false; });
  });
  up.on('click', '.js-pop-over .js-welite-setting', function (event, el) {
    event.preventDefault();
    var method = el.dataset.method;
    call(method).then(function () {
      var check = el.querySelector('.js-setting-check'), on = check.hidden;
      check.hidden = !on;
      inTemplate('change-settings', '[data-method="' + method + '"] .js-setting-check', function (c) {
        if (on) c.removeAttribute('hidden'); else c.setAttribute('hidden', '');
      });
      if (method === 'toggleKeepAddCardFormOpen') document.body.dataset.keepAddCardFormOpen = String(on);
      if (method === 'toggleHideFocusOutline') document.body.classList.toggle('has-hide-focus-outline', !on);
      // The drag handles are drawn on the board itself.
      if (method === 'toggleDesktopDragHandles' && document.querySelector('.board-wrapper')) up.reload('.board-wrapper');
    });
  });
})();

// Admin Panel / Settings / Appearance: each box toggles as it is clicked,
// the date section's Save writes its two fields (settingBody.js
// js-visibility-date-save).
(function () {
  'use strict';
  if (!window.up) return;
  up.on('click', '.admin-appearance .js-toggle-hide-logo, .admin-appearance .js-toggle-date-format', function (event, el) {
    event.preventDefault();
    el.querySelector('.materialCheckBox').classList.toggle('is-checked');
  });
  up.on('click', '.admin-appearance .js-visibility-date-save', function (event, el) {
    event.preventDefault();
    var pane = el.closest('.admin-appearance');
    window.Meteor.callAsync('/settings/update', { _id: pane.dataset.setting }, { $set: {
      hideDateFormat: pane.querySelector('#global-date-format-enabled').classList.contains('is-checked'),
      globalDateFormat: pane.querySelector('#global-date-format').value,
    } }).catch(function () {});
  });
  // A history entry a script pushed (WeKan's FlowRouter.go, a test's
  // navigateInApp): its page is drawn as a link to it would draw it. The
  // entries Unpoly makes are Unpoly's own.
  window.addEventListener('popstate', function (event) {
    if (event.state && event.state.up) return;
    up.render({ url: window.location.href, target: 'body', history: false }).catch(function () {});
  });
})();

// Meteor.loggingIn(), as WeKan's scripts and tests ask it: the HTML5 view's
// page is drawn signed in already, so it never is.
if (window.Meteor && !window.Meteor.loggingIn) window.Meteor.loggingIn = function () { return false; };

// #6902, One shared list header row: the swimlanes of such a board scroll
// sideways together (WeKan's sharedListRow.js installSharedSwimlaneScroll).
// What each was set to is remembered, so the scroll that setting fires is not
// passed on again - a shorter row would pull the others back to its limit.
(function () {
  if (document.__wekanSharedSwimlaneScroll) return;
  document.__wekanSharedSwimlaneScroll = true;
  var recent = new WeakMap();
  document.addEventListener('scroll', function (event) {
    var lane = event.target;
    if (!lane || typeof lane.matches !== 'function' || !lane.matches('.board-canvas.shared-list-headers .js-swimlane')) return;
    if (recent.has(lane)) {
      var expected = recent.get(lane);
      recent.delete(lane);
      if (expected === lane.scrollLeft) return;
    }
    lane.closest('.board-canvas').querySelectorAll('.js-swimlane').forEach(function (other) {
      if (other === lane || other.scrollLeft === lane.scrollLeft) return;
      other.scrollLeft = lane.scrollLeft;
      recent.set(other, other.scrollLeft);
    });
  }, { capture: true, passive: true });
})();

// Blaze.getData(element), as WeKan's scripts and tests read a list's or a
// card's document from its element: the HTML5 view has no Blaze, so the
// element's own id is the document's, from its data-list or data-card-id.
// Nothing else of the document is there, and none is invented.
if (!window.Blaze) {
  window.Blaze = {
    getData: function (el) {
      var id = el && el.dataset && (el.dataset.list || el.dataset.cardId);
      return id ? { _id: id } : null;
    },
  };
}

// A date pop-over opens with what stands now: its template was drawn with the
// page, and Admin Panel's or the board's format may have changed since.
(function () {
  'use strict';
  if (!window.up) return;
  function refresh(scope) {
    var wrapper = document.querySelector('.board-wrapper');
    var board = wrapper ? wrapper.getAttribute('data-board') || '' : '';
    var pop = scope === 'board' ? 'board-date-settings' : 'member-date-settings';
    fetch('/date-settings?scope=' + scope + '&board=' + encodeURIComponent(board), { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.text() : null; })
      .then(function (html) {
        if (html === null) return;
        var t = document.querySelector('template.js-pop-over-template[data-pop="' + pop + '"]');
        var open = document.querySelector('.js-pop-over[data-popup="' + (scope === 'board' ? 'boardDateSettingsPopup' : 'memberDateSettingsPopup') + '"] .content');
        [t && t.content.querySelector('.content'), open].forEach(function (box) {
          if (!box) return;
          var editor = document.createElement('div');
          editor.innerHTML = html;
          // Only the formats that stand elsewhere: the form is this pop-over's
          // own, saved through it, and is not swapped under the user.
          var now = editor.querySelector('.date-format-inherited'), was = box.querySelector(':scope > .date-format-inherited');
          if (now && was && now.innerHTML !== was.innerHTML) was.innerHTML = now.innerHTML;
        });
      }).catch(function () {});
  }
  up.on('click', '.js-member-date-settings', function () { setTimeout(function () { refresh('member'); }, 0); });
  up.on('click', '.js-open-board-date-settings', function () { setTimeout(function () { refresh('board'); }, 0); });

  // Member Settings / Change Avatar (WeKan's changeAvatarPopup): opened from
  // the member menu; a delete asks first (deleteAvatarPopup).
  up.on('click', '.js-change-avatar', function (event) {
    event.preventDefault();
    if (window.Popup) window.Popup.open('changeAvatar')();
  });
  up.on('click', '.js-delete-avatar', function (event, el) {
    if (!window.confirm(el.getAttribute('data-confirm') || '')) event.preventDefault();
  });
})();
