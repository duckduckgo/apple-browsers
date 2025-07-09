// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { AsyncProfileTransform, Extractor } from '../types.js';
import { hashObject } from '../utils/utils.js';

/**
 * @implements {Extractor<{profileUrl: string; identifier: string} | null>}
 */
export class ProfileUrlExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
        if (strs.length === 0) return null;
        const profile = {
            profileUrl: strs[0],
            identifier: strs[0],
        };

        if (!extractorParams.identifierType || !extractorParams.identifier) {
            return profile;
        }

        const profileUrl = strs[0];
        profile.identifier = this.getIdFromProfileUrl(profileUrl, extractorParams.identifierType, extractorParams.identifier);
        return profile;
    }

    /**
     * Parse a profile id from a profile URL
     * @param {string} profileUrl
     * @param {import('../actions/extract.js').IdentifierType} identifierType
     * @param {string} identifier
     * @return {string}
     */
    getIdFromProfileUrl(profileUrl, identifierType, identifier) {
        const parsedUrl = new URL(profileUrl);
        const urlParams = parsedUrl.searchParams;

        // Attempt to parse out an id from the search parameters
        if (identifierType === 'param' && urlParams.has(identifier)) {
            const profileId = urlParams.get(identifier);
            return profileId || profileUrl;
        }

        return profileUrl;
    }
}

/**
 * If a hash is needed, compute it from the profile and
 * set it as the 'identifier'
 *
 * @implements {AsyncProfileTransform}
 */
export class ProfileHashTransformer {
    /**
     * @param {Record<string, any>} profile
     * @param {Record<string, any> } params
     * @return {Promise<Record<string, any>>}
     */
    async transform(profile, params) {
        if (params?.profileUrl?.identifierType !== 'hash') {
            return profile;
        }

        return {
            ...profile,
            identifier: await hashObject(profile),
        };
    }
}
