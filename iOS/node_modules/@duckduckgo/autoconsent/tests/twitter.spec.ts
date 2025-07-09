import generateCMPTests from '../playwright/runner';

generateCMPTests('twitter', ['https://mobile.twitter.com/', 'https://twitter.com/'], {
    skipRegions: ['US'],
});

generateCMPTests('twitter', ['https://mobile.twitter.com/', 'https://twitter.com/'], {
    skipRegions: ['US'],
    mobile: true,
});
