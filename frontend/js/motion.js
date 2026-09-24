// ---------------------------------------------------------------------------
// "Reduce motion" toggle — plain script (not a module) so it runs before
// anything else and works even if a module fails to load. Mirrors the
// design reference's escape hatch for the animated background/effects,
// on top of the automatic prefers-reduced-motion support already in CSS.
// Preference is remembered per-browser via localStorage.
// ---------------------------------------------------------------------------
(function () {
  var KEY = "uno_reduce_motion";
  var btn = document.getElementById("motion-toggle");

  function apply(reduced) {
    document.body.classList.toggle("reduce-motion", reduced);
    if (btn) {
      btn.setAttribute("aria-pressed", String(reduced));
      btn.textContent = reduced ? "Enable motion" : "Reduce motion";
    }
  }

  var saved = null;
  try {
    saved = localStorage.getItem(KEY);
  } catch (e) {
    // localStorage unavailable (private mode, etc) — fall back to CSS's
    // own prefers-reduced-motion handling only.
  }
  if (saved === "1") apply(true);

  if (btn) {
    btn.addEventListener("click", function () {
      var reduced = !document.body.classList.contains("reduce-motion");
      apply(reduced);
      try {
        localStorage.setItem(KEY, reduced ? "1" : "0");
      } catch (e) {
        /* ignore */
      }
    });
  }
})();
