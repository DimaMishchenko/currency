import { test } from '../fixtures.js';
import { expect, type Locator } from 'e2e';

async function boundsOf(locator: Locator) {
  const bounds = await locator.boundingBox();
  if (!bounds) throw new Error('Visible Settings control has no native bounds.');
  return bounds;
}

test('settings creator footer aligns with native rows', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await agent.act('Scroll Settings until the Help section, Feedback row and bug/idea description are visible. Stay on Settings.');
  await expect(screen.getByText('Help')).toBeVisible();
  await expect(screen.getByTestId('settings.feedback')).toBeVisible();
  await expect(screen.getByText('Found a bug or have an idea? Send me your feedback.')).toBeVisible();
  await agent.act('Scroll Settings to the bottom. Finish with the About section, Privacy policy and Terms of use rows, centered creator portrait, all three contact buttons and complete Version footer visible.');
  await expect(screen.getByText('About')).toBeVisible();
  await expect(screen.getByTestId('settings.privacyPolicy')).toBeVisible();
  await expect(screen.getByTestId('settings.termsOfUse')).toBeVisible();
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.email')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.website')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.x')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.email')).toHaveAccessibleName('Email');
  await expect(screen.getByTestId('settings.contact.website')).toHaveAccessibleName('Website');
  await expect(screen.getByTestId('settings.contact.x')).toHaveAccessibleName('X');
  await expect(screen.getByTestId('settings.creator.coin')).toBeVisible();
  const privacyBounds = await boundsOf(screen.getByTestId('settings.privacyPolicy'));
  const emailBounds = await boundsOf(screen.getByTestId('settings.contact.email'));
  const websiteBounds = await boundsOf(screen.getByTestId('settings.contact.website'));
  const xBounds = await boundsOf(screen.getByTestId('settings.contact.x'));
  const coinBounds = await boundsOf(screen.getByTestId('settings.creator.coin'));
  expect(Math.abs(emailBounds.x - privacyBounds.x)).toBeLessThanOrEqual(1);
  expect(Math.abs(xBounds.x + xBounds.width - privacyBounds.x - privacyBounds.width)).toBeLessThanOrEqual(1);
  for (const bounds of [emailBounds, websiteBounds, xBounds]) {
    expect(bounds.height).toBeGreaterThanOrEqual(44);
    expect(Math.abs(bounds.height - 44)).toBeLessThanOrEqual(1);
    expect(Math.abs(bounds.height - emailBounds.height)).toBeLessThanOrEqual(1);
    expect(Math.abs(bounds.width - emailBounds.width)).toBeLessThanOrEqual(1);
    expect(Math.abs(bounds.y - emailBounds.y)).toBeLessThanOrEqual(1);
  }
  expect(Math.abs(coinBounds.x + coinBounds.width / 2 - privacyBounds.x - privacyBounds.width / 2)).toBeLessThanOrEqual(1);
  await app.screenshot('settings-creator-light');
  await expect(screen.getByTestId('settings.creator.coin')).toBeVisible();
  await expect(screen.getByTestId('settings.version')).toBeVisible();
});

test('appearance preference survives app restart', { tags: ['core'] }, async ({ start, agent, app, screen, device }) => {
  await start('ready-converter');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await expect(screen.getByTestId('settings.theme')).toBeVisible();
  const theme = screen.getByTestId('settings.theme');
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, System');

  await theme.getByText('System').tap();
  await agent.act('Choose Dark in the open Theme menu. Stay on Settings with the theme menu closed.');
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await agent.act('Scroll Settings to the bottom to show the About legal rows, creator portrait, all three contact buttons and Version.');
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.email')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.website')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.x')).toBeVisible();
  await app.screenshot('settings-dark-theme');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await app.screenshot('settings-dark-theme-after-restart');
  const version = screen.getByTestId('settings.version');
  await agent.act('Scroll Settings to the very bottom so the complete Version label is visible above the home indicator. Do not leave Settings.');
  await expect(version).toBeVisible();
  await expect(version).toHaveAccessibleName(/^Version \S+ · Build \S+$/);
  const versionBounds = await boundsOf(version);
  const viewport = await boundsOf(device.locator('role=Application'));
  expect(versionBounds.width).toBeGreaterThan(0);
  expect(versionBounds.height).toBeGreaterThan(0);
  expect(versionBounds.x).toBeGreaterThanOrEqual(viewport.x);
  expect(versionBounds.y).toBeGreaterThanOrEqual(viewport.y);
  expect(versionBounds.x + versionBounds.width).toBeLessThanOrEqual(viewport.x + viewport.width);
  expect(versionBounds.y + versionBounds.height).toBeLessThanOrEqual(viewport.y + viewport.height - 20);
  await app.screenshot('settings-version');
});
