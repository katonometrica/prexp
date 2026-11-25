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
(function () {
  "use strict";

  // The load waiting for each query input's answer: its text and selectize's
  // callback
  var waiting = {};

  window.prexpSearch = {
    load: function (selectize, inputId, query, callback) {
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
