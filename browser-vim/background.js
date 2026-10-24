chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== "switch-tab" || !sender.tab || ![-1, 1].includes(message.direction)) {
    return;
  }

  chrome.tabs.query({ windowId: sender.tab.windowId }).then((tabs) => {
    const ordered = tabs.sort((a, b) => a.index - b.index);
    const current = ordered.findIndex((tab) => tab.id === sender.tab.id);
    if (current < 0 || ordered.length < 2) return;
    const next = ordered[(current + message.direction + ordered.length) % ordered.length];
    if (next.id !== undefined) return chrome.tabs.update(next.id, { active: true });
  }).catch(console.error);
});
