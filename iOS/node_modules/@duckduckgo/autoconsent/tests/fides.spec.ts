import generateCMPTests from '../playwright/runner';

generateCMPTests('fides', ['https://www.nytimes.com/', 'https://nextjs.org/', 'https://wetransfer.com/']);
