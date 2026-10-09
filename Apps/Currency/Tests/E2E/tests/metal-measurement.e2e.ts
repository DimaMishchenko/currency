import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('metal measurement changes conversion and preserves weight after restart', { tags: ['core'] }, async ({ start, app, screen }) => {
  await start('ready-metals');
  const gold = screen.getByRole('button', /^Gold,/i);
  await expect(gold).toHaveAccessibleName('Gold, 0.01 troy oz');

  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Troy ounces').tap();
  await screen.getByTestId('settings.metalUnit.gram').tap();
  await expect(screen.getByTestId('settings.metalUnit')).toHaveAccessibleName(/Grams/i);
  await app.screenshot('settings-metal-grams');
  await screen.getByRole('button', 'Back', { exact: true }).tap();
  await expect(gold).toHaveAccessibleName('Gold, 0.31103477 g');
  await app.screenshot('converter-metal-grams');

  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Grams').tap();
  await screen.getByTestId('settings.metalUnit.kilogram').tap();
  await expect(screen.getByTestId('settings.metalUnit')).toHaveAccessibleName(/Kilograms/i);
  await screen.getByRole('button', 'Back', { exact: true }).tap();
  await expect(gold).toHaveAccessibleName('Gold, 0.00031103477 kg');

  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Kilograms').tap();
  await screen.getByTestId('settings.metalUnit.troyOunce').tap();
  await expect(screen.getByTestId('settings.metalUnit')).toHaveAccessibleName(/Troy ounces/i);
  await screen.getByRole('button', 'Back', { exact: true }).tap();
  await expect(gold).toHaveAccessibleName('Gold, 0.01 troy oz');
  await app.restart();
  await expect(gold).toHaveAccessibleName('Gold, 0.01 troy oz');
});

test('metal source weight and measurement survive app restart', { tags: ['core'] }, async ({ start, app, screen }) => {
  await start('ready-metal-source');
  await expect(screen.getByRole('button', 'Edit amount in XAU troy oz')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 200');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Troy ounces').tap();
  await screen.getByTestId('settings.metalUnit.gram').tap();
  await screen.getByRole('button', 'Back', { exact: true }).tap();
  await expect(screen.getByRole('button', 'Edit amount in XAU g')).toHaveValue('31.1034768');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 200');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in XAU g')).toHaveValue('31.1034768');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 200');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await expect(screen.getByTestId('settings.metalUnit')).toHaveAccessibleName(/Grams/i);
  await app.screenshot('metal-grams-persisted');
});
