import generateCMPTests from '../playwright/runner';

generateCMPTests('takealot.com', ['https://www.takealot.com/'], {
    mobile: false,
});

generateCMPTests('takealot.com', ['https://www.takealot.com/'], {
    mobile: true,
});
