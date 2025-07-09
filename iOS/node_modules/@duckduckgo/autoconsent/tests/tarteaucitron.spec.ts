import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'tarteaucitron.js',
    [
        'https://planetside2.com',
        'https://marseille.intercontinental.com/',
        'https://www.powellflutes.com/en/',
        'https://www.neweuropetours.eu/',
    ],
    {},
);
