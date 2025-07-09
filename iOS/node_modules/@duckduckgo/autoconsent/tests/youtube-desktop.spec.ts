import generateCMPTests from '../playwright/runner';

generateCMPTests('youtube-desktop', ['https://youtube.com/'], {
    skipRegions: ['US'],
});
