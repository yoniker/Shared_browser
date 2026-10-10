// probe: count messages Neko's server sends over the page's WebRTC data channels, by opcode
// (1 = pointer position, 2 = pointer image). Result: JSON counts.
(() => {
  const counts = {};
  const tally = (buf) => { const op = new Uint8Array(buf)[0]; counts[op] = (counts[op] || 0) + 1; };
  const listen = (dc) => dc.addEventListener("message", (e) => {
    if (e.data instanceof ArrayBuffer) tally(e.data);
    else if (e.data && e.data.arrayBuffer) e.data.arrayBuffer().then(tally);
  });
  const Native = window.RTCPeerConnection;
  const create = Native.prototype.createDataChannel;
  Native.prototype.createDataChannel = function (...a) { const dc = create.apply(this, a); listen(dc); return dc; };
  function Wrapped(...a) { const pc = new Native(...a); pc.addEventListener("datachannel", (e) => listen(e.channel)); return pc; }
  Wrapped.prototype = Native.prototype;
  window.RTCPeerConnection = Wrapped;
  setInterval(() => { document.documentElement.dataset.result = JSON.stringify(counts); }, 500);
})();
