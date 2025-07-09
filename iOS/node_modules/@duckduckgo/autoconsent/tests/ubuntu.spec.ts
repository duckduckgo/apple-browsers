import generateCMPTests from '../playwright/runner';

generateCMPTests('ubuntu.com', ['https://ubuntu.com/', 'https://canonical.com/', 'https://snapcraft.io/'], {});
