// Prescription Explorer: the type-ahead search (spec section 5.4).
//
// A selectize input asks the server for matches as the user types: load()
// sends the text as a Shiny input, and the server answers with a custom
// message, "prexp-search-results", that hands the matches to selectize. The
// server ranks them, so each answer replaces the options of the last one and
// keeps the server's order. Fewer than two characters load nothing.
(function () {
  "use strict";

  // The selectize callback waiting for each query input's answer
  var waiting = {};

  window.prexpSearch = {
    load: function (selectize, inputId, query, callback) {
      selectize.clearOptions();
      selectize.loadedSearches = {};
      if (waiting[inputId]) {
        waiting[inputId]();
        delete waiting[inputId];
      }
      if (!query || query.trim().length < 2) {
        callback();
        return;
      }
      waiting[inputId] = callback;
      Shiny.setInputValue(inputId, query, { priority: "event" });
    }
  };

  $(document).on("shiny:connected", function () {
    Shiny.addCustomMessageHandler("prexp-search-results", function (message) {
      var callback = waiting[message.id];
      if (callback) {
        delete waiting[message.id];
        callback(message.options);
      }
    });
  });
})();
