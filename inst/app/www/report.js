// The report panel (P5-02). Its buttons and notes carry their item's id, so
// one input of the module tells the server what changed: `act` for a move or
// a removal, `note` for a note.
// - A note is sent after a pause in typing, and at once when its box loses
//   the focus or a button of the panel is pressed, so a move or a removal
//   always reaches the server after the latest text, even text typed back to
//   what the box held, which fires no change event.
// - Its counter counts characters as the server does, not UTF-16 units, and
//   turns red past the limit, which the server refuses.
// - A move or a removal draws the list again, which takes the focus from the
//   button pressed, so once the list is drawn the focus goes back: to the same
//   button of the item moved, or to its other move button once it is first or
//   last; after a removal, to the title of the item in its place, or of the
//   new last item, or to the empty panel's text.
// - What a change did is said by the page's status region (#prexp-status),
//   emptied first so that the same words twice are read twice.
// - The report's link, from the Copy link button: copied with the browser's
//   clipboard and shown in the box under the button, its text selected to
//   copy by hand where the browser will not copy it (an address without
//   HTTPS, or a denied permission).
(function () {
  'use strict';
  var pause = 400;
  var timers = {};
  // The boxes typed in whose note is still to be sent, by item id
  var pending = {};
  // The button last pressed, for the focus once the list is drawn again
  var pressed = null;
  var watched = [];

  function characters(text) {
    return Array.from(text).length;
  }

  function sendNote(box) {
    var id = box.dataset.reportId;
    clearTimeout(timers[id]);
    delete timers[id];
    delete pending[id];
    if (!window.Shiny || !window.Shiny.setInputValue) {
      return;
    }
    window.Shiny.setInputValue(box.dataset.reportInput, {
      id: Number(id),
      note: box.value
    }, { priority: 'event' });
  }

  function sendPending() {
    Object.keys(pending).forEach(function (id) {
      sendNote(pending[id]);
    });
  }

  // Only when the focus was lost, so a list drawn again while the focus is
  // elsewhere, as on a pin from another tab, takes nothing. `pressed` is kept
  // until the next press, so a second press before the first redraw still
  // gets its focus back.
  function refocus(list) {
    var active = document.activeElement;
    if (!pressed || pressed.list !== list || (active && active !== document.body)) {
      return;
    }
    var target = null;
    if (pressed.act !== 'remove') {
      var acts = pressed.act === 'up' ? ['up', 'down'] : ['down', 'up'];
      for (var i = 0; i < acts.length && !target; i++) {
        var button = list.querySelector('button[data-report-id="' + pressed.id +
          '"][data-report-act="' + acts[i] + '"]');
        if (button && !button.disabled) {
          target = button;
        }
      }
    }
    if (!target) {
      var items = list.querySelectorAll('.prexp-report-item');
      var item = items[Math.min(pressed.index, items.length - 1)];
      target = item ? item.querySelector('h2') : list.querySelector('[tabindex="-1"]');
    }
    if (target) {
      target.focus();
    }
  }

  function watch(list) {
    if (watched.indexOf(list) >= 0) {
      return;
    }
    watched.push(list);
    new MutationObserver(function () {
      refocus(list);
    }).observe(list, { childList: true });
  }

  document.addEventListener('click', function (event) {
    var button = event.target.closest('button[data-report-act]');
    if (!button || button.disabled || !window.Shiny || !window.Shiny.setInputValue) {
      return;
    }
    hideLink();
    sendPending();
    var list = button.closest('.shiny-html-output');
    var item = button.closest('.prexp-report-item');
    if (list && item) {
      watch(list);
      pressed = {
        list: list,
        id: button.dataset.reportId,
        act: button.dataset.reportAct,
        index: Array.prototype.indexOf.call(list.querySelectorAll('.prexp-report-item'), item)
      };
    }
    window.Shiny.setInputValue(button.dataset.reportInput, {
      id: Number(button.dataset.reportId),
      act: button.dataset.reportAct
    }, { priority: 'event' });
  });

  document.addEventListener('input', function (event) {
    var box = event.target.closest('textarea[data-report-input]');
    if (!box) {
      return;
    }
    hideLink();
    var counter = document.getElementById(box.dataset.reportCounter);
    if (counter) {
      var n = characters(box.value);
      var count = counter.querySelector('.prexp-note-count');
      if (count) {
        count.textContent = n;
      }
      counter.classList.toggle('text-danger', n > Number(box.dataset.reportLimit));
    }
    var id = box.dataset.reportId;
    clearTimeout(timers[id]);
    pending[id] = box;
    timers[id] = setTimeout(function () {
      sendNote(box);
    }, pause);
  });

  document.addEventListener('focusout', function (event) {
    var box = event.target.closest && event.target.closest('textarea[data-report-input]');
    if (box && pending[box.dataset.reportId] === box) {
      sendNote(box);
    }
  });

  function say(text) {
    var region = document.getElementById('prexp-status');
    if (!region) {
      return;
    }
    region.textContent = '';
    setTimeout(function () {
      region.textContent = text;
    }, 100);
  }

  // The link shown is the report and the view as they were: a note, a move
  // or a removal here, or another tab, where pins and a view's selections
  // change, makes it stale, so it is hidden until Copy link is pressed again
  function hideLink() {
    var input = document.querySelector('input[data-report-link]');
    if (!input) {
      return;
    }
    input.value = '';
    input.closest('.prexp-link-box').hidden = true;
  }

  function showLink(url, copied) {
    var input = document.querySelector('input[data-report-link]');
    if (!input) {
      return;
    }
    var box = input.closest('.prexp-link-box');
    var label = box.querySelector('[data-report-link-label]');
    input.value = url;
    box.hidden = false;
    if (copied) {
      label.textContent = 'Copied: the report\'s link';
      say('Link copied.');
    } else {
      label.textContent = 'The report\'s link: copy it from here';
      input.focus();
      input.select();
      say('The link could not be copied: it is selected in the box below the button.');
    }
  }

  $(document).on('shiny:inputchanged', function (event) {
    if (event.name === 'tab') {
      hideLink();
    }
  });

  $(document).on('shiny:connected', function () {
    window.Shiny.addCustomMessageHandler('prexp-status', say);
    window.Shiny.addCustomMessageHandler('prexp-copy-link', function (url) {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(url).then(function () {
          showLink(url, true);
        }, function () {
          showLink(url, false);
        });
      } else {
        showLink(url, false);
      }
    });
  });
})();
