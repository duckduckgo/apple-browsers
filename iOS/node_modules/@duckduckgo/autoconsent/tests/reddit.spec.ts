import generateCMPTests from '../playwright/runner';

generateCMPTests('reddit.com', ['https://www.reddit.com/r/AskReddit/'], {
    mobile: false,
    skipRegions: ['US', 'DE', 'FR', 'GB'], // https://github.com/duckduckgo/autoconsent/issues/82
});
