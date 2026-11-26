// The header (spec section 5.3): katonometrica.com's bar over the app's tabs,
// with the site's behaviour, from its script.js (initNavbarScroll() and
// initMobileMenu()), under the prefix kat- that its classes take here.
//
// - Once the page has scrolled more than 50 px, the header takes the class
//   kat-scrolled: the site's translucent background, a blur and a rule under
//   it (prexp.css).
// - Below 900 px the hamburger opens the site's drawer: its links and, at its
//   foot, the theme button and Book a call, over a backdrop. The focus goes
//   into the drawer and stays there while it is open. The button, Escape, the
//   backdrop or a click outside close it, and the focus goes back to the
//   button.
// - The header's height is kept in --prexp-header-height, by which the page
//   scrolls what takes the keyboard's focus clear of the header.
// - Where the tabs scroll sideways, on a phone, the open one is kept in view.
(function () {
  'use strict';

  // The site's: the scroll at which the header takes its background, and the
  // widest screen with the drawer
  var SCROLLED = 50;
  var DRAWER = 900;

  function initNavbarScroll(header) {
    function update() {
      header.classList.toggle('kat-scrolled', window.scrollY > SCROLLED);
    }
    window.addEventListener('scroll', update, { passive: true });
    // A page opened part-way down, as a reload can leave it, starts scrolled
    update();
  }

  function initHeaderHeight(header) {
    function update() {
      document.documentElement.style.setProperty(
        '--prexp-header-height', header.offsetHeight + 'px'
      );
    }
    if (window.ResizeObserver) {
      new window.ResizeObserver(update).observe(header);
    } else {
      window.addEventListener('resize', update);
    }
    update();
  }

  function initMobileMenu() {
    var button = document.getElementById('kat-nav-toggle');
    var menu = document.getElementById('kat-nav-menu');
    // On a phone the drawer is two elements: the links (.kat-nav-menu) and,
    // under them, the actions (.kat-nav-actions: the theme button and Book a
    // call)
    var actions = document.getElementById('kat-nav-actions');
    var backdrop = document.getElementById('kat-nav-menu-backdrop');
    if (!button || !menu) {
      return;
    }
    var trapKeydown = null;

    function isOpen() {
      return menu.classList.contains('kat-active');
    }

    function inDrawer(el) {
      return menu.contains(el) || (actions !== null && actions.contains(el));
    }

    // The drawer's controls that can take the focus, in the order Tab reaches
    // them, then the button, so that the keyboard can close it too. Hidden
    // ones are skipped, or the wrap breaks.
    function focusables() {
      var sel = 'a[href], button:not([disabled]), select, [tabindex]:not([tabindex="-1"])';
      var els = Array.prototype.slice.call(menu.querySelectorAll(sel));
      if (actions) {
        els = els.concat(Array.prototype.slice.call(actions.querySelectorAll(sel)));
      }
      els.push(button);
      return els.filter(function (el) {
        return el.getClientRects().length > 0;
      });
    }

    function trapFocus() {
      // Two frames on: the drawer was hidden (visibility), and where motion
      // is reduced its links are still hidden in this frame, so a focus now
      // would be ignored
      window.requestAnimationFrame(function () {
        window.requestAnimationFrame(function () {
          var els = focusables();
          if (isOpen() && els.length) {
            els[0].focus();
          }
        });
      });
      trapKeydown = function (e) {
        if (e.key !== 'Tab') {
          return;
        }
        var els = focusables();
        if (!els.length) {
          return;
        }
        var first = els[0];
        var last = els[els.length - 1];
        var inside = els.indexOf(document.activeElement) !== -1;
        if (e.shiftKey && (document.activeElement === first || !inside)) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && (document.activeElement === last || !inside)) {
          e.preventDefault();
          first.focus();
        }
      };
      document.addEventListener('keydown', trapKeydown);
    }

    function releaseFocus() {
      if (trapKeydown) {
        document.removeEventListener('keydown', trapKeydown);
        trapKeydown = null;
      }
    }

    function open() {
      menu.classList.add('kat-active');
      button.classList.add('kat-active');
      if (backdrop) {
        backdrop.classList.add('kat-active');
      }
      button.setAttribute('aria-expanded', 'true');
      document.body.style.overflow = 'hidden';
      trapFocus();
    }

    // Closes the drawer; with refocus, the focus goes back to the button
    function close(refocus) {
      menu.classList.remove('kat-active');
      button.classList.remove('kat-active');
      if (backdrop) {
        backdrop.classList.remove('kat-active');
      }
      button.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = '';
      releaseFocus();
      if (refocus) {
        button.focus();
      }
    }

    button.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (isOpen()) {
        close(true);
      } else {
        open();
      }
    });
    if (backdrop) {
      backdrop.addEventListener('click', function () {
        close(true);
      });
    }
    // A click outside the drawer closes it. Its actions count as inside.
    document.addEventListener('click', function (e) {
      if (isOpen() && !inDrawer(e.target) && !button.contains(e.target)) {
        close(true);
      }
    });
    // A link in the drawer closes it as the page goes
    [menu, actions].forEach(function (part) {
      if (!part) {
        return;
      }
      Array.prototype.forEach.call(part.querySelectorAll('a[href]'), function (link) {
        link.addEventListener('click', function () {
          if (isOpen()) {
            close(false);
          }
        });
      });
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && isOpen()) {
        close(true);
      }
    });
    // Wider than a phone, the drawer is gone: the links are in the bar
    window.addEventListener('resize', function () {
      if (window.innerWidth > DRAWER && isOpen()) {
        close(false);
      }
    });
  }

  // The tabs' strip scrolls sideways where the tabs do not fit: the open tab
  // is brought into view when it changes, by a click, the arrow keys (which
  // move the focus without scrolling) or a bookmark, and when the width does
  function initTabStrip(header) {
    var strip = header.querySelector('.prexp-app-nav .navbar-nav');
    if (!strip) {
      return;
    }
    function reveal() {
      var tab = strip.querySelector('.nav-link.active');
      if (!tab || strip.scrollWidth <= strip.clientWidth) {
        return;
      }
      var pad = parseFloat(window.getComputedStyle(strip).paddingLeft) || 0;
      var box = strip.getBoundingClientRect();
      var at = tab.getBoundingClientRect();
      if (at.left < box.left + pad) {
        strip.scrollLeft -= box.left + pad - at.left;
      } else if (at.right > box.right - pad) {
        strip.scrollLeft += at.right - (box.right - pad);
      }
    }
    document.addEventListener('shown.bs.tab', reveal);
    window.addEventListener('resize', reveal);
    reveal();
  }

  function init() {
    var header = document.getElementById('kat-navbar');
    if (!header) {
      return;
    }
    initNavbarScroll(header);
    initHeaderHeight(header);
    initMobileMenu();
    initTabStrip(header);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
