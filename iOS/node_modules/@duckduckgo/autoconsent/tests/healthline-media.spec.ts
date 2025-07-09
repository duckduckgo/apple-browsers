import generateCMPTests from '../playwright/runner';

generateCMPTests('healthline-media', ['https://www.healthline.com/', 'https://www.medicalnewstoday.com/'], {});
