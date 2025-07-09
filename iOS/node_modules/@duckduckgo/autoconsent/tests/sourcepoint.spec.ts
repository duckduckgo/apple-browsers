import generateCMPTests from '../playwright/runner';

generateCMPTests('Sourcepoint-frame', ['https://www.theguardian.com/', 'https://news.sky.com/', 'https://www.economist.com/']);

generateCMPTests(
    'Sourcepoint-frame',
    [
        'https://www.insider.com/',
        'https://www.techtarget.com/searchvirtualdesktop/',
        // "https://www.csoonline.com/blogs", // settings button doesn't work
        'https://www.independent.co.uk/',
        'https://reitschuster.de/',
    ],
    {
        skipRegions: ['US', 'GB'],
    },
);

generateCMPTests(
    'Sourcepoint-frame',
    ['https://www.sueddeutsche.de/', 'https://www.derstandard.at/', 'https://www.heise.de/', 'https://www.n-tv.de/'],
    {
        skipRegions: ['US', 'GB', 'FR'],
        expectPopupOpen: false,
        testOptIn: false,
        testOptOut: false,
        testSelfTest: false,
    },
);
