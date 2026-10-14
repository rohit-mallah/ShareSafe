#!/usr/bin/env node
/** Behavioral tests use a fresh disposable Chrome context and fictional local data only. */
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
let chromium, PNG;
try {
  ({ chromium } = require('playwright'));
  ({ PNG } = require('pngjs'));
} catch (error) {
  console.error('Install the test dependencies with npm install in ChromeExtension/tests, or set NODE_PATH to a directory containing playwright and pngjs.');
  throw error;
}

const extensionRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const contentPath = path.join(extensionRoot, 'content.js');
const demoPath = path.join(extensionRoot, 'demo', 'index.html');
await access(contentPath);
const html = await readFile(demoPath);
const server = createServer((_request, response) => {
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  response.end(html);
});
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});
const origin = `http://127.0.0.1:${server.address().port}`;
const chromePath = process.env.CHROME_PATH || (process.platform === 'darwin'
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : undefined);
let browser;
let failures = 0;
let executed = 0;
const tests = [];
const test = (name, run) => tests.push({ name, run });
const toolbar = (page, action) => page.locator(`#sharesafe-companion-root [data-action="${action}"]`);
const mask = (page, kind = 'element') => page.locator(`#sharesafe-companion-root .mask[data-kind="${kind}"]`);
const state = page => page.evaluate(() => window.__shareSafeCompanion.inspect());
const inject = page => page.addScriptTag({ path: contentPath });
const activate = page => page.evaluate(() => window.__shareSafeCompanion.activate());
const mode = (page, action) => toolbar(page, action).click();

async function expectCounts(page, elements, areas = 0) {
  await page.waitForFunction(({ elements, areas }) => {
    const value = window.__shareSafeCompanion.inspect();
    return value.elementMasks === elements && value.areaMasks === areas && value.maskCount === elements + areas;
  }, { elements, areas }, { timeout: 3000 });
}

async function clickPadding(page, selector) {
  const bounds = await page.locator(selector).boundingBox();
  assert.ok(bounds, `${selector} must have a visible box`);
  await page.mouse.click(bounds.x + 12, bounds.y + 12);
}

async function expectTracked(page, selector) {
  await page.waitForFunction(selector => {
    const source = document.querySelector(selector).getBoundingClientRect();
    const cover = document.querySelector('#sharesafe-companion-root').shadowRoot.querySelector('.mask[data-kind="element"]').getBoundingClientRect();
    return ['x', 'y', 'width', 'height'].every(key => Math.abs(source[key] - cover[key]) <= 2);
  }, selector, { timeout: 3000 });
}

async function expectSolid(page, kind = 'element') {
  const cover = mask(page, kind).first();
  const styles = await cover.evaluate(element => {
    const style = getComputedStyle(element);
    return { background: style.backgroundColor, opacity: style.opacity, filter: style.filter };
  });
  const color = styles.background.match(/[\d.]+/g)?.map(Number);
  assert.ok(color && (color.length === 3 || color[3] === 1), `Mask background must be opaque: ${styles.background}`);
  assert.equal(styles.opacity, '1');
  assert.equal(styles.filter, 'none');
  const bounds = await cover.boundingBox();
  assert.ok(bounds && bounds.width > 24 && bounds.height > 24, 'Mask must cover a useful positive area');
  // An actual browser screenshot checks the rendered cover, including stacking and opacity.
  // Sample in the padding to avoid the mask label or its border/radius.
  const png = PNG.sync.read(await page.screenshot({ clip: { x: bounds.x + 12, y: bounds.y + 12, width: 1, height: 1 } }));
  assert.equal(png.data[3], 255);
  color.slice(0, 3).forEach((value, index) => assert.ok(Math.abs(png.data[index] - value) <= 3,
    `Rendered mask pixel ${Array.from(png.data.slice(0, 4))} must match its solid background ${styles.background}`));
}

async function expectOpaque(page, kind = 'element') {
  const cover = mask(page, kind).first();
  if (await cover.getAttribute('data-fallback') === 'true' || await cover.getAttribute('data-style') === 'solid') return expectSolid(page, kind);
  assert.equal(await cover.getAttribute('data-style'), 'blur');
  if (kind === 'area') assert.equal(await cover.evaluate(element => getComputedStyle(element).backdropFilter), 'blur(18px)');
}

