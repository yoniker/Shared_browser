// test-only: capture the visible tab __CAPTURE_MS__ ms after start and save it as Downloads/shot.png
setTimeout(async () => {
  const [tab] = await chrome.tabs.query({ active: true });
  const url = await chrome.tabs.captureVisibleTab(tab.windowId, { format: "png" });
  chrome.downloads.download({ url, filename: "shot.png" });
}, __CAPTURE_MS__);
