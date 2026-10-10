// test-only: after __DELAY_MS__ ms, read the probe's result from the page and save it as Downloads/result.txt
setTimeout(async () => {
  const [tab] = await chrome.tabs.query({ active: true });
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    world: "MAIN",
    func: () => document.documentElement.dataset.result || "(probe set no result)",
  });
  chrome.downloads.download({ url: "data:text/plain," + encodeURIComponent(result), filename: "result.txt" });
}, __DELAY_MS__);
