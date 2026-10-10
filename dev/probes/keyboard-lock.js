// probe: is Neko's full-screen keyboard lock switched off (client-patch/www/fullscreen.js)?
// Needs a secure context (https or localhost), otherwise navigator.keyboard doesn't exist.
setTimeout(() => {
  const kb = navigator.keyboard;
  const replaced = !!kb && kb.lock !== Object.getPrototypeOf(kb).lock;
  document.documentElement.dataset.result = `keyboard-api=${!!kb} lock-replaced=${replaced}`;
}, 3000);