async function drawTestArea(page) {
  await mode(page, 'area');
  await page.mouse.move(300, 280);
  await page.mouse.down();
  await page.mouse.move(700, 560, { steps: 3 });
  await page.mouse.up();
  await expectCounts(page, 0, 1);
  await mode(page, 'done');
  await expectOpaque(page, 'area');
}

async function addFullscreenFixture(page, tag) {
  await page.evaluate(tag => {
    const source = document.createElement(tag);
    source.id = 'fullscreen-fixture';
    source.style.cssText = 'position:fixed;bottom:16px;left:16px;width:240px;height:160px;background:magenta;color:black;';
    if (tag === 'iframe') {
      source.title = 'Fictional fullscreen fixture';
      source.srcdoc = '<!doctype html><body style="margin:0;background:magenta;color:black">FICTIONAL FULLSCREEN CONTENT</body>';
    } else if (tag === 'video') {
      source.poster = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="900"><path fill="magenta" d="M0 0h1280v900H0z"/></svg>');
    } else source.textContent = 'FICTIONAL FULLSCREEN CONTENT';
    document.body.append(source);
    window.fullscreenEntries = [];
    document.addEventListener('fullscreenchange', () => {
      if (document.fullscreenElement === source) window.fullscreenEntries.push({ opacity: getComputedStyle(source).opacity, style: source.getAttribute('style') });
    });
    const trigger = document.createElement('button');
    trigger.id = 'fullscreen-trigger';
    trigger.textContent = 'Enter fictional fullscreen';
    trigger.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:5;';
    trigger.addEventListener('click', () => {
      window.fullscreenAttempt = source.requestFullscreen().catch(error => { window.fullscreenError = error.message; });
    });
    document.body.append(trigger);
  }, tag);
}

async function enterFullscreenExpectSafeExit(page) {
  // A real trusted click provides the user activation required by requestFullscreen.
  await page.locator('#fullscreen-trigger').click();
  await page.waitForFunction(() => window.fullscreenEntries.length > 0, null, { timeout: 3000 });
  assert.equal(await page.evaluate(() => window.fullscreenError || null), null);
  assert.equal(await page.evaluate(() => window.fullscreenEntries[0].opacity), '0', 'The fullscreen source must be hidden before its first fullscreen frame');
  await page.waitForFunction(() => document.fullscreenElement === null, null, { timeout: 3000 });
  // Wait for the safe return to document view and a renderer frame, without a timed sleep.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  assert.match(await page.locator('#sharesafe-companion-root [data-status]').innerText(), /fullscreen ended.*covers remain/i, 'The automatic exit must be explained in the visible toolbar status');
}

for (const tag of ['iframe', 'video']) test(`top layer: a fullscreen ${tag} is hidden during automatic safe exit while area covers persist`, async page => {
  await addFullscreenFixture(page, tag);
  const original = await page.locator('#fullscreen-fixture').getAttribute('style');
  await drawTestArea(page);
  await enterFullscreenExpectSafeExit(page);
  await expectCounts(page, 0, 1);
  assert.equal(await page.locator('#fullscreen-fixture').getAttribute('style'), original, 'Safe exit must restore the full original source style');
  await expectOpaque(page, 'area');
  await toolbar(page, 'clear').click({ timeout: 2000 });
  await expectCounts(page, 0);
});

test('top layer: a masked fullscreen source stays hidden through automatic safe exit and Clear recovers', async page => {
  await addFullscreenFixture(page, 'div');
  await clickPadding(page, '#fullscreen-fixture');
  await expectCounts(page, 1);
  await mode(page, 'done');
  await enterFullscreenExpectSafeExit(page);
  await expectCounts(page, 1);
  assert.equal(await page.locator('#fullscreen-fixture').evaluate(element => getComputedStyle(element).filter), 'blur(18px)');
  await expectTracked(page, '#fullscreen-fixture');
  await expectOpaque(page);
  await toolbar(page, 'clear').click({ timeout: 2000 });
  await expectCounts(page, 0);
  assert.equal(await page.locator('#fullscreen-fixture').evaluate(element => getComputedStyle(element).opacity), '1');
});

