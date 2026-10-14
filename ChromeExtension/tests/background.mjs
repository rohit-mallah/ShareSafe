#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const manifest = JSON.parse(await readFile(new URL('manifest.json', root), 'utf8'));
const source = await readFile(new URL('background.js', root), 'utf8');
assert.equal(manifest.manifest_version, 3);
assert.deepEqual([...manifest.permissions].sort(), ['activeTab', 'scripting']);
assert.equal(manifest.host_permissions, undefined);
assert.equal(manifest.optional_host_permissions, undefined);
assert.equal(manifest.content_scripts, undefined, 'Injection must happen after an explicit action');
assert.equal(manifest.background.service_worker, 'background.js');
assert.ok(manifest.commands._execute_action, 'The keyboard command must trigger the same action');
console.log('PASS minimal manifest permissions and explicit action wiring');

function worker({ injectionFails = false, popupFails = false } = {}) {
  const calls = [];
  let clicked;
  const action = { onClicked: { addListener(listener) { assert.equal(clicked, undefined); clicked = listener; } } };
  for (const name of ['setBadgeText', 'setBadgeBackgroundColor', 'setTitle', 'setPopup', 'openPopup']) {
    action[name] = async data => {
      calls.push({ name, data: data === undefined ? null : JSON.parse(JSON.stringify(data)) });
      if (name === 'openPopup' && popupFails) throw new Error('Popup requires another user gesture');
    };
  }
  vm.runInNewContext(source, {
    chrome: { action, scripting: { async executeScript(data) {
      calls.push({ name: 'executeScript', data: JSON.parse(JSON.stringify(data)) });
      if (injectionFails) throw new Error('Cannot access this Chrome-owned page');
    } } }
  }, { filename: 'background.js' });
  assert.equal(typeof clicked, 'function');
  return { calls, clicked };
}

{
  const { calls, clicked } = worker();
  await clicked({ id: 42 });
  assert.deepEqual(calls[0], { name: 'executeScript', data: { target: { tabId: 42 }, files: ['content.js'] } });
  assert.ok(calls.some(({ name, data }) => name === 'setBadgeText' && data.tabId === 42 && data.text === ''));
  assert.ok(calls.some(({ name, data }) => name === 'setPopup' && data.tabId === 42 && data.popup === ''));
  assert.ok(calls.some(({ name, data }) => name === 'setTitle' && data.tabId === 42 && /hide an element/i.test(data.title)));
  assert.ok(!calls.some(({ name }) => name === 'openPopup'));
  console.log('PASS action injects the packaged script and clears prior error state');
}

for (const popupFails of [false, true]) {
  const { calls, clicked } = worker({ injectionFails: true, popupFails });
  await clicked({ id: 43 });
  assert.ok(calls.some(({ name, data }) => name === 'setBadgeText' && data.tabId === 43 && data.text === '!'));
  assert.ok(calls.some(({ name, data }) => name === 'setPopup' && data.tabId === 43 && data.popup === 'help.html'));
  assert.ok(calls.some(({ name, data }) => name === 'setTitle' && /help/i.test(data.title)));
  assert.ok(calls.some(({ name }) => name === 'openPopup'));
  console.log(`PASS blocked-page help ${popupFails ? 'survives a rejected automatic popup' : 'opens an actionable popup'}`);
}

{
  const { calls, clicked } = worker();
  for (const tab of [{}, { id: null }, { id: '42' }, { id: NaN }]) await clicked(tab);
  assert.deepEqual(calls, []);
  console.log('PASS missing or invalid tab ids do not invoke Chrome APIs');
}
console.log('5/5 background and manifest checks passed');
