import generateCMPTests from '../playwright/runner';

generateCMPTests('youtube-mobile', ['https://m.youtube.com/'], {
    skipRegions: ['US'],
    mobile: true,
});