test('top layer: area covers use solid fallback above a modal dialog and Clear recovers after closing that dialog', async page => {
  await drawTestArea(page);
  await page.evaluate(() => {
    const dialog = document.createElement('dialog');
    dialog.id = 'fictional-dialog';
    dialog.style.cssText = 'margin:0;border:0;width:100vw;height:100vh;max-width:none;max-height:none;background:magenta;color:black;';
    dialog.textContent = 'FICTIONAL MODAL CONTENT';
    document.body.append(dialog);
    dialog.showModal();
  });
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await expectOpaque(page, 'area');
  assert.match(await page.locator('#sharesafe-companion-root [data-status]').innerText(), /close the page dialog.*covers remain/i);
  await page.evaluate(() => document.getElementById('fictional-dialog').close());
  await toolbar(page, 'clear').click({ timeout: 2000 });
  await expectCounts(page, 0);
});

test('selection blurs the source and suppresses page actions', async page => {
  await page.locator('#sensitive-action').click();
  await expectCounts(page, 1);
  assert.deepEqual(await page.evaluate(() => window.demoEvents), { sensitive: 0, safe: 0, pointerdown: 0, link: 0 });
  assert.equal(await page.locator('#sensitive-action').evaluate(element => getComputedStyle(element).filter), 'blur(18px)');
  await expectOpaque(page);
  await page.locator('#sensitive-link').click();
  await expectCounts(page, 2);
  assert.equal(await page.evaluate(() => location.hash), '', 'Selecting a link must suppress its navigation');
  assert.equal(await page.evaluate(() => window.demoEvents.link), 0);
  await mode(page, 'done');
  assert.equal((await state(page)).mode, null);
  await page.locator('#safe-action').click();
  assert.equal(await page.evaluate(() => window.demoEvents.safe), 1, 'Idle toolbar must allow normal page interaction');
  await expectCounts(page, 2);
});

test('Undo and Clear restore complete original inline styles, including important descendants and absent attributes', async page => {
  const original = await page.evaluate(() => ['sensitive-profile', 'nested-name', 'nested-note', 'sensitive-balance'].map(id => [id, document.getElementById(id).getAttribute('style')]));
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  assert.equal(await page.locator('#sensitive-profile').evaluate(element => getComputedStyle(element).filter), 'blur(18px)', 'Ancestor blur composites important descendants');
  await clickPadding(page, '#sensitive-balance');
  await expectCounts(page, 2);
  await mode(page, 'undo');
  await expectCounts(page, 1);
  assert.equal(await page.locator('#sensitive-balance').getAttribute('style'), null, 'Undo must remove a style attribute that did not originally exist');
  await mode(page, 'clear');
  await expectCounts(page, 0);
  assert.deepEqual(await page.evaluate(() => ['sensitive-profile', 'nested-name', 'nested-note', 'sensitive-balance'].map(id => [id, document.getElementById(id).getAttribute('style')])), original);
});

test('duplicate and nested selections are no-ops', async page => {
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  // Hidden source elements cannot be reached by normal hit testing. Dispatching a
  // bubbling click exercises duplicate handling without clicking the cover itself.
  await page.evaluate(() => {
    document.getElementById('sensitive-profile').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    document.getElementById('nested-name').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  });
  await expectCounts(page, 1);
  assert.equal(await mask(page).count(), 1);
});

test('Escape ends selection, retains multiple masks, and restores page interaction', async page => {
  await clickPadding(page, '#sensitive-profile');
  await clickPadding(page, '#sensitive-balance');
  await expectCounts(page, 2);
  await page.keyboard.press('Escape');
  assert.equal((await state(page)).mode, null);
  await expectCounts(page, 2);
  await page.locator('#safe-action').click();
  assert.equal(await page.evaluate(() => window.demoEvents.safe), 1);
  await mode(page, 'element');
  assert.equal((await state(page)).mode, 'element');
  await mode(page, 'clear');
  await expectCounts(page, 0);
});

test('element masks track scrolling, layout changes, and viewport resizing', async page => {
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  await expectTracked(page, '#sensitive-profile');
  await page.evaluate(() => window.scrollTo(0, 180));
  await expectTracked(page, '#sensitive-profile');
  await page.evaluate(() => { document.getElementById('layout-spacer').style.height = '140px'; });
  await expectTracked(page, '#sensitive-profile');
  await page.setViewportSize({ width: 900, height: 820 });
  await expectTracked(page, '#sensitive-profile');
  await expectOpaque(page);
});

