"use strict";

async function showHelp(tabId) {
  await chrome.action.setBadgeText({ tabId, text: "!" });
  await chrome.action.setBadgeBackgroundColor({ tabId, color: "#164f42" });
  await chrome.action.setTitle({ tabId, title: "ShareSafe: this page cannot be changed. Click for help." });
  await chrome.action.setPopup({ tabId, popup: "help.html" });
  try {
    await chrome.action.openPopup();
  } catch {
    // Some Chrome versions require the next explicit action click to open it.
  }
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!Number.isInteger(tab.id)) return;
  try {
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
    await chrome.action.setBadgeText({ tabId: tab.id, text: "" });
    await chrome.action.setTitle({ tabId: tab.id, title: "ShareSafe — hide an element" });
    await chrome.action.setPopup({ tabId: tab.id, popup: "" });
  } catch {
    try { await showHelp(tab.id); } catch { /* The tab may have closed. */ }
  }
});
