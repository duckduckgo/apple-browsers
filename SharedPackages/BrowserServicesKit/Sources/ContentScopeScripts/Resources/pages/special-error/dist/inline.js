"use strict";
(() => {
  // pages/special-error/src/inline.js
  var param = new URLSearchParams(window.location.search).get("injectName");
  if (isAllowed(param)) {
    document.documentElement.dataset.platform = String(param);
  } else {
    document.documentElement.dataset.platform = "apple";
  }
  function isAllowed(input) {
    const allowed = ["windows", "apple", "integration"];
    return allowed.includes(input);
  }
})();