test('new descendants and overflowing content remain blurred after source mutations', async page => {
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  const original = await page.evaluate(() => {
    const child = document.createElement('div');
    child.id = 'added-sensitive';
    child.textContent = 'ADDED FICTIONAL SECRET';
    child.style.cssText = 'opacity: 1 !important; position: absolute; left: -30px; top: -20px; background: magenta;';
    const original = child.getAttribute('style');
    document.getElementById('sensitive-profile').append(child);
    return original;
  });
  await page.waitForFunction(() => getComputedStyle(document.getElementById('sensitive-profile')).filter === 'blur(18px)', null, { timeout: 3000 });
  await mode(page, 'clear');
  assert.equal(await page.locator('#added-sensitive').getAttribute('style'), original);
});

test('area drags clip to the viewport, stay fixed while scrolling, and clip after resize', async page => {
  await mode(page, 'area');
  assert.equal((await state(page)).mode, 'area');
  const initialViewport = page.viewportSize();
  await page.mouse.move(300, 380);
  await page.mouse.down();
  await page.mouse.move(initialViewport.width + 120, initialViewport.height + 120, { steps: 5 });
  await page.mouse.up();
  await expectCounts(page, 0, 1);
  let bounds = await mask(page, 'area').first().boundingBox();
  assert.ok(bounds.x >= 0 && bounds.y >= 0 && bounds.width > 0 && bounds.height > 0);
  assert.ok(bounds.x + bounds.width <= initialViewport.width + 1 && bounds.y + bounds.height <= initialViewport.height + 1, 'Area bounds must be clipped to the current viewport');
  assert.ok(Math.abs(bounds.x - 300) <= 1 && Math.abs(bounds.y - 380) <= 1);
  await expectOpaque(page, 'area');
  await page.evaluate(() => { window.scrollTo(0, 240); document.getElementById('layout-spacer').style.height = '140px'; });
  const afterScroll = await mask(page, 'area').first().boundingBox();
  assert.deepEqual(afterScroll, bounds, 'Area masks use viewport coordinates');
  await page.setViewportSize({ width: 900, height: 700 });
  await page.waitForFunction(() => {
    const bounds = document.querySelector('#sharesafe-companion-root').shadowRoot.querySelector('.mask[data-kind="area"]').getBoundingClientRect();
    return bounds.right <= innerWidth + 1 && bounds.bottom <= innerHeight + 1;
  }, null, { timeout: 3000 });
  bounds = await mask(page, 'area').first().boundingBox();
  assert.ok(bounds.width > 0 && bounds.height > 0);
  assert.ok(Math.abs(bounds.x - 300) <= 1 && Math.abs(bounds.y - 380) <= 1);
  await mode(page, 'undo');
  await expectCounts(page, 0);
});

test('reinjection is idempotent and preserves masks', async page => {
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  await inject(page);
  assert.equal(await page.locator('#sharesafe-companion-root').count(), 1);
  assert.equal(await page.locator('#sharesafe-companion-root [data-status]').count(), 1);
  await expectCounts(page, 1);
  await expectOpaque(page);
  await mode(page, 'clear');
  await expectCounts(page, 0);
});

test('blur renders actual source pixels for element and area masks; solid remains selectable', async page => {
  await page.evaluate(() => {
    const fixture = document.createElement('div'); fixture.id = 'blur-pixels';
    fixture.style.cssText = 'position:fixed;left:300px;top:300px;width:400px;height:200px;background:repeating-linear-gradient(90deg,black 0 4px,white 4px 8px);';
    document.body.append(fixture);
  });
  const sample = async () => Array.from(PNG.sync.read(await page.screenshot({ clip: { x: 400, y: 400, width: 16, height: 1 } })).data).filter((_, i) => i % 4 === 0);
  const original = await page.locator('#blur-pixels').getAttribute('style');
  const before = await sample();
  assert.ok(Math.max(...before) - Math.min(...before) > 200);
  await clickPadding(page, '#blur-pixels'); await mode(page, 'done');
  let after = await sample();
  assert.ok(after.every(value => value > 60 && value < 195), `Element blur must mix black and white source pixels: ${after}`);
  await mode(page, 'clear');
  assert.equal(await page.locator('#blur-pixels').getAttribute('style'), original);
  await drawTestArea(page); after = await sample();
  assert.ok(after.every(value => value > 60 && value < 195), `Area backdrop blur must mix source pixels: ${after}`);
  await mode(page, 'clear'); await mode(page, 'style'); await mode(page, 'element');
  await clickPadding(page, '#blur-pixels'); await mode(page, 'done'); await expectSolid(page);
  assert.equal(await page.locator('#blur-pixels').evaluate(element => getComputedStyle(element).opacity), '0');
  await mode(page, 'clear'); assert.equal(await page.locator('#blur-pixels').getAttribute('style'), original);
});

