import generateCMPTests from '../playwright/runner';

generateCMPTests('dmgmedia-us', ['https://www.dailymail.co.uk/ushome/index.html', 'https://metro.co.uk/'], {
    skipRegions: ['DE', 'FR', 'GB', 'NL'],
});
