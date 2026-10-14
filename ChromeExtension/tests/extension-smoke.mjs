#!/usr/bin/env node
/** A bounded, actual unpacked-extension load check with a disposable profile. */
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const { chromium } = createRequire(import.meta.url)('playwright');
const extensionRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const profile = await mkdtemp(path.join(os.tmpdir(), 'sharesafe-extension-smoke-'));
let context;
try {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.EXTENSION_CHROME_PATH || chromium.executablePath(),
    headless: process.env.HEADED !== '1',
    args: [`--disable-extensions-except=${extensionRoot}`, `--load-extension=${extensionRoot}`]
  });
  const worker = context.serviceWorkers()[0] || await context.waitForEvent('serviceworker', { timeout: 10_000 });
  assert.match(worker.url(), /^chrome-extension:\/\/[a-z]+\/background\.js$/);
  const manifest = await worker.evaluate(() => chrome.runtime.getManifest());
  assert.equal(manifest.name, 'ShareSafe Companion');
  assert.deepEqual([...manifest.permissions].sort(), ['activeTab', 'scripting']);
  const page = await context.newPage();
  await page.goto(worker.url().replace(/background\.js$/, 'help.html'));
  assert.ok((await page.locator('body').innerText()).includes('ShareSafe'));
  console.log(`PASS unpacked MV3 extension loaded with a live background service worker: ${worker.url()}`);
  console.log('PASS packaged blocked-page help renders in the actual extension origin');
  console.log('Action callback logic is covered by background.mjs; a manual toolbar-click smoke remains useful.');
} finally {
  try { await context?.close(); }
  finally { await rm(profile, { recursive: true, force: true }); }
}
