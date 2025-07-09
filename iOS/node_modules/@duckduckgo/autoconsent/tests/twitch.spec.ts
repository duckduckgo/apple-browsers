import generateCMPTests from '../playwright/runner';

generateCMPTests('twitch.tv', ['https://www.twitch.tv/'], {
    skipRegions: ['US'],
});
