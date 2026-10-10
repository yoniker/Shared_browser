// probe: does a control change (chat entry of type "event") still play chat.mp3? A normal chat
// message should, as a control. Result: "event=N text=M" (expected event=0 text=1).
(() => {
  let n = 0;
  const Native = window.Audio;
  window.Audio = function (...a) { if (String(a[0]).includes("chat.mp3")) n++; return new Native(...a); };
  window.Audio.prototype = Native.prototype;
  setTimeout(() => {
    try {
      const acc = document.getElementById("neko").__vue__.$accessor;
      acc.settings.setSound(true);
      acc.chat.newMessage({ id: "probe", content: "took the controls", type: "event", created: new Date() });
      const ev = n;
      acc.chat.newMessage({ id: "probe", content: "hello", type: "text", created: new Date() });
      document.documentElement.dataset.result = `event=${ev} text=${n - ev}`;
    } catch (e) {
      document.documentElement.dataset.result = "error: " + e;
    }
  }, 6000);
})();
