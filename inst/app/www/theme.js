// The theme button (spec section 5.3): dark or light, as on katonometrica.com.
// The page's head sets the theme before the page is drawn (theme_script() in
// R/theme.R): dark, unless the visitor chose light before. A press switches
// it, keeps the choice in the browser's storage under "theme", and sets the
// button's glyph and label. No cookie; where storage is blocked the choice
// lasts until the page is left.
(function () {
  'use strict';

  function current() {
    return document.documentElement.getAttribute('data-bs-theme') === 'light' ? 'light' : 'dark';
  }

  // The glyph shows the theme; the label says what a press does
  function show(button) {
    var light = current() === 'light';
    button.textContent = light ? '\u25D1' : '\u25D0';
    button.setAttribute('aria-label', light ? 'Switch to dark theme' : 'Switch to light theme');
  }

  function init() {
    var button = document.getElementById('prexp-theme-toggle');
    if (!button) {
      return;
    }
    show(button);
    button.addEventListener('click', function () {
      var next = current() === 'light' ? 'dark' : 'light';
      document.documentElement.setAttribute('data-bs-theme', next);
      try {
        window.localStorage.setItem('theme', next);
      } catch (e) {
        // Storage blocked: the theme is not kept
      }
      show(button);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
