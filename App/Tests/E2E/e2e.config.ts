import { mobile } from '@e2e-dev/mobile';
import type { E2EConfig } from 'e2e';
import { chatgpt } from 'e2e/oauth/chatgpt';
import { targetName } from './device-profile.js';

const udid = process.env.CURRENCY_E2E_UDID?.trim();
if (!udid) {
  throw new Error('Set CURRENCY_E2E_UDID to your dedicated simulator UUID.');
}

export default {
  tests: 'tests/**/*.e2e.ts',
  targets: [
    {
      name: targetName,
      engine: mobile({ platform: 'ios', device: udid, session: `currency-e2e-${targetName}` }),
      app: {
        identity: 'currency-fixtures-v1',
        bundleId: 'com.dimasike.currency',
        appPath: '../../../.validation/e2e/DerivedData/Build/Products/Debug-iphonesimulator/Currency.app',
        launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-CurrencyE2E'],
      },
    },
  ],
  workers: 1,
  timeout: 300_000,
  launchTimeout: 120_000,
  agents: {
    default: {
      model: chatgpt('gpt-6-luna'),
      providerOptions: { openai: { reasoningEffort: 'low' } },
    },
  },
} satisfies E2EConfig;
