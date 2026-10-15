import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('crypto reference prices preserve ranges, provenance and credits after restart', { tags: ['core', 'providers'] }, async ({ start, app, agent, screen }) => {
  await start('ready-crypto');
  const bitcoin = screen.getByRole('button', /^Bitcoin,/i);
  const expectedAmount = 'Bitcoin, 0.00002';
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(bitcoin).toHaveAccessibleName(expectedAmount);

  const inspectDetails = async (capture: string) => {
    await agent.act('Open Details & history for the Bitcoin destination currency.');
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
    await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 BTC in USD');
    await expect(screen.getByTestId('currency.details.rate')).toHaveValue('50,000 USD');
    const ranges = screen.getByTestId('currency.details.historyRange');
    const day = ranges.getByRole('tab', 'One day', { exact: true });
    const source = screen.getByTestId('currency.details.sourceDisclosure')
      .filter({ hasText: /daily reference rates|monthly reference rates|minute reference prices/i });
    await expect(source.filter({ hasText: /Fawaz.*daily reference rates/i })).toBeVisible();
    await expect(day).toBeVisible();
    await day.tap();
    await expect(day).toBeSelected();
    await expect(source.filter({ hasText: /Coin Metrics.*minute reference prices/i })).toBeVisible();
    await expect(screen.getByText('50,000 USD', { exact: true })).toBeVisible();
    const all = ranges.getByRole('tab', 'All available history', { exact: true });
    await all.tap();
    await expect(all).toBeSelected();
    await expect(source.filter({ hasText: /monthly reference rates/i })).toBeVisible();
    await expect(source.filter({ hasText: /Coin Metrics.*Frankfurter|Frankfurter.*Coin Metrics/i })).toBeVisible();
    await app.screenshot(`${capture}-all-reference-history`);
    await day.tap();
    await expect(day).toBeSelected();
    await expect(source.filter({ hasText: /Coin Metrics.*minute reference prices/i })).toBeVisible();
    await expect(screen.getByText('50,000 USD', { exact: true })).toBeVisible();
    await source.tap();
    await expect(source).toHaveValue('Expanded');
    await agent.act('Scroll in Details until the exact text "Crypto history combines daily and monthly reference data with intraday prices when available. Converted prices may be approximate. Historical and current sources can differ." is visible. Use that exact text when scrolling to text. Keep Details open.');
    await expect(screen.getByText(/Coin Metrics.*minute reference prices.*approximate conversion/i)).toBeVisible();
    await app.screenshot(capture);
    await agent.act('Close Details & history with the circular X at the top right and return to the converter.');
    await expect(screen.getByTestId('currency.details.close')).toBeHidden();
    await expect(bitcoin).toHaveAccessibleName(expectedAmount);
  };

  await inspectDetails('crypto-reference-history');
  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(bitcoin).toHaveAccessibleName(expectedAmount);
  await inspectDetails('crypto-reference-history-after-restart');

  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.rates').tap();
  await agent.act('Scroll Rates until the BTC quote and its source information are visible. Keep Rates open.');
  await expect(screen.getByText(/Coin Metrics.*minute reference prices.*approximate conversion/i).first()).toBeVisible();
  await expect(screen.getByText(/Approximate conversion: 1 EUR = 2 USD \(Fawaz,/i).first()).toBeVisible();
  await expect(screen.getByText(/Observed/i).first()).toBeVisible();
  await app.screenshot('crypto-reference-rates-provenance');
  await screen.getByRole('button', 'Settings', { exact: true }).tap();
  await screen.getByTestId('settings.sources').tap();
  await expect(screen.getByText('Fawaz Exchange API', { exact: true })).toBeVisible();
  const coinMetrics = screen.getByText('Coin Metrics', { exact: true });
  await expect(coinMetrics).toBeVisible();
  await expect(screen.getByText('Frankfurter', { exact: true })).toBeVisible();
  await app.screenshot('crypto-reference-credits');
});
