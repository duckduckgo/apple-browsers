import generateCMPTests from '../playwright/runner';

generateCMPTests('tiktok.com', ['https://tiktok.com/'], {
    skipRegions: ['US'],
});

generateCMPTests('tiktok.com', ['https://tiktok.com/'], {
    skipRegions: ['US'],
    mobile: true,
});
