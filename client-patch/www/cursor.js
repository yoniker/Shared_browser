/*
 * Shared mouse pointer for Neko's page (loaded by client-patch/apply.sh, before Neko's own code).
 *
 * Neko is set not to draw the pointer into the video (NEKO_CAPTURE_VIDEO_SHOW_POINTER=false), so:
 *  - the driver sees only their own pointer: instant, with the remote pointer's shape
 *    (arrow, text cursor, hand...);
 *  - everyone else sees the driver's pointer drawn here, with a name tag, from the position and
 *    image updates Neko's server sends over the WebRTC data channel (the driver's page mirrors its
 *    mouse moves in Neko's current format so those position updates actually happen).
 * It also asks the browser to show video frames as soon as they arrive (less delay).
 *
 * Everything is wrapped so that a failure here can never break Neko itself.
 */
(() => {
  "use strict";

  const OP_CURSOR_POSITION = 0x01; // server -> page: x, y (uint16, big-endian)
  const OP_CURSOR_IMAGE = 0x02; // server -> page: width, height, xhot, yhot (uint16) + PNG
  const OP_MOVE = 0x01; // page -> server: x, y (legacy format little-endian, current format big-endian)

  const remote = { pos: null, img: null }; // img: { url, w, h, xhot, yhot }
  let pointer = null; // { box, img, tag } drawn inside the video container

  // ---- listen to Neko's WebRTC data channels -------------------------------------------

  function handle(buf) {
    try {
      const v = new DataView(buf);
      if (v.byteLength < 3 || v.getUint16(1) !== v.byteLength) return;
      const op = v.getUint8(0);
      if (op === OP_CURSOR_POSITION && v.byteLength === 7) {
        remote.pos = { x: v.getUint16(3), y: v.getUint16(5) };
        render();
      } else if (op === OP_CURSOR_IMAGE && v.byteLength > 15 && v.getUint8(11) === 0x89) {
        const meta = { w: v.getUint16(3), h: v.getUint16(5), xhot: v.getUint16(7), yhot: v.getUint16(9) };
        const reader = new FileReader();
        reader.onload = () => {
          remote.img = Object.assign({ url: reader.result }, meta);
          render();
        };
        reader.readAsDataURL(new Blob([new Uint8Array(buf, 11)], { type: "image/png" }));
      }
    } catch (_) {
      /* ignore anything we don't understand */
    }
  }

  function onMessage(e) {
    if (e.data instanceof ArrayBuffer) handle(e.data);
    else if (e.data && typeof e.data.arrayBuffer === "function") e.data.arrayBuffer().then(handle);
  }

  function showFramesImmediately(receiver) {
    try {
      if ("jitterBufferTarget" in receiver) receiver.jitterBufferTarget = 0;
      if ("playoutDelayHint" in receiver) receiver.playoutDelayHint = 0;
    } catch (_) {}
  }

  // Neko's bundled page sends the driver's mouse moves in its older format, which moves the remote
  // pointer but never updates the position other viewers receive. Mirror each move in the current
  // format on the channel the server opened, so everyone else's page can draw the pointer.
  let serverChannel = null;
  function mirrorMove(channel, data) {
    if (channel === serverChannel || !serverChannel || serverChannel.readyState !== "open") return;
    const buf = data instanceof ArrayBuffer ? data : ArrayBuffer.isView(data) ? data.buffer : null;
    if (!buf || buf.byteLength !== 7) return;
    const v = new DataView(buf);
    if (v.getUint8(0) !== OP_MOVE || v.getUint16(1, true) !== 4) return;
    const out = new DataView(new ArrayBuffer(7));
    out.setUint8(0, OP_MOVE);
    out.setUint16(1, 4);
    out.setUint16(3, v.getUint16(3, true));
    out.setUint16(5, v.getUint16(5, true));
    nativeSend.call(serverChannel, out.buffer);
  }

  const nativeSend = window.RTCDataChannel && window.RTCDataChannel.prototype.send;
  if (nativeSend) {
    window.RTCDataChannel.prototype.send = function (data) {
      nativeSend.call(this, data);
      try {
        mirrorMove(this, data);
      } catch (_) {}
    };
  }

  const Native = window.RTCPeerConnection;
  if (Native) {
    try {
      const createDataChannel = Native.prototype.createDataChannel;
      Native.prototype.createDataChannel = function (...args) {
        const dc = createDataChannel.apply(this, args);
        dc.addEventListener("message", onMessage);
        return dc;
      };
      const Patched = function (...args) {
        const pc = new Native(...args);
        pc.addEventListener("datachannel", (e) => {
          serverChannel = e.channel;
          e.channel.addEventListener("message", onMessage);
        });
        pc.addEventListener("track", (e) => e.track.kind === "video" && showFramesImmediately(e.receiver));
        return pc;
      };
      Patched.prototype = Native.prototype;
      Object.setPrototypeOf(Patched, Native);
      window.RTCPeerConnection = Patched;
    } catch (_) {}
  }

  // ---- draw ------------------------------------------------------------------------------

  function nekoState() {
    const app = document.getElementById("neko");
    const a = app && app.__vue__ && app.__vue__.$accessor;
    if (!a || !a.remote) return null;
    return {
      driving: !!a.remote.controlling, // am I the driver?
      someoneDrives: !!a.remote.hosted,
      driverName: (a.remote.host && a.remote.host.displayname) || "",
    };
  }

  function ensurePointer(container) {
    if (pointer && pointer.box.isConnected) return pointer;
    const box = document.createElement("div");
    box.className = "nk-remote-pointer";
    const img = document.createElement("img");
    img.alt = "";
    const tag = document.createElement("span");
    tag.className = "nk-remote-pointer-tag";
    box.append(img, tag);
    container.append(box);
    pointer = { box, img, tag };
    return pointer;
  }

  function render() {
    try {
      const container = document.querySelector("#neko .player-container");
      const video = container && container.querySelector("video");
      const st = nekoState();
      if (!container || !video || !st) return;

      // driver: their own pointer takes the remote pointer's shape
      const overlay = container.querySelector(".overlay");
      if (overlay) {
        overlay.style.cursor =
          st.driving && remote.img ? `url(${remote.img.url}) ${remote.img.xhot} ${remote.img.yhot}, default` : "";
      }

      // everyone else: draw the driver's pointer
      const p = ensurePointer(container);
      const show = !st.driving && st.someoneDrives && remote.pos && remote.img && video.videoWidth > 0;
      p.box.style.display = show ? "block" : "none";
      if (!show) return;

      const rect = container.getBoundingClientRect();
      const scale = Math.min(rect.width / video.videoWidth, rect.height / video.videoHeight);
      const offsetX = (rect.width - video.videoWidth * scale) / 2;
      const offsetY = (rect.height - video.videoHeight * scale) / 2;
      if (p.img.src !== remote.img.url) p.img.src = remote.img.url;
      p.img.style.width = `${remote.img.w * scale}px`;
      p.img.style.height = `${remote.img.h * scale}px`;
      const x = offsetX + (remote.pos.x - remote.img.xhot) * scale;
      const y = offsetY + (remote.pos.y - remote.img.yhot) * scale;
      p.box.style.transform = `translate(${x}px, ${y}px)`;
      if (p.tag.textContent !== st.driverName) p.tag.textContent = st.driverName;
    } catch (_) {}
  }

  // also re-check regularly: who drives can change, and the window can be resized
  setInterval(render, 250);
})();
