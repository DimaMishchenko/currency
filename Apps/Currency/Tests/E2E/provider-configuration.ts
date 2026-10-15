import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../Modules/CurrencyApplication/Sources/CurrencyRateConfiguration.swift', import.meta.url), 'utf8');
const flag = source.match(/intradayEnabled\s*=\s*(true|false)\b/);
if (!flag) throw new Error('Expected the Boolean CurrencyRateConfiguration.intradayEnabled in source.');
export const intradayEnabled = flag[1] === 'true';
