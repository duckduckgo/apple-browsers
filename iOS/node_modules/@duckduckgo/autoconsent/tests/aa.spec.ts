import generateCMPTests from '../playwright/runner';

generateCMPTests('aa', ['https://www.aa.com/homePage.do'], {
    onlyRegions: ['US'],
});
