/*
 * Full screen: one Esc press exits it in every browser (loaded by client-patch/apply.sh).
 * Neko locks the keyboard when it goes full screen (Keyboard Lock API, Chrome/Edge only), which
 * turns exiting into "press and hold Esc". Skipping that lock gives Chrome/Edge the same plain-Esc
 * behaviour as Safari and Firefox; shortcuts then work in full screen just as they do in a window.
 */
(() => {
  try {
    if (navigator.keyboard && typeof navigator.keyboard.lock === "function") {
      navigator.keyboard.lock = () => Promise.resolve();
    }
  } catch (_) {}
})();
