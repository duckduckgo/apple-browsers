import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'click.io',
    ['https://www.propertywire.com/', 'https://pedsovet.su/', 'https://golftoday.co.uk/', 'https://www.golfshake.com/'],
    {
        skipRegions: ['US'],
    },
);
