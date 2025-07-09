import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'xhamster-eu',
    [
        'https://xhamster.com/',
        'https://xhamster2.com/',
        'https://xhamster3.com/',
        'https://www.xhamster.com/',
        'https://www.xhamster2.com/',
    ],
    {},
);
