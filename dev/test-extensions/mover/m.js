// test-only: after 15 s, sweep the mouse left to right across Neko's video, 45% down
setTimeout(() => {
  let i = 0;
  setInterval(() => {
    const el = document.querySelector(".player-container .overlay");
    if (!el) return;
    const r = el.getBoundingClientRect();
    const x = r.left + r.width * (0.25 + 0.5 * ((i++ % 40) / 40));
    el.dispatchEvent(new MouseEvent("mousemove", { clientX: x, clientY: r.top + r.height * 0.45, bubbles: true }));
  }, 150);
}, 15000);
