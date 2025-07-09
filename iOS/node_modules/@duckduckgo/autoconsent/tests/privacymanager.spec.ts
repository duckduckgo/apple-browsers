import generateCMPTests from '../playwright/runner';

generateCMPTests('privacymanager.io', ['https://linuxhint.com/', 'https://www.immmo.at/'], {
    skipRegions: ['US'],
});
