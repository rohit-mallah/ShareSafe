"use strict";
// Reset the temporary popup so the next click retries the normal action.
chrome.tabs.query({ active: true, currentWindow: true }).then(([tab]) => {
  if (tab && Number.isInteger(tab.id)) chrome.action.setPopup({ tabId: tab.id, popup: "" });
});
document.querySelector("#close").addEventListener("click", () => window.close());
