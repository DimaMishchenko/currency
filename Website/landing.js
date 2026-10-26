const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const reveals = [...document.querySelectorAll('.reveal')];
if (!reducedMotion.matches && 'IntersectionObserver' in window) {
  document.documentElement.classList.add('motion-ready');
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) {
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  }, { threshold: .05, rootMargin: '0px 0px 30px 0px' });
  reveals.forEach(element => observer.observe(element));
  reducedMotion.addEventListener('change', event => {
    if (event.matches) {
      document.documentElement.classList.remove('motion-ready');
      observer.disconnect();
    }
  });
}
function tabs(selector, render) {
  const items = [...document.querySelectorAll(selector)];
  if (items.length) items[0].closest('[role=tablist]').hidden = false;
  function activate(button, focus = false) {
    for (const item of items) { item.setAttribute('aria-selected', String(item === button)); item.tabIndex = item === button ? 0 : -1; }
    render(button);
    if (focus) button.focus();
  }
  for (const button of items) {
    button.addEventListener('click', () => activate(button));
    button.addEventListener('keydown', event => {
      let index = items.indexOf(button);
      if (event.key === 'ArrowRight') index = (index + 1) % items.length;
      else if (event.key === 'ArrowLeft') index = (index - 1 + items.length) % items.length;
      else if (event.key === 'Home') index = 0;
      else if (event.key === 'End') index = items.length - 1;
      else return;
      event.preventDefault(); activate(items[index], true);
    });
  }
}
const panels = [...document.querySelectorAll('[data-rate-panel]')];
for (const panel of panels) panel.hidden = panel.dataset.ratePanel !== 'currencies';
document.querySelector('.rate-panels').classList.add('is-enhanced');
tabs('[data-rate]', button => {
  for (const panel of panels) panel.hidden = panel.dataset.ratePanel !== button.dataset.rate;
  const image = document.querySelector('#rate-image');
  image.src = button.dataset.image;
  image.alt = button.dataset.imageAlt;
});
