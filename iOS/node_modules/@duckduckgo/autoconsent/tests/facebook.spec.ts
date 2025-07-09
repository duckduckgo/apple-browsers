import generateCMPTests from '../playwright/runner';

generateCMPTests('facebook', ['https://facebook.com/'], {
    skipRegions: ['US'],
});

generateCMPTests('facebook', ['https://facebook.com/'], {
    mobile: true,
    skipRegions: ['US'],
});
