import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { deviceProfile } from '../device-profile.js';

test('settings groups expose rates, credits and legal links', { tags: ['core'] }, async ({ start, agent, app, screen, device }) => {
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
  await agent.act('Scroll Settings until the About section with Acknowledgements, Privacy policy, Terms of use and Open source is visible. Stay in Settings.');
  await expect(screen.getByText('About', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('settings.privacyPolicy')).toBeVisible();
  await expect(screen.getByTestId('settings.termsOfUse')).toBeVisible();
  await expect(screen.getByTestId('settings.openSource')).toBeVisible();
  await screen.getByTestId('settings.acknowledgements').tap();
  await expect(screen.getByText('Web3 Icons', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Settings', { exact: true }).tap();
  await expect(screen.getByTestId('settings.privacyPolicy')).toBeVisible();
  await app.screenshot('settings-legal-information');
  await screen.getByTestId('settings.openSource').tap();
  await device.openApp('com.apple.mobilesafari');
  const address = deviceProfile === 'ipad'
    ? screen.getByTestId(/^SafariWindow\?/).getByTestId('TabBarItemTitleContainer').first()
    : screen.getByLabel('Address', { exact: true });
  await expect(screen.getByRole('link', 'DimaMishchenko', { exact: true }).first()).toBeVisible();
  await expect(screen.getByRole('link', 'currency', { exact: true }).first()).toBeVisible();
  await address.tap();
  const fullAddress = screen.getByRole('textbox').first();
  await expect(fullAddress).toBeVisible();
  await expect(fullAddress).toHaveValue(/^(?:\u200e)?https:\/\/github\.com\/DimaMishchenko\/currency\/?$/i);
  await app.screenshot('settings-open-source-url');
  const cancelAddressEditing = screen.getByRole('button', 'Cancel', { exact: true });
  if (await cancelAddressEditing.isVisible()) await cancelAddressEditing.tap();
  await app.screenshot('settings-open-source-github');
  await device.openApp('com.dimasike.currency');
  await expect(screen.getByTestId('settings.openSource')).toBeVisible();
  await expect(screen.getByText('About', { exact: true })).toBeVisible();
});
