import { test as mobileTest } from '@e2e-dev/mobile';
import { deviceProfile } from './device-profile.js';

type InitialState = 'fresh-onboarding' | 'ready-converter' | 'ready-metals' | 'ready-metal-source';
const worker = globalThis as typeof globalThis & { currencyE2EInstallation?: Promise<unknown> };

export const test = mobileTest.extend<{ start: (state: InitialState) => Promise<void> }>({
  start: async ({ device }, use) => {
    worker.currencyE2EInstallation ??= device.installApp();
    try {
      await worker.currencyE2EInstallation;
    } catch (error) {
      delete worker.currencyE2EInstallation;
      throw error;
    }
    await use(async (state) => {
      await device.openApp('com.dimasike.currency', {
        relaunch: true,
        launchArguments: [
          '-AppleLanguages', '(en)', '-AppleLocale', 'en_US',
          '-CurrencyE2E', '-CurrencyE2EState', state,
        ],
      });
      if (deviceProfile === 'duo-open' || deviceProfile === 'duo-closed') {
        await device.fold(deviceProfile === 'duo-open' ? 'open' : 'closed');
      }
      if (deviceProfile !== 'iphone') {
        await device.setOrientation(deviceProfile === 'duo-open' ? 'landscape-left' : 'portrait');
      }
    });
  },
});
