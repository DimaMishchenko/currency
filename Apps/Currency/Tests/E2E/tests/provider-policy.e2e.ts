import { expect } from 'e2e';
import { test } from '../fixtures.js';

const mode = process.env.CURRENCY_E2E_COINBASE ?? 'on';
if (mode !== 'on' && mode !== 'off') {
  throw new Error('CURRENCY_E2E_COINBASE must be on or off and match the installed build.');
}
const enhanced = mode === 'on';

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
    await agent.act('Scroll in Details until the current conversion provider information below the expanded source disclosure is visible. Keep Details open.');
    await expect(screen.getByText(enhanced ? /Coinbase.*retrieved/i : /Fawaz · daily ·/i)).toBeVisible();
    await app.screenshot(capture);
    await screen.getByTestId('currency.details.close').tap();
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
