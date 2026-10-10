import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { coinbaseEnabled } from '../provider-configuration.js';

const enhanced = coinbaseEnabled;
const mode = enhanced ? 'on' : 'off';

test(`provider policy ${mode} preserves crypto fallback, ranges and credits after restart`, { tags: ['core', 'providers'] }, async ({ start, app, agent, screen }) => {
  await start('ready-crypto');
  const bitcoin = screen.getByRole('button', /^Bitcoin,/i);
  const expectedAmount = enhanced ? 'Bitcoin, 0.00002' : 'Bitcoin, 0.00001';
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(bitcoin).toHaveAccessibleName(expectedAmount);

  const inspectDetails = async (capture: string) => {
    await agent.act('Open Details & history for the Bitcoin destination currency.');
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
    await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 BTC in USD');
    await expect(screen.getByTestId('currency.details.rate')).toHaveValue(enhanced ? '50,000 USD' : '100,000 USD');
    const ranges = screen.getByTestId('currency.details.historyRange');
    const day = ranges.getByRole('tab', 'One day', { exact: true });
    const source = screen.getByTestId('currency.details.sourceDisclosure')
      .filter({ hasText: /daily reference rates|hourly closes/i });
    await expect(source.filter({ hasText: /Fawaz.*daily reference rates/i })).toBeVisible();
    if (enhanced) {
      await expect(day).toBeVisible();
      await day.tap();
      await expect(day).toBeSelected();
      await expect(source.filter({ hasText: /Coinbase.*hourly closes/i })).toBeVisible();
    } else {
      await expect(day).toBeHidden();
      await expect(screen.getByText(/Coinbase/i)).toBeHidden();
    }
    await source.tap();
    await expect(source).toHaveValue('Expanded');
    await agent.act('Scroll in Details until the exact text "Crypto history uses daily rates and completed hourly candles when available. Historical and current conversion sources may differ." is visible. Use that exact text when scrolling to text. Keep Details open.');
    await expect(screen.getByText(enhanced ? /Coinbase.*retrieved/i : /Fawaz · daily ·/i)).toBeVisible();
    await app.screenshot(capture);
    await agent.act('Close Details & history with the circular X at the top right and return to the converter.');
    await expect(screen.getByTestId('currency.details.close')).toBeHidden();
    await expect(bitcoin).toHaveAccessibleName(expectedAmount);
  };

  await inspectDetails(`provider-${mode}-history`);
  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(bitcoin).toHaveAccessibleName(expectedAmount);
  await inspectDetails(`provider-${mode}-history-after-restart`);

  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.sources').tap();
  await expect(screen.getByText('Fawaz Exchange API', { exact: true })).toBeVisible();
  const coinbase = screen.getByText('Coinbase', { exact: true });
  if (enhanced) await expect(coinbase).toBeVisible();
  else await expect(coinbase).toBeHidden();
  await expect(screen.getByText('Frankfurter', { exact: true })).toBeHidden();
  await app.screenshot(`provider-${mode}-credits`);
});
