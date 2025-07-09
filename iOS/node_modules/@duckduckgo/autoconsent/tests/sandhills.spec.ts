import generateCMPTests from '../playwright/runner';

generateCMPTests('sandhills', [
    'https://www.tractorhouse.com/',
    'https://www.machinerytrader.com/',
    'https://www.controller.com/',
    'https://www.truckpaper.com/',
]);
