document.addEventListener('click', event => {
  for (const menu of document.querySelectorAll('.language-menu[open]')) {
    if (!menu.contains(event.target)) menu.open = false;
  }
});
