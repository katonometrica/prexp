// Prescription Explorer: the type-ahead search (spec section 5.4).
//
// A selectize input asks the server for matches as the user types: load()
// sends the text as a Shiny input, and the server answers with a custom
// message, "prexp-search-results", that hands the matches to selectize. The
// server ranks them, so each answer replaces the options of the last one and
// keeps the server's order. Each answer names the text it answers: one to
// older text, which can arrive after newer text was typed, is dropped, and
// the answer to the latest text follows it. Fewer than two characters load
// nothing, and clear the last search's message.
//
// Typing or pasting over a pick starts a new search. Holding its one pick, a
// single-pick selectize ignores keys and pastes, so a key that types a
// character, Shift+Insert or a paste first takes the pick out of the box,
// without telling Shiny: the view keeps showing it until another is picked,
// and leaving the box without one puts it back, without the search typed over
// it. Text that comes with no such key (an input method, a phone's keyboard,
// dictation) does the same as it starts. Backspace and the clear button still
// clear the pick, as before.
(function () {
  "use strict";

  // The load waiting for each query input's answer: its text and selectize's
  // callback
  var waiting = {};

  window.prexpSearch = {
    init: function (selectize, inputId) {
      var input = selectize.$control_input[0];
      // Takes the pick out of the box, silently, and keeps it to put back
      function free() {
        if (!selectize.items.length) {
          return;
        }
        var value = selectize.items[0];
        selectize.prexpKept = { value: value, option: selectize.options[value] };
        selectize.clear(true);
      }
      // All before selectize's own handlers, which drop keys and pastes while
      // it holds a pick, and would search text that comes with no key and
      // clear the pick, telling Shiny. Shift+Insert pastes on Windows and
      // Linux: selectize drops its key, so its paste would never come.
      input.addEventListener("keydown", function (event) {
        var key = event.key || "";
        if ((key.length === 1 || (key === "Insert" && event.shiftKey)) && !event.ctrlKey &&
            !event.metaKey && !event.altKey && !event.isComposing) {
          free();
        }
      }, true);
      input.addEventListener("paste", free, true);
      input.addEventListener("compositionstart", free, true);
      input.addEventListener("beforeinput", function (event) {
        if (/^insert/.test(event.inputType || "")) {
          free();
        }
      }, true);
      selectize.on("item_add", function () {
        delete selectize.prexpKept;
      });
      // Leaving the box without a new pick puts the pick back, without the
      // search typed over it: its matches, the answer it waits for, and its
      // message, which the server clears for text too short to search
      selectize.on("blur", function () {
        var kept = selectize.prexpKept;
        delete selectize.prexpKept;
        if (kept && kept.option && !selectize.items.length) {
          selectize.clearOptions(true);
          if (waiting[inputId]) {
            waiting[inputId].callback();
            delete waiting[inputId];
          }
          Shiny.setInputValue(inputId, "", { priority: "event" });
          selectize.addOption(kept.option);
          selectize.addItem(kept.value, true);
        }
      });
    },
    load: function (selectize, inputId, query, callback) {
      // A box that holds a pick does not search. Selectize asks for a search
      // loadThrottle (50 ms) after the last key, and by then leaving the box
      // can have put the pick back, or an option been picked, which
      // clearOptions() below would clear, telling Shiny. The text is not kept
      // as searched, so the same text, typed or pasted later, still searches.
      if (selectize.items.length) {
        selectize.loadedSearches = {};
        callback();
        return;
      }
      // Drop the last answer's options and redraw: selectize redraws on its
      // own only for an answer with options, so an empty one would leave the
      // old list open, its options dead
      selectize.clearOptions();
      selectize.refreshOptions(false);
      selectize.loadedSearches = {};
      if (waiting[inputId]) {
        waiting[inputId].callback();
        delete waiting[inputId];
      }
      if (!query || query.trim().length < 2) {
        callback();
        return;
      }
      waiting[inputId] = { query: query, callback: callback };
      Shiny.setInputValue(inputId, query, { priority: "event" });
    },
    typed: function (selectize, inputId, text) {
      // As in load(): never with a pick in the box
      if (selectize.items.length) {
        return;
      }
      if (!text || text.trim().length < 2) {
        selectize.clearOptions();
        selectize.refreshOptions(false);
        Shiny.setInputValue(inputId, text || "", { priority: "event" });
      }
    }
  };

  $(document).on("shiny:connected", function () {
    // A pick from a link: its option added to its box and selected, which
    // sends it as any pick is sent
    Shiny.addCustomMessageHandler("prexp-search-select", function (message) {
      var element = document.getElementById(message.id);
      var selectize = element && element.selectize;
      if (!selectize) {
        return;
      }
      selectize.addOption(message.option);
      selectize.setValue(message.option.value);
    });
    Shiny.addCustomMessageHandler("prexp-search-results", function (message) {
      var pending = waiting[message.id];
      if (pending && pending.query === message.query) {
        delete waiting[message.id];
        pending.callback(message.options);
      }
    });
  });
})();
