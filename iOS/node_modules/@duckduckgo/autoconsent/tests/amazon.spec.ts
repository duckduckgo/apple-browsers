import generateCMPTests from '../playwright/runner';

generateCMPTests('amazon.com', ['https://www.amazon.co.uk/', 'https://www.amazon.de/', 'https://www.amazon.nl/'], {
    mobile: true,
});

generateCMPTests('amazon.com', ['https://www.amazon.co.uk/', 'https://www.amazon.de/', 'https://www.amazon.nl/'], {
    mobile: false,
});
