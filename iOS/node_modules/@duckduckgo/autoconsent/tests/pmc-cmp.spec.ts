import generateCMPTests from '../playwright/runner';

generateCMPTests('pmc', ['https://www.rollingstone.com/', 'https://www.hollywoodreporter.com/'], {});
