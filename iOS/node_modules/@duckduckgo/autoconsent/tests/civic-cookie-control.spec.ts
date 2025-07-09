import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'civic-cookie-control',
    ['https://www.birmingham.gov.uk/', 'https://planning.org.uk/', 'https://www.jessops.com/', 'https://www.bcs.org/'],
    {
        skipRegions: ['US', 'DE'],
    },
);
