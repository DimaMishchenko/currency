import { test } from '../fixtures.js';
import { expect } from 'e2e';
import { deviceProfile } from '../device-profile.js';

test('creator website opens in Safari and preserves Settings', { tags: ['core'] }, async ({ start, agent, app, screen, device }) => {
  await device.openApp('com.apple.mobilesafari');
  await device.openLink('https://example.com', { app: 'com.apple.mobilesafari' });
  const address = deviceProfile === 'ipad'
    ? screen.getByTestId(/^SafariWindow\?/).getByTestId('TabBarItemTitleContainer').first()
    : screen.getByTestId('TabBarItemTitle');
  await expect(address).toHaveValue(/^(?:\u200e)?(?:https:\/\/)?example\.com\/?$/);
  await start('ready-converter');
  await agent.act('Open Options and tap Settings. Finish on the Settings screen showing Theme and Accent color.');
  await agent.act('Scroll Settings to the very bottom so the creator footer and Website contact button are visible.');
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
    : screen.getByTestId('TabBarItemTitle');
  await expect(address).toHaveValue(/^(?:\u200e)?(?:https:\/\/)?example\.com\/?$/);
  await start('ready-converter');
  await agent.act('Open Options and tap Settings, then scroll to the very bottom to show the single Feedback row and its bug/idea description above the creator portrait.');
  const feedback = screen.getByTestId('settings.feedback');
  const emailOption = screen.getByTestId('settings.feedback.email').last();
  const xOption = screen.getByTestId('settings.feedback.x').last();
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
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
});
