import generateCMPTests from '../playwright/runner';

generateCMPTests('EZoic', ['https://computingforgeeks.com/'], {
    skipRegions: ['US'],
});
