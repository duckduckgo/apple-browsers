import generateCMPTests from '../playwright/runner';

generateCMPTests('om', [
    'https://olli-machts.de/en/extension/cookie-manager',
    'https://www.uni-assist.de/',
    'https://www.unisabana.edu.co/',
    'https://deutsche-alzheimer.de/',
    'https://avstumpfl.com/en/',
]);
