import generateCMPTests from '../playwright/runner';

generateCMPTests('dailymotion.com', ['https://www.dailymotion.com/us'], {
    skipRegions: ['US'],
});

generateCMPTests('dailymotion.com', ['https://www.dailymotion.com/us'], {
    skipRegions: ['US'],
    mobile: true,
});
