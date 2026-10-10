// test-only: click Neko's take-control button __CLICK_MS__ ms after load (0 = never)
if (__CLICK_MS__ > 0) setTimeout(() => document.querySelector("i.fa-keyboard.request")?.click(), __CLICK_MS__);
