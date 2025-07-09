import generateCMPTests from '../playwright/runner';

generateCMPTests('cookie-law-info', ['https://www.omas-gegen-rechts.org/', 'https://www.fitundattraktiv.de/'], {
    skipRegions: ['US', 'GB'],
});

generateCMPTests('cookie-law-info', ['https://www.sbid.org/']);
