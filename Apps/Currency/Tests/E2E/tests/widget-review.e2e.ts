import { expect } from 'e2e';
import { test, tapCalculatorControl } from '../widget-fixtures.js';
import { unloadWidgetHelper } from '../simulator-widgets.js';
import { completeConversion, dismissNativeReview, expectNoReview, reviewUsageCount } from './review-support.js';

test('Calculator widget session contributes once to the next in-app review request', { tags: ['extended', 'widgets'] }, async ({ calculator, screen, app, agent }) => {
  const context = { screen, app, agent };
  await tapCalculatorControl(calculator, 'EUR');
  await tapCalculatorControl(calculator, 'Clear');
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('0');
  await tapCalculatorControl(calculator, '4');
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('8');
  await expect.poll(reviewUsageCount, { timeout: 10_000 }).toBe(1);
  await tapCalculatorControl(calculator, '2');
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('84');
  await agent.assert('The Currency Calculator widget shows EUR 42 and USD 84, with the complete amounts readable.', { vision: 'only' });
  await expectNoReview(context, 1);
  await app.screenshot('calculator-review-usage-one-session');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('42');
  await expectNoReview(context, 1);
  await completeConversion(context, '2');
  await expectNoReview(context, 2);
  await completeConversion(context, '4');
  await dismissNativeReview(context, 'native-review-includes-calculator-session');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
