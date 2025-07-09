import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'Evidon',
    [
        'https://www.crunchyroll.com/',
        'https://www.kia.com/us/en', // "I agree" button is actually a decline button
    ],
    {
        testOptIn: false,
        skipRegions: ['US'],
    },
);
