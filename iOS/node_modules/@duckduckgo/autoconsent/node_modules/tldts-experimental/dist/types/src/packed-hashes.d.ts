import { IPublicSuffix, ISuffixLookupOptions } from 'tldts-core';
/**
 * Perform a public suffix lookup for `hostname` using the packed hashes
 * data-structure. The `options` allows to specify if ICANN/PRIVATE sections
 * should be considered. By default, both are.
 *
 */
export default function suffixLookup(hostname: string, options: ISuffixLookupOptions, out: IPublicSuffix): void;
