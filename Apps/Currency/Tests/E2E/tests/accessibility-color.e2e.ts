import assert from 'node:assert/strict';
import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('color-independent chooser selection retains currency codes and category', { tags: ['accessibility-color'] }, async ({ start, screen, app, agent }) => {
  await start('ready-converter');
  await screen.getByTestId('converter.source').tap();
  await expect(screen.getByTestId('currency.picker.category')).toBeVisible();
  await expect(screen.getByTestId('currency.picker.EUR')).toBeSelected();
  await expect(screen.getByTestId('currency.picker.USD')).toBeVisible();
  await app.screenshot('color-chooser-selected');
  await agent.assert('The base currency chooser visibly shows EUR with a checkmark, USD with its code and name, and a selected category indicated by an enclosing segment shape. Judge actual rendered marks and letters.', { vision: 'only' });
  const search = screen.getByRole('textbox', 'Search', { exact: true });
  const searchBounds = await search.boundingBox();
  assert.ok(searchBounds, 'Search must expose its actual bounds');
  await screen.tapAt({ x: searchBounds.x + searchBounds.width / 2, y: searchBounds.y + searchBounds.height / 2 });
  for (const key of ['a', 'm', 'd']) {
    await screen.getByLabel(key, { exact: true }).tap();
  }
  await expect(screen.getByTestId('currency.picker.AMD')).toBeVisible();
  await expect(screen.getByText('Unavailable', { exact: true })).toBeVisible();
  await app.screenshot('color-chooser-unavailable');
  await agent.assert('The AMD currency row shows readable AMD and Armenian Dram identification and an explicit Unavailable word, rather than relying only on muted color.', { vision: 'only' });
  const pickerClose = screen.getByTestId('currency.picker.close');
  if (await pickerClose.count() === 0) {
    await screen.getByRole('button', 'close', { exact: true }).tap();
    await expect(pickerClose).toBeVisible();
  }
  const close = await pickerClose.boundingBox();
  assert.ok(close, 'Close must expose actual bounds');
  await screen.tapAt({ x: close.x + close.width / 2, y: close.y + close.height / 2 });
  await expect(screen.getByTestId('currency.picker.close')).toBeHidden();
});

test('color-independent Settings retain accent name and selected icon checkmark', { tags: ['accessibility-color'] }, async ({ start, screen, app, agent }) => {
  await start('ready-converter');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await expect(screen.getByTestId('settings.accent')).toHaveValue('Default');
  await screen.getByTestId('settings.accent').getByText('Default').tap();
  await app.screenshot('color-accent-menu');
  await agent.assert('The open accent-color menu shows readable color names and an actual checkmark beside Default, so the chosen accent can be identified without comparing swatch colors.', { vision: 'only' });
  await screen.getByText('Default', { exact: true }).last().tap();
  await expect(screen.getByTestId('settings.accent')).toHaveValue('Default');
  await screen.getByTestId('settings.appIcon').tap();
  await expect(screen.getByTestId('settings.appIcon.world')).toHaveValue('Selected');
  await app.screenshot('color-selected-icon');
  await agent.assert('The App icon picker shows a checkmark badge on the selected World Yen / Yuan icon. Its readable title and currency symbol distinguish it from the unselected named icons without relying on color.', { vision: 'only' });
});

test('color-independent History retains range shape and dated latest value', { tags: ['accessibility-color'] }, async ({ start, screen, app, agent }) => {
  await start('ready-history-sync');
  await screen.getByRole('button', 'Edit amount in BTC').tap();
  await screen.getByTestId('converter.history').tap();
  await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
  await expect(screen.getByTestId('currency.details.historyRange')).toBeVisible();
  await agent.act('Select One week in the History range control. Keep Details open with the history chart, selected value and date visible.');
  await expect(screen.getByTestId('currency.details.selectedValue')).toHaveText('52,500 USD');
  await expect(screen.getByTestId('currency.details.selectedDate')).toBeVisible();
  await app.screenshot('color-history-week');
  await agent.assert('The History view visibly shows a selected One week range by an enclosing segment shape or named selected menu value, a single line graph with discernible rises/dips, and the latest 52,500 USD value with a readable date. Judge actual rendered glyphs and geometry.', { vision: 'only' });
});

test('color-independent onboarding distinguishes selected and unavailable tiles', { tags: ['accessibility-color'] }, async ({ start, screen, app, agent }) => {
  await start('fresh-onboarding');
  await screen.getByTestId('onboarding.primary').tap();
  await screen.getByTestId('onboarding.baseChoice.EUR').tap();
  await expect(screen.getByTestId('onboarding.baseChoice.EUR')).toHaveValue('Selected');
  await screen.getByTestId('onboarding.primary').tap();
  await expect(screen.getByTestId('onboarding.recommendations')).toBeVisible();
  await agent.act('On the destination currency page, select US Dollar only if its recommendation is not already Selected. Keep the selection page open with US Dollar and the unavailable British Pound tile visible.');
  await expect(screen.getByTestId('onboarding.recommendation.USD')).toHaveValue('Selected');
  await expect(screen.getByTestId('onboarding.recommendation.GBP')).toHaveValue('Unavailable');
  await app.screenshot('color-onboarding-selected-unavailable');
  await agent.assert('The destination recommendations visibly show USD with a checkmark badge and GBP with the explicit word Unavailable. Currency codes identify both tiles without color. The selected badge does not obscure the currency identity.', { vision: 'only' });
});
