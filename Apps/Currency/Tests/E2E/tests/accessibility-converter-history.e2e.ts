import { join } from 'node:path';
import assert from 'node:assert/strict';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { readHistory, sharedDirectory } from './history-cache.js';

test('history values select an exact dated rate without a chart gesture', {
  tags: ['core', 'accessibility-converter-history'],
}, async ({ start, screen, agent, app }) => {
  await start('ready-converter');
  await screen.getByRole('button', 'Edit amount in EUR', { exact: true }).tap();
  await screen.getByTestId('converter.history').tap();
  const month = screen.getByTestId('currency.details.historyRange')
    .getByRole('tab', 'One month', { exact: true });
  await month.tap();
  await expect(month).toBeSelected();
  const history = readHistory(join(sharedDirectory(), 'history-v3-EUR-USD-30.json'));
  const first = history.points[0]!;
  const date = new Intl.DateTimeFormat('en-US', {
    year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC',
  }).format(new Date((first.date + 978_307_200) * 1000));
  const value = `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 6 }).format(first.value)} USD`;
  const detailsBounds = await screen.getByTestId('currency.details.EUR').boundingBox();
  assert.ok(detailsBounds, 'Details must have a visible sheet for history navigation');
  await screen.swipe({
    from: { x: detailsBounds.x + detailsBounds.width / 2, y: detailsBounds.y + detailsBounds.height * 0.8 },
    to: { x: detailsBounds.x + detailsBounds.width / 2, y: detailsBounds.y + detailsBounds.height * 0.25 },
  });
  const values = screen.getByTestId('currency.details.historyValues')
    .filter({ hasText: /^History values$/ });
  await expect(values).toBeVisible();
  await expect(values).toHaveValue('Collapsed');
  await values.tap();
  await expect(values).toHaveValue('Expanded');
  const point = screen.getByRole('button', date, { exact: true });
  await expect(point).toBeVisible();
  await expect(point).toHaveAccessibleName(date);
  await expect(point).toHaveValue(value);
  await point.tap();
  await expect(point).toBeSelected();
  await app.screenshot('history-values-selected-dated-point');
  await values.tap();
  await expect(values).toHaveValue('Collapsed');
  await expect(point).toBeHidden();
  await app.screenshot('history-values-collapsed-selection-retained');
  await agent.act('Scroll to the top of Details until the selected history value and date above the chart are visible.');
  await expect(screen.getByTestId('currency.details.selectedDate')).toHaveText(date);
  await expect(screen.getByTestId('currency.details.selectedValue')).toHaveText(value);
});

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
