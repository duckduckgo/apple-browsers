import generateCMPTests from '../playwright/runner';

generateCMPTests(
    'automattic-cmp-optout',
    ['https://automattic.com/', 'https://pocketcasts.com/', 'https://en.gravatar.com/', 'https://akismet.com/', 'https://wordpress.com/'],
    {},
);