test('inline mutations cannot remove blur and Clear restores exact original source style', async page => {
  const original = await page.locator('#sensitive-profile').getAttribute('style');
  await clickPadding(page, '#sensitive-profile'); await mode(page, 'done');
  await page.evaluate(() => { document.getElementById('sensitive-profile').style.cssText = 'filter:none !important; animation: reveal 1s;'; });
  await page.waitForFunction(() => getComputedStyle(document.getElementById('sensitive-profile')).filter === 'blur(18px)');
  await mode(page, 'clear'); assert.equal(await page.locator('#sensitive-profile').getAttribute('style'), original);
});

test('top layer: protected descendant popover receives solid fallback and exact restoration', async page => {
  await page.evaluate(() => {
    const child = document.createElement('div'); child.id = 'protected-popover'; child.popover = 'manual';
    child.style.cssText = 'background:magenta;width:200px;height:100px;'; child.textContent = 'FICTIONAL SECRET';
    document.getElementById('sensitive-profile').append(child);
  });
  const original = await page.locator('#protected-popover').getAttribute('style');
  await clickPadding(page, '#sensitive-profile'); await mode(page, 'done');
  await page.evaluate(() => document.getElementById('protected-popover').showPopover());
  await page.waitForFunction(() => getComputedStyle(document.getElementById('protected-popover')).opacity === '0');
  await page.evaluate(() => document.getElementById('protected-popover').hidePopover());
  await mode(page, 'clear'); assert.equal(await page.locator('#protected-popover').getAttribute('style'), original);
});

test('navigation drops masks and the companion writes no page storage', async page => {
  await clickPadding(page, '#sensitive-profile');
  await expectCounts(page, 1);
  await mode(page, 'area');
  await page.mouse.move(650, 350);
  await page.mouse.down();
  await page.mouse.move(820, 480, { steps: 3 });
  await page.mouse.up();
  await expectCounts(page, 1, 1);
  assert.deepEqual(await page.evaluate(() => ({ local: localStorage.length, session: sessionStorage.length })), { local: 0, session: 0 });
  await page.reload();
  assert.equal(await page.locator('#sharesafe-companion-root').count(), 0);
  await inject(page);
  await activate(page);
  await expectCounts(page, 0);
  assert.deepEqual(await page.evaluate(() => ({ local: localStorage.length, session: sessionStorage.length })), { local: 0, session: 0 });
});

try {
  browser = await chromium.launch({ executablePath: chromePath, headless: process.env.HEADED !== '1' });
  const selectedTests = tests.filter(({ name }) => !process.env.TEST_FILTER || name.toLowerCase().includes(process.env.TEST_FILTER.toLowerCase()));
  assert.ok(selectedTests.length, 'TEST_FILTER must match at least one test');
  executed = selectedTests.length;
  console.log(`Chrome ${browser.version()} · ${selectedTests.length} fictional local behavioral tests`);
  for (const { name, run } of selectedTests) {
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    try {
      await page.goto(origin);
      await inject(page);
      await activate(page);
      await expectCounts(page, 0);
      assert.equal((await state(page)).mode, 'element');
      await run(page);
      assert.deepEqual(pageErrors, [], 'The page and injected companion must not throw uncaught errors');
      console.log(`PASS ${name}`);
    } catch (error) {
      failures++;
      console.error(`FAIL ${name}\n${error.stack}`);
      console.error('Last companion state:', await state(page).catch(() => 'unavailable'));
    } finally {
      await context.close();
    }
  }
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
console.log(`${executed - failures}/${executed} passed`);
if (failures) process.exitCode = 1;
