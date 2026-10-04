import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('source changes and added or removed currencies survive restart', { tags: ['core'] }, async ({ start, app, agent, screen }) => {
  await start('ready-converter');
  const source = screen.getByTestId('converter.source');
  const euros = screen.getByRole('button', /^Euro,/i);
  const francs = screen.getByRole('button', /^Swiss Franc,/i);
  const korunas = screen.getByRole('button', /^Czech Koruna,/i);
  await expect(source).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');

  await agent.act('Open the source currency picker. Use its Search field to search USD, then select the US Dollar result and return to the converter without editing the amount.');
  await expect(source).toHaveAccessibleName(/US Dollar/i);
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(euros).toHaveAccessibleName(/^Euro, 0\.5$/i);
  await expect(screen.getByRole('button', /^US Dollar,/i)).toBeHidden();

  await agent.act('Add CHF as a destination currency using Add currency and its Search field. Select the Swiss Franc result and finish on the converter. Keep US Dollar as the source currency.');
  await expect(source).toHaveAccessibleName(/US Dollar/i);
  await expect(francs).toHaveAccessibleName(/^Swiss Franc, 0\.25$/i);
  await agent.act('Add CZK as a destination currency using Add currency and its Search field. Select the Czech Koruna result and finish on the converter with EUR, CHF and CZK destination rows visible. Keep US Dollar as the source currency.');
  await expect(source).toHaveAccessibleName(/US Dollar/i);
  await expect(euros).toHaveAccessibleName(/^Euro, 0\.5$/i);
  await expect(francs).toHaveAccessibleName(/^Swiss Franc, 0\.25$/i);
  await expect(korunas).toHaveAccessibleName(/^Czech Koruna, 12\.5$/i);

  await agent.act('Open Options, then Manage currencies. Delete only the Euro (EUR) destination using the list editing controls, then close Manage currencies and return to the converter. Keep Swiss Franc and Czech Koruna.');
  await expect(euros).toBeHidden();
  await expect(francs).toHaveAccessibleName(/^Swiss Franc, 0\.25$/i);
  await expect(korunas).toHaveAccessibleName(/^Czech Koruna, 12\.5$/i);

  await app.restart();
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(source).toHaveAccessibleName(/US Dollar/i);
  await expect(screen.getByRole('button', 'Edit amount in USD')).toHaveValue('1');
  await expect(euros).toBeHidden();
  await expect(francs).toHaveAccessibleName(/^Swiss Franc, 0\.25$/i);
  await expect(korunas).toHaveAccessibleName(/^Czech Koruna, 12\.5$/i);
  await app.screenshot('currency-selection-persisted-usd-chf-czk');
});
