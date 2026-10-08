import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('settings groups expose rates, credits and legal links', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await expect(screen.getByText('Personalization', { exact: true })).toBeVisible();
  await screen.getByTestId('settings.rates').tap();
  await expect(screen.getByText('Rates retrieved', { exact: true })).toBeVisible();
  await expect(screen.getByText(/Estimates only, not financial advice/)).toBeVisible();
  await screen.getByRole('button', 'Settings', { exact: true }).tap();
  await screen.getByTestId('settings.sources').tap();
  await expect(screen.getByText('Frankfurter', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Settings', { exact: true }).tap();
  await agent.act('Scroll Settings until the About section with Acknowledgements, Privacy policy and Terms of use is visible. Stay in Settings.');
  await expect(screen.getByText('About', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('settings.privacyPolicy')).toBeVisible();
  await expect(screen.getByTestId('settings.termsOfUse')).toBeVisible();
  await screen.getByTestId('settings.acknowledgements').tap();
  await expect(screen.getByText('Web3 Icons', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Settings', { exact: true }).tap();
  await expect(screen.getByTestId('settings.privacyPolicy')).toBeVisible();
  await app.screenshot('settings-legal-information');
});
