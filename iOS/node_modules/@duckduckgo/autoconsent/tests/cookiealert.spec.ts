import generateCMPTests from '../playwright/runner';

generateCMPTests('cookiealert', ['https://www.kaufland.de/'], {
    skipRegions: ['US', 'GB', 'FR'],
    testSelfTest: false,
});
