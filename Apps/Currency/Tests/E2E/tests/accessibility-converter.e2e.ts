import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('destination amount semantics follow the displayed draft', {
  tags: ['core', 'accessibility-converter-history'],
}, async ({ start, screen }) => {
  await start('ready-converter');
  await screen.getByRole('button', /^US Dollar,/).tap();
  await screen.getByRole('button', '4', { exact: true }).tap();
  await screen.getByRole('button', 'Decimal separator', { exact: true }).tap();
  await expect(screen.getByRole('button', 'US Dollar, 4', { exact: true })).toBeVisible();
  await screen.getByRole('button', '0', { exact: true }).tap();
  await expect(screen.getByRole('button', 'US Dollar, 4.0', { exact: true })).toBeVisible();
});
