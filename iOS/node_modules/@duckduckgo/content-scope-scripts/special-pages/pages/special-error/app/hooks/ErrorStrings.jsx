import { h } from 'preact';
import { useTypedTranslation } from '../types';
import { useErrorData } from '../providers/SpecialErrorProvider';
import { Trans } from '../../../../shared/components/TranslationsProvider';
import { phishingMalwareHelpPageURL, reportSiteAsSafeFormURL } from '../constants';

/**
 * @param {string} urlString
 * @returns {string}
 */
const sanitizeURL = (urlString) => {
    if (!urlString) return '';

    try {
        const url = new URL(urlString);

        return `${url.origin}${url.pathname}`;
    } catch (error) {
        return '';
    }
};

/**
 * @typedef {object} AnchorTagParams
 * @property {string} href
 * @property {string} target
 */

const helpPageAnchorTagParams = {
    href: phishingMalwareHelpPageURL,
    target: '_blank',
};

/** @type {(url: string) => AnchorTagParams} */
const reportSiteAnchorTagParams = (urlParam) => {
    const sanitizedURLParam = sanitizeURL(urlParam);
    const url = new URL(reportSiteAsSafeFormURL);
    url.searchParams.set('url', sanitizedURLParam);

    return {
        href: url.toString(),
        target: '_blank',
    };
};

/**
 * @typedef {import("../../types/special-error.js").InitialSetupResponse['errorData']} ErrorData
 * @typedef {import("../../types/special-error.js").SSLExpiredCertificate} SSLExpiredCertificate
 * @typedef {import("../../types/special-error.js").SSLInvalidCertificate} SSLInvalidCertificate
 * @typedef {import("../../types/special-error.js").SSLSelfSignedCertificate} SSLSelfSignedCertificate
 * @typedef {import("../../types/special-error.js").SSLWrongHost} SSLWrongHost
 * @typedef {import("../../types/special-error.js").MaliciousSite} MaliciousSite
 * @typedef {SSLExpiredCertificate|SSLInvalidCertificate|SSLSelfSignedCertificate|SSLWrongHost} SSLError
 */

/**
 * @returns {string}
 */
export function useWarningHeading() {
    const { t } = useTypedTranslation();
    const { kind } = useErrorData();

    switch (kind) {
        case 'ssl':
            return t('sslPageHeading');
        case 'malware':
        case 'phishing':
        case 'scam':
            const translationKey = /** @type {const} */ (`${kind}PageHeading`);
            return t(translationKey).replace('{newline}', '\n');
        default:
    }

    throw new Error(`Unhandled error kind ${kind}`);
}

/**
 * @returns {(string|import("preact/src/jsx").JSXInternal.Element)[]}
 */
export function useWarningContent() {
    const { t } = useTypedTranslation();
    const errorData = useErrorData();
    const { kind } = useErrorData();

    if (kind === 'phishing') {
        const text = t('phishingWarningText').replace('{newline}', '\n');
        return [<Trans str={text} values={{ a: helpPageAnchorTagParams }} />];
    }

    if (kind === 'malware') {
        const text = t('malwareWarningText').replace('{newline}', '\n');
        return [<Trans str={text} values={{ a: helpPageAnchorTagParams }} />];
    }

    if (kind === 'scam') {
        const text = t('scamWarningText').replace('{newline}', '\n');
        return [<Trans str={text} values={{ a: helpPageAnchorTagParams }} />];
    }

    if (kind === 'ssl') {
        const { domain } = /** @type {SSLError}} */ (errorData);
        return [<Trans str={t('sslWarningText', { domain })} values="" />];
    }

    throw new Error(`Unhandled error kind ${kind}`);
}

/**
 * @returns {string|import("preact/src/jsx").JSXInternal.Element}
 */
export function useAdvancedInfoHeading() {
    const { t } = useTypedTranslation();
    const errorData = useErrorData();
    const { kind } = errorData;

    switch (kind) {
        case 'ssl':
            return t('sslAdvancedInfoHeading');
        case 'malware':
        case 'phishing':
        case 'scam':
            const { url } = /** @type {MaliciousSite} */ (errorData);
            const anchorTagParams = reportSiteAnchorTagParams(url);
            const translationKey = /** @type {const} */ (`${kind}AdvancedInfoHeading`);
            return <Trans str={t(translationKey)} values={{ a: anchorTagParams }} />;
        default:
    }

    throw new Error(`Unhandled error kind ${kind}`);
}

/**
 * @returns {(string|import("preact/src/jsx").JSXInternal.Element)[]}
 */
export function useAdvancedInfoContent() {
    const { t } = useTypedTranslation();
    const errorData = useErrorData();
    const { kind } = errorData;

    if (kind === 'malware' || kind === 'phishing' || kind === 'scam') {
        return [];
    }

    if (kind === 'ssl') {
        const { errorType, domain } = /** @type {SSLError}} */ (errorData);
        switch (errorType) {
            case 'expired':
                return [<Trans str={t('sslExpiredAdvancedInfoText', { domain })} values="" />];
            case 'invalid':
                return [<Trans str={t('sslInvalidAdvancedInfoText', { domain })} values="" />];
            case 'selfSigned':
                return [<Trans str={t('sslSelfSignedAdvancedInfoText', { domain })} values="" />];
            case 'wrongHost':
                const { eTldPlus1 } = /** @type {SSLWrongHost} */ (errorData);
                return [<Trans str={t('sslWrongHostAdvancedInfoText', { domain, eTldPlus1 })} values="" />];
            default:
                throw new Error(`Unhandled SSL error type ${errorType}`);
        }
    }

    throw new Error(`Unhandled error kind ${kind}`);
}
