import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Uniconsent',
    [
        // 'https://sport-stimme.de/', // see https://github.com/duckduckgo/autoconsent/issues/81
        'https://www.sharethrough.com/',
    ],
    {},
);

generateCMPTests('Uniconsent', ['https://www.vivobarefoot.com/eu/'], {
    skipRegions: ['US'],
});
