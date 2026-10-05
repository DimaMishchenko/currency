import { test } from '../fixtures.js';
import { expect } from 'e2e';

test('converter state survives inspecting history and rate sources', { tags: ['core'] }, async ({ app, agent, start, screen }) => {
  await start('ready-converter');
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');

  await agent.act('Open Details & history for the US Dollar destination currency.');
  await expect(screen.getByTestId('currency.details.USD')).toBeVisible();
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 USD in EUR');
  await expect(screen.getByTestId('currency.details.rate')).toHaveValue('0.5 EUR');
  await expect(screen.getByTestId('currency.details.historyRange')).toBeVisible();

  await agent.act('Change the history range to Three months (3M).');
  await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'Three months')).toBeSelected();

  const source = screen.getByTestId('currency.details.sourceDisclosure').filter({ hasText: /daily reference rates/i });
  await source.tap();
  await expect(source).toHaveValue('Expanded');
  await agent.act('Scroll down in Details until the exact text "Reference-rate history may have gaps on weekends or when no data is published. Historical and current conversion sources may differ." is visible. Use that exact text when scrolling to text. Keep Details open.');
  await expect(screen.getByText('Reference-rate history may have gaps on weekends or when no data is published. Historical and current conversion sources may differ.')).toBeVisible();
  await app.screenshot('details-three-months-source-expanded');

  await agent.act('Close Details & history and return to the converter.');
  await expect(screen.getByTestId('currency.details.close')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
  await app.screenshot('converter-preserved-amount-after-details');
});
