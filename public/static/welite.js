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
})();
