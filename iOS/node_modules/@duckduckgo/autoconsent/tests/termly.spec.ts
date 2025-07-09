import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Termly',
    [
        'https://itsalovelylife.com/',
        'https://www.iccsafe.org/',
        'https://cooper.edu/',
        'https://www.chateauelan.com/',
        'https://www.bentley.edu/',
    ],
    {},
);

generateCMPTests('Termly', ['https://visualsbyimpulse.com/'], {
    skipRegions: ['DE'],
});
