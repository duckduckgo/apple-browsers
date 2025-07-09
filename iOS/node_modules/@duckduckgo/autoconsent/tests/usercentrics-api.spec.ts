import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'usercentrics-api',
    [
        'https://hornbach.de',
        'https://dm.de', // unsafe-eval CSP
        'https://usercentrics.com/',
        'https://shopbetreiber-blog.de/',
        'https://www.kia.com/us/en',
        'https://www.sportscheck.com/filialen/dortmund/',
        'https://www.idealo.de/',
    ],
    {
        skipRegions: ['US', 'GB', 'FR'],
    },
);
