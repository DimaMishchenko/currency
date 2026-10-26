(() => {
  'use strict';
  const dialog = document.querySelector('#launch-waitlist');
  if (!dialog) return;
  const config = JSON.parse(document.querySelector('#waitlist-config').textContent);
  const form = dialog.querySelector('form');
  const email = form.elements.email;
  const submit = form.querySelector('button[type="submit"]');
  const status = dialog.querySelector('[role="status"]');
  const challenge = dialog.querySelector('.waitlist-challenge');
  const strings = config.strings;
  let token = '', widget, loader, session = 0, controller, opener;
  let pending = false;
  const update = () => {
    submit.disabled = pending || !token || !email.validity.valid;
  };
  const message = (value, error = false) => {
    status.textContent = value;
    status.classList.toggle('waitlist-error', error);
  };
  const loadChallenge = () => {
    if (window.turnstile) return Promise.resolve(window.turnstile);
    if (loader) return loader;
    loader = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      script.async = true;
      script.onload = () => window.turnstile ? resolve(window.turnstile) : reject(new Error());
      script.onerror = () => { script.remove(); loader = undefined; reject(new Error()); };
      document.head.append(script);
    });
    return loader;
  };
  const open = async (event) => {
    event.preventDefault();
    if (dialog.open) return;
    opener = event.currentTarget;
    const current = ++session;
    dialog.showModal();
    document.documentElement.classList.add('waitlist-open');
    email.focus();
    if (!config.sitekey) { message(strings.unavailable, true); return; }
    try {
      const turnstile = await loadChallenge();
      if (current !== session || !dialog.open) return;
      widget = turnstile.render(challenge, {
        sitekey: config.sitekey,
        action: 'waitlist',
        language: config.language,
        size: window.innerWidth < 360 ? 'compact' : 'flexible',
        callback: value => { if (current === session) { token = value; update(); } },
        'expired-callback': () => { if (current === session) { token = ''; update(); } },
        'error-callback': () => { if (current === session) { token = ''; message(strings.unavailable, true); update(); } }
      });
    } catch {
      if (current === session) message(strings.unavailable, true);
    }
  };
  document.querySelectorAll('.app-store-link').forEach(link => link.addEventListener('click', open));
  email.addEventListener('input', update);
  dialog.querySelector('.waitlist-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) {
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  } });
  dialog.addEventListener('close', () => {
    ++session;
    controller?.abort();
    controller = undefined;
    if (widget !== undefined) window.turnstile?.remove(widget);
    widget = undefined;
    token = '';
    pending = false;
    form.reset();
    form.hidden = false;
    email.disabled = false;
    submit.textContent = strings.submit;
    message('');
    update();
    document.documentElement.classList.remove('waitlist-open');
    opener?.focus();
  });
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (pending || !token || !form.reportValidity()) return;
    const current = session;
    pending = true;
    email.disabled = true;
    submit.textContent = strings.pending;
    message('');
    update();
    const request = new AbortController();
    controller = request;
    const timeout = setTimeout(() => request.abort(), 12000);
    try {
      const response = await fetch(config.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        signal: request.signal,
        body: JSON.stringify({ email: email.value.trim(), consent: true, consentVersion: 'launch-email-submit-v2', locale: config.locale, token })
      });
      if (!response.ok) throw new Error();
      if (current !== session) return;
      email.value = '';
      token = '';
      form.hidden = true;
      if (widget !== undefined) window.turnstile?.remove(widget);
      widget = undefined;
      message(strings.success);
      status.focus();
    } catch {
      if (current !== session) return;
      token = '';
      if (widget !== undefined) window.turnstile?.reset(widget);
      message(strings.error, true);
    } finally {
      clearTimeout(timeout);
      if (current === session) {
        controller = undefined;
        pending = false;
        email.disabled = false;
        submit.textContent = strings.submit;
        update();
      }
    }
  });
})();
