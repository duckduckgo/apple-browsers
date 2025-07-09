import generateCMPTests from '../playwright/runner';

generateCMPTests('gov.uk', ['https://gov.uk', 'https://data.gov.uk', 'https://sorn.service.gov.uk/'], {
    skipRegions: ['US', 'FR', 'DE'],
});
