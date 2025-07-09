import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'WP DSGVO Tools',
    [
        'https://ccmedia.ch/',
        'https://rlalpbsl.web.belwue.de/',
        // 'https://www.mathe-lerntipps.de/', // https://github.com/duckduckgo/autoconsent/issues/80
    ],
    {
        skipRegions: ['US'],
    },
);
