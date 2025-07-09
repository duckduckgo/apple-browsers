import generateCMPTests from '../playwright/runner';

generateCMPTests('pinterest-business', [
    'https://business.pinterest.com/en-gb/',
    'https://newsroom.pinterest.com/en-gb/news/introducing-new-ai-tools-for-creative-and-performance/',
]);
