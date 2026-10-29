import assert from 'node:assert/strict';
import { join } from 'node:path';
import { test } from '../fixtures.js';
import { expect } from 'e2e';
import { readHistory, sharedDirectory } from './history-cache.js';

test('converter state survives inspecting history and rate sources', { tags: ['core'] }, async ({ app, agent, start, screen }) => {
  await start('ready-converter');
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');

  await screen.getByRole('button', /^US Dollar,/i).longPress({ duration: 650 });
  await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Details & history', { exact: true }).tap();
  await expect(screen.getByTestId('currency.details.USD')).toBeVisible();
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 USD in EUR');
  await expect(screen.getByTestId('currency.details.rate')).toHaveValue('0.5 EUR');
  await expect(screen.getByTestId('currency.details.historyRange')).toBeVisible();

  await agent.act('Change the history range to Three months (3M).');
  await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'Three months')).toBeSelected();

  const detailsBounds = await screen.getByTestId('currency.details.USD').boundingBox();
  if (!detailsBounds) throw new Error('Details must expose its sheet bounds');
  await screen.swipe({
    from: { x: detailsBounds.x + 8, y: detailsBounds.y + detailsBounds.height * 0.8 },
    to: { x: detailsBounds.x + 8, y: detailsBounds.y + detailsBounds.height * 0.3 },
  });
  const history = readHistory(join(sharedDirectory(), 'history-v3-USD-EUR-90.json'));
  assert.equal(history.source.observation, 'dailyReference');
  const provider = Object.keys(history.source.provider)[0];
  assert.ok(provider === 'frankfurter' || provider === 'fawaz');
  const providerName = provider === 'frankfurter' ? 'Frankfurter' : 'Fawaz';
  const sourceTitle = new RegExp(`^${providerName}.*daily reference rates$`, 'i');
  const source = screen.getByTestId('currency.details.sourceDisclosure')
    .filter({ hasText: sourceTitle });
  await expect(source).toHaveText(sourceTitle);
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


test('input dock History keeps BTC primary when inspecting the USD conversion', { tags: ['core'] }, async ({ app, start, screen }) => {
  await start('ready-history-sync');
  await screen.getByRole('button', /^US Dollar,/i).tap();
  await screen.getByTestId('converter.history').tap();
  await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
  const rate = screen.getByTestId('currency.details.rate');
  await expect(rate).toHaveAccessibleName('1 BTC in USD');
  await expect(rate).toHaveValue('52,500 USD');
  const ranges = screen.getByTestId('currency.details.historyRange');
  for (const name of ['One day', 'One week', 'One month']) {
    const period = ranges.getByRole('tab', name, { exact: true });
    await period.tap();
    await expect(period).toBeSelected();
    await expect(rate).toHaveAccessibleName('1 BTC in USD');
    await expect(rate).toHaveValue('52,500 USD');
  }
  await app.screenshot('btc-primary-usd-input-history-retains-conversion-direction');
  await screen.getByTestId('currency.details.close').tap();
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
  await screen.getByRole('button', /^US Dollar,/i).tap();
  await screen.getByTestId('converter.history').tap();
  await expect(rate).toHaveAccessibleName('1 BTC in USD');
  await expect(rate).toHaveValue('52,500 USD');
});
