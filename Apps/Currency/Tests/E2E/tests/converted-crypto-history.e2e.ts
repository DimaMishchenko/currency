import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('converted Bitcoin day history exposes its dated USD to EUR reference input', { tags: ['extended', 'live-providers'] }, async ({ start, screen, agent, app }) => {
  await start('ready-converter');
  await agent.act('Add Bitcoin (BTC) as another destination currency. Keep Euro as the source currency. Return to the converter.');
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', /^Bitcoin,/i)).toBeVisible();
  await agent.act('Open Details & history for the Bitcoin destination currency.');
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 BTC in EUR');
  const day = screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One day', { exact: true });
  await day.tap();
  await expect(day).toBeSelected();
  const source = screen.getByTestId('currency.details.sourceDisclosure').filter({ hasText: /Coin Metrics.*minute reference prices.*approximate conversion/i });
  await expect(source).toBeVisible({ timeout: 90_000 });
  await app.screenshot('crypto-converted-day-chart-approximate-source');
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', process.env.CURRENCY_E2E_UDID!, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const saved = JSON.parse(readFileSync(join(directory, 'history-v2-intradayEnhanced-BTC-EUR-1.json'), 'utf8')) as {
    points: { value: number }[];
    source: { conversion: { base: string; quote: string; value: number; published: string } };
  };
  assert.ok(saved.points.length >= 270);
  assert.equal(saved.source.conversion.base, 'USD');
  assert.equal(saved.source.conversion.quote, 'EUR');
  assert.ok(Number(saved.source.conversion.value) > 0);
  assert.match(saved.source.conversion.published, /^\d{4}-\d{2}-\d{2}$/);
  await source.tap();
  await expect(source).toHaveValue('Expanded');
  await agent.act('Scroll Details until the historical conversion input beginning "Approximate conversion: 1 USD" is visible. Keep the source disclosure expanded.');
  await expect(screen.getByText(/Approximate conversion: 1 USD = .+ EUR \(Fawaz,/i)).toBeVisible();
  await app.screenshot('crypto-converted-day-expanded-historical-fx-input');
  await agent.act('Scroll Details until the explanatory paragraph beginning "Crypto history combines daily and monthly reference data" is fully visible. Keep the source disclosure expanded.');
  await expect(screen.getByText('Crypto history combines daily and monthly reference data with intraday prices when available. Converted prices may be approximate. Historical and current sources can differ.')).toBeVisible();
  await app.screenshot('crypto-converted-day-explanation-and-observation-labels');
});
