const status = document.getElementById("status");

chrome.tabs.query({ active: true, currentWindow: true }).then(async ([tab]) => {
  if (!tab?.id) {
    status.textContent = "タブを確認できません";
    return;
  }
  if (/^(chrome|edge|about|devtools|chrome-extension):/.test(tab.url || "")) {
    status.textContent = "この内部ページでは使用できません";
    return;
  }
  try {
    const response = await chrome.tabs.sendMessage(tab.id, { type: "ping" });
    status.textContent = response?.ready ? "このページで有効です" : "ページで起動していません";
  } catch {
    status.textContent = "ページで起動していません。再読み込みしてください";
  }
}).catch(() => {
  status.textContent = "タブの確認に失敗しました";
});
