import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { completeConversion, dismissNativeReview, expectNoReview } from './review-support.js';

test('third completed conversion requests native review and persists the consumed batch', { tags: ['core'] }, async ({ start, screen, app, agent }) => {
  const context = { screen, app, agent };
  await start('ready-converter');
  await expectNoReview(context, 0);
  await completeConversion(context, '4');
  await expectNoReview(context, 1);
  await completeConversion(context, '2');
  await expectNoReview(context, 2);

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('2');
  await expectNoReview(context, 2);
  await completeConversion(context, '4');
  await dismissNativeReview(context, 'native-review-after-third-conversion');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('4');
  await expectNoReview(context, 0);
  await app.screenshot('converter-after-review-dismissal-and-restart');
});

test('opening the currency picker cancels pending review until another completed conversion', { tags: ['core'] }, async ({ start, screen, app, agent }) => {
  const context = { screen, app, agent };
  await start('ready-converter');
  await completeConversion(context, '4');
  await completeConversion(context, '2');
  await completeConversion(context, '4');
  await screen.getByTestId('converter.source').tap();
  await expectNoReview(context, 3);
  await screen.getByTestId('currency.picker.close').tap();
  await expectNoReview(context, 3);
  await completeConversion(context, '2');
  await dismissNativeReview(context, 'native-review-after-fresh-conversion');
});

for (const target of ['source', 'destination'] as const) {
  test(`${target} context menu cancels a pending review`, { tags: ['core'] }, async ({ start, screen, app, agent }) => {
    const context = { screen, app, agent };
    await start('ready-converter');
    await completeConversion(context, '4');
    await completeConversion(context, '2');
    await completeConversion(context, '4');
    const amount = target === 'source'
      ? screen.getByRole('button', 'Edit amount in EUR', { exact: true })
      : screen.getByRole('button', /^US Dollar,/);
    await amount.longPress({ duration: 650 });
    await expect(screen.getByRole('button', 'Details & history', { exact: true })).toBeVisible();
    await expectNoReview(context, 3);
    await app.screenshot(`review-deferred-for-${target}-context-menu`);
    await app.restart();
    await expectNoReview(context, 3);
    await completeConversion(context, '2');
    await dismissNativeReview(context, `native-review-after-${target}-menu-dismissal`);
  });
}
