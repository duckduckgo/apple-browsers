import generateCMPTests from '../playwright/runner';

generateCMPTests('tropicfeel-com', ['https://shop.tropicfeel.com/'], {
    skipRegions: [],
});
