import { test } from '../fixtures.js';
import { expect } from 'e2e';
import { deviceProfile } from '../device-profile.js';

test('creator website opens in Safari and preserves Settings', { tags: ['core'] }, async ({ start, agent, app, screen, device }) => {
  await device.openApp('com.apple.mobilesafari');
  await device.openLink('https://example.com', { app: 'com.apple.mobilesafari' });
  const address = deviceProfile === 'ipad'
    ? screen.getByTestId(/^SafariWindow\?/).getByTestId('TabBarItemTitleContainer').first()
    : screen.getByLabel('Address', { exact: true });
  await expect(address).toHaveValue(/^(?:\u200e)?(?:https:\/\/)?example\.com\/?$/);
  await start('ready-converter');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await agent.act('Scroll Settings to the bottom so the About section, creator footer and Website contact button are visible.');
  await screen.getByTestId('settings.contact.website').tap();
  await device.openApp('com.apple.mobilesafari');
  await expect(address).toHaveValue(/^(?:\u200e)?(?:https:\/\/)?dimasike\.com\/?$/);
  await app.screenshot('creator-website-safari');
  await device.openApp('com.dimasike.currency');
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
  await agent.act('Scroll Settings to the top so Theme is visible.');
  await expect(screen.getByTestId('settings.theme')).toHaveAccessibleName('Theme, System');
});

test('feedback email fallback and X preserve Settings', { tags: ['core'] }, async ({ start, agent, app, screen, device }) => {
  await device.openApp('com.apple.mobilesafari');
  await device.openLink('https://example.com', { app: 'com.apple.mobilesafari' });
  const address = deviceProfile === 'ipad'
    ? screen.getByTestId(/^SafariWindow\?/).getByTestId('TabBarItemTitleContainer').first()
    : screen.getByLabel('Address', { exact: true });
  await expect(address).toHaveValue(/^(?:\u200e)?(?:https:\/\/)?example\.com\/?$/);
  await start('ready-converter');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await agent.act('Scroll Settings until the Help section, its single Feedback row and bug/idea description are visible. Keep Feedback visible; the creator footer is in the separate About section below.');
  const feedback = screen.getByTestId('settings.feedback');
  const emailOption = screen.getByTestId('settings.feedback.email').last();
  const xOption = screen.getByTestId('settings.feedback.x').last();
  await expect(screen.getByText('Help')).toBeVisible();
  await expect(feedback).toBeVisible();
  await expect(screen.getByText('Found a bug or have an idea? Send me your feedback.')).toBeVisible();
  await feedback.tap();
  await expect(emailOption).toBeVisible();
  await expect(xOption).toBeVisible();
  await app.screenshot('feedback-options');
  await screen.getByRole('button', 'Close').tap();
  await expect(feedback).toBeVisible();
  await feedback.tap();
  await emailOption.tap();
  await expect(screen.getByText('Email is unavailable')).toBeVisible();
  await expect(screen.getByText('dimasike.dev@gmail.com')).toBeVisible();
  await app.screenshot('feedback-email-fallback');
  await screen.getByRole('button', 'Copy email').tap();
  await expect(feedback).toBeVisible();
  await feedback.tap();
  await xOption.tap();
  await device.openApp('com.apple.mobilesafari');
  await expect(address).toHaveValue(/(?:x\.com|twitter\.com)/);
  await app.screenshot('feedback-x-safari');
  await device.openApp('com.dimasike.currency');
  await expect(feedback).toBeVisible();
  await expect(screen.getByText('Help')).toBeVisible();
});
