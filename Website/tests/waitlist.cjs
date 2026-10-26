const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../waitlist.js'), 'utf8');
class Element {
  constructor() { this.events = {}; this.disabled = false; this.hidden = false; this.value = ''; this.checked = false; this.validity = { valid: false }; this.textContent = ''; this.classList = { toggle() {}, add() {}, remove() {} }; }
  addEventListener(name, callback) { this.events[name] = callback; }
  dispatch(name, extra = {}) { return this.events[name]?.({ preventDefault() {}, currentTarget: this, ...extra }); }
  focus() { this.focused = true; }
}
function fixture(sitekey = 'public-test-key') {
  const dialog = new Element(), form = new Element(), email = new Element(), button = new Element(), close = new Element(), status = new Element(), challenge = new Element(), link = new Element();
  button.disabled = true;
  form.elements = { email };
  form.querySelector = () => button;
  form.reportValidity = () => email.validity.valid;
  form.reset = () => { email.value = ''; email.validity.valid = false; };
  dialog.querySelector = selector => ({ form, '[role="status"]': status, '.waitlist-challenge': challenge, '.waitlist-close': close })[selector];
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = () => { dialog.open = false; dialog.dispatch('close'); };
  let options, resets = 0, removes = 0, scripts = [], requests = [], response = async () => ({ ok: true });
  const strings = { submit: 'Notify me', pending: 'Saving', success: 'Saved', error: 'Try again', unavailable: 'Unavailable' };
  const config = { endpoint: 'https://waitlist.example/api/waitlist', sitekey, locale: 'en-US', language: 'en', strings };
  const window = { turnstile: { render(element, value) { options = value; return 'widget'; }, reset() { resets++; }, remove() { removes++; } } };
  const document = { querySelector: selector => selector === '#launch-waitlist' ? dialog : { textContent: JSON.stringify(config) }, querySelectorAll: () => [link], documentElement: new Element(), head: { append: script => scripts.push(script) }, createElement: () => new Element() };
  vm.runInNewContext(source, { document, window, AbortController, setTimeout, clearTimeout, fetch: (url, init) => { requests.push({ url, ...init }); return response(url, init); } });
  return { dialog, form, email, button, close, status, link, scripts, requests, window, strings, get options() { return options; }, get resets() { return resets; }, get removes() { return removes; }, set response(callback) { response = callback; } };
}
function fill(view) {
  view.email.value = 'person@example.org';
  view.email.validity.valid = true;
  view.email.dispatch('input');
}
(async () => {
  const view = fixture();
  assert.equal(view.requests.length, 0);
  assert.equal(view.scripts.length, 0);
  await view.link.dispatch('click');
  assert.equal(view.options.action, 'waitlist');
  assert.equal(view.options.size, 'flexible');
  assert.equal(view.button.disabled, true);
  fill(view);
  assert.equal(view.button.disabled, true);
  view.options.callback('token-one');
  assert.equal(view.button.disabled, false);
  view.email.validity.valid = false;
  view.email.dispatch('input');
  assert.equal(view.button.disabled, true);
  await view.form.dispatch('submit');
  assert.equal(view.requests.length, 0);
  fill(view);
  view.response = async () => ({ ok: false });
  await view.form.dispatch('submit');
  assert.equal(view.status.textContent, view.strings.error);
  assert.equal(view.resets, 1);
  assert.equal(view.button.disabled, true);
  assert.deepEqual(JSON.parse(view.requests[0].body), { email: 'person@example.org', consent: true, consentVersion: 'launch-email-submit-v2', locale: 'en-US', token: 'token-one' });
  assert.equal(view.requests[0].credentials, 'omit');
  view.options.callback('token-two');
  view.response = async () => ({ ok: true });
  await view.form.dispatch('submit');
  assert.equal(view.status.textContent, view.strings.success);
  assert.equal(view.form.hidden, true);
  assert.equal(view.email.value, '');
  view.close.dispatch('click');
  assert.equal(view.form.hidden, false);
  assert.equal(view.status.textContent, '');
  assert.equal(view.link.focused, true);

  await view.link.dispatch('click');
  fill(view);
  const staleOptions = view.options;
  view.options.callback('token-three');
  let finish;
  view.response = () => new Promise(resolve => { finish = resolve; });
  const pending = view.form.dispatch('submit');
  assert.equal(view.email.disabled, true);
  assert.equal(view.button.disabled, true);
  const request = view.requests.at(-1);
  view.close.dispatch('click');
  assert.equal(request.signal.aborted, true);
  assert.equal(view.email.value, '');
  await view.link.dispatch('click');
  staleOptions.callback('stale-token');
  fill(view);
  assert.equal(view.button.disabled, true);
  finish({ ok: true });
  await pending;
  assert.equal(view.form.hidden, false);
  assert.equal(view.status.textContent, '');

  const unavailable = fixture('');
  delete unavailable.window.turnstile;
  await unavailable.link.dispatch('click');
  assert.equal(unavailable.scripts.length, 0);
  assert.equal(unavailable.status.textContent, unavailable.strings.unavailable);

  const lazy = fixture();
  const turnstile = lazy.window.turnstile;
  delete lazy.window.turnstile;
  const opening = lazy.link.dispatch('click');
  assert.equal(lazy.scripts.length, 1);
  assert.match(lazy.scripts[0].src, /render=explicit/);
  lazy.close.dispatch('click');
  lazy.window.turnstile = turnstile;
  lazy.scripts[0].onload();
  await opening;
  assert.equal(lazy.options, undefined);
  console.log('PASS: email/token gating and consent on submission, lazy loading, generic outcomes, token reset and close/reopen request isolation');
})().catch(error => { console.error(error); process.exitCode = 1; });
