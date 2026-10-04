export const deviceProfile = process.env.CURRENCY_E2E_TARGET ?? 'iphone';

if (!['iphone', 'ipad', 'duo-open', 'duo-closed'].includes(deviceProfile)) {
  throw new Error('CURRENCY_E2E_TARGET must be iphone, ipad, duo-open or duo-closed.');
}

export const targetName = deviceProfile === 'iphone' ? 'owned-iphone' : deviceProfile;
