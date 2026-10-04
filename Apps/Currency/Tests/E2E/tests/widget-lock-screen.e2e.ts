import { test } from '../fixtures.js';

test('Lock Screen Currency Icon displays its default Dollar symbol', { tags: ['extended', 'widgets', 'widget-lock-screen'] }, async ({ start, device, agent, screen, app }) => {
  await start('ready-converter');
  await device.home();
  await device.openApp('com.apple.springboard');
  const bounds = await device.locator('role=Application').boundingBox();
  if (!bounds) throw new Error('The Lock Screen gesture requires the simulator viewport.');
  await screen.swipe({ from: { x: bounds.width / 2, y: 1 }, to: { x: bounds.width / 2, y: bounds.height * 0.7 } });
  await screen.getByText(/^\d{1,2}:\d{2}$/).longPress({ duration: 1500 });
  await screen.getByRole('button', /^Customi[sz]e$/).tap();
  await agent.waitFor('Lock Screen customization is open with Cancel and Done visible. The widget area below the clock is visible and no widget picker or other sheet obscures it.', { vision: 'only', timeout: 30_000 });
  try {
    await agent.assert('The Lock Screen customization widget area contains exactly one circular Currency Icon displaying the Dollar symbol ($).', { vision: 'only' });
  } catch (error) {
    if (!(error instanceof Error) || !('code' in error) || error.code !== 'ASSERTION_FAILED') throw error;
    await agent.assert('The entire Lock Screen customization widget area is visible and contains no Currency Icon with any currency symbol. No sheet or picker obscures it.', { vision: 'only' });
    await agent.act('Add one Currency circular Currency Icon from Add Widgets using its default Dollar symbol. Keep the current wallpaper and all other widgets. Close the Currency widget picker and dismiss the Add Widgets sheet. Stop on Lock Screen customization with the installed icon visible and Done available.');
    await agent.assert('The Lock Screen customization widget area contains exactly one circular Currency Icon displaying the Dollar symbol ($).', { vision: 'only' });
  }
  await agent.act('Save the current Lock Screen customization with Done, then tap the current wallpaper preview to leave the wallpaper switcher and show the normal Lock Screen. Finish with no customization controls or widget picker open.');
  await agent.waitFor('The normal iPhone Lock Screen or Notification Center is visible, with no wallpaper customization controls or widget picker. Exactly one installed circular Currency Icon displays the Dollar symbol ($) below the clock. The symbol is fully visible and readable.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-lock-screen-currency-icon-dollar');
  await device.home();
});
