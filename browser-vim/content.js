(() => {
  if (window.__browserVimBasicsLoaded) return;
  window.__browserVimBasicsLoaded = true;

  const alphabet = "asdfghjkl";
  const selector = [
    "a[href]", "area[href]", "button", "input:not([type=hidden])", "textarea", "select",
    "summary", "[role=button]", "[role=link]", "[onclick]", "[tabindex]:not([tabindex='-1'])"
  ].join(",");
  let hintState = null;
  let pendingG = false;
  let pendingTimer = null;

  function isEditable(element) {
    return element instanceof Element && Boolean(element.closest(
      "input, textarea, select, [contenteditable]:not([contenteditable='false'])"
    ));
  }

  function isVisible(element) {
    if (element.disabled || element.closest("[hidden], [inert], [aria-hidden='true']")) return false;
    const style = getComputedStyle(element);
    if (style.display === "none" || style.visibility !== "visible" || style.pointerEvents === "none") return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
      rect.top < innerHeight && rect.left < innerWidth;
  }

  function hintCode(index, width) {
    let code = "";
    for (let place = 0; place < width; place++) {
      code = alphabet[index % alphabet.length] + code;
      index = Math.floor(index / alphabet.length);
    }
    return code;
  }

  function closeHints() {
    hintState?.host.remove();
    hintState = null;
  }

  function renderHints() {
    if (!hintState) return;
    const { items, labels, typed } = hintState;
    items.forEach((item, index) => {
      const label = labels[index];
      const match = item.code.startsWith(typed);
      label.hidden = !match;
      if (!match) return;
      const rect = item.element.getBoundingClientRect();
      label.style.left = `${Math.max(0, rect.left)}px`;
      label.style.top = `${Math.max(0, rect.top)}px`;
      label.textContent = item.code;
    });
  }

  function startHints() {
    closeHints();
    const elements = [...document.querySelectorAll(selector)].filter(isVisible);
    if (!elements.length) return;
    const width = Math.max(1, Math.ceil(Math.log(elements.length) / Math.log(alphabet.length)));
    const host = document.createElement("div");
    host.style.cssText = "all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none";
    const shadow = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = `span{position:absolute;display:block;padding:1px 3px;border:1px solid #b88400;
      border-radius:3px;background:#ffe38a;color:#171717;font:700 12px/1.2 monospace;
      box-shadow:0 1px 3px #0008;white-space:nowrap}span[hidden]{display:none}`;
    shadow.append(style);
    const items = elements.map((element, index) => ({ element, code: hintCode(index, width) }));
    const labels = items.map(() => {
      const label = document.createElement("span");
      shadow.append(label);
      return label;
    });
    (document.documentElement || document.body).append(host);
    hintState = { host, items, labels, typed: "" };
    renderHints();
  }

  function activateHint(item) {
    closeHints();
    if (!item.element.isConnected) return;
    if (item.element.matches("input, textarea, select, [contenteditable]")) item.element.focus();
    if (typeof item.element.click === "function") item.element.click();
    else item.element.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
  }

  function handleHintKey(event) {
    if (!hintState) return false;
    if (event.key === "Escape") {
      closeHints();
    } else if (event.key === "Backspace") {
      hintState.typed = hintState.typed.slice(0, -1);
      renderHints();
    } else if (!event.ctrlKey && !event.altKey && !event.metaKey &&
        alphabet.includes(event.key.toLowerCase()) && event.key.length === 1) {
      hintState.typed += event.key.toLowerCase();
      const matches = hintState.items.filter((item) => item.code.startsWith(hintState.typed));
      if (matches.length === 1) activateHint(matches[0]);
      else if (matches.length === 0) closeHints();
      else renderHints();
    } else if (event.ctrlKey || event.altKey || event.metaKey ||
        ["Shift", "Control", "Alt", "Meta"].includes(event.key)) {
      return false;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    return true;
  }

  window.addEventListener("keydown", (event) => {
    if (hintState && handleHintKey(event)) return;
    const target = event.composedPath?.()[0] || event.target;
    if (event.defaultPrevented || event.isComposing || event.repeat || event.ctrlKey ||
        event.altKey || event.metaKey || isEditable(target)) return;

    if (pendingG) {
      pendingG = false;
      clearTimeout(pendingTimer);
      if (event.key === "t" || event.key === "T") {
        chrome.runtime.sendMessage({ type: "switch-tab", direction: event.key === "t" ? 1 : -1 });
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }
    }
    if (event.key === "g") {
      pendingG = true;
      pendingTimer = setTimeout(() => { pendingG = false; }, 1000);
      event.preventDefault();
      event.stopImmediatePropagation();
    } else if (event.key === "f") {
      startHints();
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  window.addEventListener("blur", () => {
    pendingG = false;
    clearTimeout(pendingTimer);
    closeHints();
  });
  window.addEventListener("scroll", closeHints, true);
  window.addEventListener("resize", closeHints);
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "ping") sendResponse({ ready: true, url: location.href });
  });
})();
