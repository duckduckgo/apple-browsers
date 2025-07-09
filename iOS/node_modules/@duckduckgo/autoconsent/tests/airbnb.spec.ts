import generateCMPTests from '../playwright/runner';

generateCMPTests('airbnb', ['https://airbnb.nl', 'https://airbnb.co.uk'], {
    skipRegions: ['US'],
});
