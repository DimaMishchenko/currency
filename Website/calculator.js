(() => {
  const localized = JSON.parse(document.querySelector('#calculator-copy')?.textContent || '{}');
  const translate = text => localized.strings?.[text] || text;
  const locale = localized.locale || 'en-US';
  const html = text => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const decimalSeparator = new Intl.NumberFormat(locale).formatToParts(1.1).find(part => part.type === 'decimal').value;
  const integerFormatter = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 });
  const currencies = [
    { code: 'EUR', name: 'Euro', flag: '🇪🇺', rate: 1 },
    { code: 'USD', name: 'US dollar', flag: '🇺🇸', rate: 1.1229 },
    { code: 'GBP', name: 'British pound', flag: '🇬🇧', rate: .8427 },
    { code: 'CZK', name: 'Czech koruna', flag: '🇨🇿', rate: 24.3346 },
    { code: 'JPY', name: 'Japanese yen', flag: '🇯🇵', rate: 177.5 },
    { code: 'CHF', name: 'Swiss franc', flag: '🇨🇭', rate: .9255 },
  ];
  const formatters = new Map(currencies.map(currency => [currency.code,
    new Intl.NumberFormat(locale, { maximumFractionDigits: currency.code === 'JPY' ? 0 : 2 })]));
  const keys = ['7', '8', '9', 'delete', '4', '5', '6', 'clear', '1', '2', '3', '000', '.', '0', '00'];
  const deleteIcon = '<svg viewBox="0 0 28 24" fill="none" aria-hidden="true"><path d="M10 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H10L2 12l8-9Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="m13 8 8 8m0-8-8 8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

  function mount(host) {
    if (host.dataset.calculatorMounted) return;
    host.dataset.calculatorMounted = 'true';
    host.classList.add('calculator-demo');
    host.innerHTML = `<div class="calculator-demo__widget" role="group" aria-label="${html(translate('Interactive currency calculator, sample rates'))}" tabindex="0">
      <div class="calculator-demo__tiles">${currencies.map(currency => `<button type="button" class="calculator-demo__tile" data-currency="${currency.code}" aria-pressed="false"><span class="calculator-demo__flag" aria-hidden="true">${currency.flag}</span><span class="calculator-demo__figures"><span class="calculator-demo__code">${currency.code}</span><span class="calculator-demo__amount"></span></span></button>`).join('')}</div>
      <div class="calculator-demo__keypad" role="group" aria-label="${html(translate('Calculator keypad'))}">${keys.map(key => `<button type="button" class="calculator-demo__key${key === '0' ? ' calculator-demo__key--zero' : ''}${key.length > 1 && /^0/.test(key) ? ' calculator-demo__key--multiple' : ''}" data-key="${key}" aria-label="${html(translate(key === 'delete' ? 'Delete last digit' : key === 'clear' ? 'Clear amount' : key === '.' ? 'Decimal point' : key))}">${key === 'delete' ? deleteIcon : key === 'clear' ? 'C' : key === '.' ? decimalSeparator : key}</button>`).join('')}</div>
      </div><div class="calculator-demo__announcement" role="status" aria-live="polite" aria-atomic="true"></div>`;
    const tiles = [...host.querySelectorAll('[data-currency]')];
    const announcement = host.querySelector('[role="status"]');
    let active = currencies[0];
    let amount = '100';
    let replacesOnDigit = true;
    let editedAt = 0;
    let announcementTimer;

    const valueFor = currency => Number(amount) / active.rate * currency.rate;
    const displayInput = () => {
      const [integer, fraction] = amount.split('.');
      return integerFormatter.format(Number(integer)) + (fraction !== undefined ? `${decimalSeparator}${fraction}` : '');
    };
    function render(announce = true) {
      const values = [];
      currencies.forEach((currency, index) => {
        const selected = currency === active;
        const value = selected && !replacesOnDigit ? displayInput() : formatters.get(currency.code).format(valueFor(currency));
        const tile = tiles[index];
        tile.setAttribute('aria-pressed', String(selected));
        tile.setAttribute('aria-label', `${translate(currency.name)}, ${currency.code}, ${value}. ${translate(selected ? 'Selected input currency.' : 'Select as input currency.')}`);
        const label = tile.querySelector('.calculator-demo__amount');
        label.textContent = value;
        label.style.fontSize = `${Math.min(6.1111, 65 / Math.max(value.length, 1))}cqw`;
        values.push(`${value} ${currency.code}`);
      });
      if (announce) {
        clearTimeout(announcementTimer);
        announcementTimer = setTimeout(() => { announcement.textContent = values.join('; '); }, 180);
      }
    }
    function press(key) {
      if (Date.now() - editedAt >= 60000 && editedAt) replacesOnDigit = true;
      editedAt = Date.now();
      if (key === 'clear') {
        amount = '0';
        replacesOnDigit = false;
      } else if (key === 'delete') {
        amount = replacesOnDigit || amount.length === 1 ? '0' : amount.slice(0, -1);
        replacesOnDigit = false;
      } else {
        if (replacesOnDigit) { amount = '0'; replacesOnDigit = false; }
        if (key === '.') {
          if (!amount.includes('.')) amount += '.';
        } else {
          for (const digit of key) {
            if (amount.replace('.', '').length >= 14) break;
            amount = amount === '0' ? digit : amount + digit;
          }
        }
      }
      render();
    }
    host.addEventListener('click', event => {
      const key = event.target.closest('[data-key]');
      if (key) { press(key.dataset.key); return; }
      const tile = event.target.closest('[data-currency]');
      if (!tile) return;
      const currency = currencies.find(item => item.code === tile.dataset.currency);
      if (currency !== active) {
        amount = String(Number(valueFor(currency).toPrecision(15)));
        active = currency;
      }
      replacesOnDigit = true;
      editedAt = Date.now();
      render();
    });
    host.addEventListener('keydown', event => {
      if (event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return;
      let key;
      if (/^[0-9]$/.test(event.key)) key = event.key;
      else if (event.key === '.' || event.key === ',') key = '.';
      else if (event.key === 'Backspace' || event.key === 'Delete') key = 'delete';
      else if (event.key === 'Escape' || event.key.toLowerCase() === 'c') key = 'clear';
      if (!key) return;
      event.preventDefault();
      press(key);
    });
    render(false);
  }
  const mountAll = () => document.querySelectorAll('[data-calculator-demo]').forEach(mount);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountAll, { once: true });
  else mountAll();
})();
