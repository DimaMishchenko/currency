import { expect } from 'e2e';
import { test } from '../fixtures.js';

const references = [
  { code: 'EUR', name: 'Euro', value: '25,000 EUR' },
  { code: 'USD', name: 'US Dollar', value: '50,000 USD' },
  { code: 'CZK', name: 'Czech Koruna', value: '625,000 CZK' },
  { code: 'CHF', name: 'Swiss Franc', value: '12,500 CHF' },
] as const;

for (const reference of references) {
  test(`Bitcoin Details preserves the ${reference.code} converter reference`, { tags: ['core', 'providers'] }, async ({ start, app, agent, screen }) => {
    await start('ready-crypto');
    if (reference.code !== 'USD') {
      await agent.act(`Open the source currency picker. Use its Search field to search ${reference.code}, then select the ${reference.name} result and return to the converter without editing the amount.`);
    }
    const sourceCurrency = screen.getByTestId('converter.source');
    await expect(sourceCurrency).toHaveAccessibleName(new RegExp(reference.name, 'i'));
    await expect(screen.getByRole('button', `Edit amount in ${reference.code}`)).toHaveValue('1');

    const assertPair = async () => {
      await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName(`1 BTC in ${reference.code}`);
      await expect(screen.getByTestId('currency.details.rate')).toHaveValue(reference.value);
    };
    await screen.getByRole('button', /^Bitcoin,/i).longPress({ duration: 650 });
    await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
    await screen.getByRole('button', 'Details & history', { exact: true }).tap();
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
    await app.screenshot(`bitcoin-details-${reference.code.toLowerCase()}-opened`);
    await assertPair();

    const ranges = screen.getByTestId('currency.details.historyRange');
    const month = ranges.getByRole('tab', 'One month', { exact: true });
    const day = ranges.getByRole('tab', 'One day', { exact: true });
    await month.tap();
    await expect(month).toBeSelected();
    await assertPair();
    await expect(screen.getByText(reference.value, { exact: true })).toBeVisible();
    await day.tap();
    await expect(day).toBeSelected();
    await assertPair();
    await expect(screen.getByText(reference.value, { exact: true })).toBeVisible();

    const source = screen.getByTestId('currency.details.sourceDisclosure')
      .filter({ hasText: /Coin Metrics.*minute reference prices/i });
    await expect(source).toBeVisible();
    if (reference.code !== 'USD') {
      await expect(source.filter({ hasText: /approximate conversion/i })).toBeVisible();
    }
    await source.tap();
    await expect(source).toHaveValue('Expanded');
    await agent.act('Scroll in Details until the exact text "Crypto history combines daily and monthly reference data with intraday prices when available. Converted prices may be approximate. Historical and current sources can differ." is visible. Use that exact text when scrolling to text. Keep Details open.');
    if (reference.code === 'USD') {
      await expect(screen.getByText(/Coin Metrics.*minute reference prices.*approximate conversion/i)).toBeHidden();
      await expect(screen.getByText(/^Approximate conversion:/i)).toBeHidden();
    } else {
      await expect(screen.getByText(new RegExp(`^Approximate conversion: 1 USD = .* ${reference.code}`, 'i')).first()).toBeVisible();
    }
    await app.screenshot(`bitcoin-details-${reference.code.toLowerCase()}-day-source`);

    await screen.getByTestId('currency.details.close').tap();
    await expect(screen.getByTestId('currency.details.close')).toBeHidden();
    await expect(sourceCurrency).toHaveAccessibleName(new RegExp(reference.name, 'i'));
    await app.restart();
    await expect(sourceCurrency).toHaveAccessibleName(new RegExp(reference.name, 'i'));
    await expect(screen.getByRole('button', `Edit amount in ${reference.code}`)).toHaveValue('1');
    await screen.getByRole('button', /^Bitcoin,/i).longPress({ duration: 650 });
    await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
    await agent.act('Select Details & history in the currently open Bitcoin row context menu. Finish when Bitcoin Details is visible, keeping the reference currency unchanged.');
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
    await assertPair();
    await app.screenshot(`bitcoin-details-${reference.code.toLowerCase()}-after-restart`);
  });
}

const bitcoinReferences = [
  { code: 'ETH', name: 'Ethereum', value: '0.002 BTC' },
  { code: 'VND', name: 'Vietnamese Dong', value: '0.0000000008 BTC' },
] as const;

for (const destination of bitcoinReferences) {
  test(`${destination.code} Details preserves a nonzero BTC reference`, { tags: ['core', 'providers'] }, async ({ start, app, agent, screen }) => {
    await start('ready-crypto');
    await agent.act('Open the source currency picker. Use its Search field to search BTC, then select the Bitcoin result and return to the converter without editing the amount.');
    await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Bitcoin/i);
    await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
    await agent.act(`Add ${destination.code} as a destination currency using Add currency and its Search field. Select the ${destination.name} result and finish on the converter. Keep Bitcoin as the source currency.`);
    await expect(screen.getByRole('button', new RegExp(`^${destination.name},`, 'i'))).toBeVisible();

    const assertPair = async () => {
      await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName(`1 ${destination.code} in BTC`);
      await expect(screen.getByTestId('currency.details.rate')).toHaveValue(destination.value);
    };
    await screen.getByRole('button', new RegExp(`^${destination.name},`, 'i')).longPress({ duration: 650 });
    await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
    await screen.getByRole('button', 'Details & history', { exact: true }).tap();
    await expect(screen.getByTestId(`currency.details.${destination.code}`)).toBeVisible();
    await app.screenshot(`${destination.code.toLowerCase()}-details-btc-opened`);
    await assertPair();
    const ranges = screen.getByTestId('currency.details.historyRange');
    for (const title of ['One month', 'One day']) {
      const range = ranges.getByRole('tab', title, { exact: true });
      await range.tap();
      await expect(range).toBeSelected();
      await assertPair();
      await expect(screen.getByText(destination.value, { exact: true })).toBeVisible();
    }
    await app.screenshot(`${destination.code.toLowerCase()}-details-btc-day-nonzero`);
    await screen.getByTestId('currency.details.close').tap();
    await expect(screen.getByTestId('currency.details.close')).toBeHidden();
    if (destination.code === 'ETH') {
      await app.restart();
      await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Bitcoin/i);
      await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
      await screen.getByRole('button', /^Ethereum,/i).longPress({ duration: 650 });
      await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
      await agent.act('Select Details & history in the currently open Ethereum row context menu. Finish when Ethereum Details is visible, keeping Bitcoin as the reference currency.');
      await expect(screen.getByTestId('currency.details.ETH')).toBeVisible();
      await assertPair();
      await app.screenshot('eth-details-btc-after-restart');
    }
  });
}
