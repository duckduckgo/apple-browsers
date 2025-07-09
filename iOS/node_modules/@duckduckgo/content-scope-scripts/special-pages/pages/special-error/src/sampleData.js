/** @type {Record<string, { name: string, data: import('../types/special-error.ts').InitialSetupResponse['errorData']}>} */
export const sampleData = {
    phishing: {
        name: 'Phishing',
        data: {
            kind: 'phishing',
            url: 'https://privacy-test-pages.site/security/badware/phishing.html?query=param&some=other',
        },
    },
    malware: {
        name: 'Malware',
        data: {
            kind: 'malware',
            url: 'https://privacy-test-pages.site/security/badware/malware.html?query=param&some=other',
        },
    },
    scam: {
        name: 'Scam',
        data: {
            kind: 'scam',
            url: 'https://privacy-test-pages.site/security/badware/scam.html',
        },
    },
    'ssl.expired': {
        name: 'Expired',
        data: {
            kind: 'ssl',
            errorType: 'expired',
            domain: 'example.com',
        },
    },
    'ssl.invalid': {
        name: 'Invalid',
        data: {
            kind: 'ssl',
            errorType: 'invalid',
            domain: 'example.com',
        },
    },
    'ssl.selfSigned': {
        name: 'Self-signed',
        data: {
            kind: 'ssl',
            errorType: 'selfSigned',
            domain: 'example.com',
        },
    },
    'ssl.wrongHost': {
        name: 'Wrong Host',
        data: {
            kind: 'ssl',
            errorType: 'wrongHost',
            domain: 'example.com',
            eTldPlus1: 'anothersite.com',
        },
    },
};
