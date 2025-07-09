import generateCMPTests from '../playwright/runner';

generateCMPTests('dmgmedia', ['https://www.dailymail.co.uk/', 'https://metro.co.uk/'], {
    skipRegions: ['US'],
});

generateCMPTests('dmgmedia', ['https://www.dailymail.co.uk/', 'https://metro.co.uk/'], {
    skipRegions: ['US'],
    mobile: true,
});
