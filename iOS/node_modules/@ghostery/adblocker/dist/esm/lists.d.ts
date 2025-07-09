/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import Config from './config.js';
import CosmeticFilter from './filters/cosmetic.js';
import NetworkFilter from './filters/network.js';
import Preprocessor from './preprocessor.js';
export declare const enum FilterType {
    NOT_SUPPORTED = 0,
    NETWORK = 1,
    COSMETIC = 2,
    NOT_SUPPORTED_EMPTY = 100,
    NOT_SUPPORTED_COMMENT = 101,
    NOT_SUPPORTED_ADGUARD = 102
}
/**
 * Given a single line (string), checks if this would likely be a cosmetic
 * filter, a network filter or something that is not supported. This check is
 * performed before calling a more specific parser to create an instance of
 * `NetworkFilter` or `CosmeticFilter`.
 */
export declare function detectFilterType(line: string, { extendedNonSupportedTypes }?: {
    extendedNonSupportedTypes?: boolean | undefined;
}): FilterType;
export declare function parseFilter(filter: string): NetworkFilter | CosmeticFilter | null;
export declare function f(strings: TemplateStringsArray): NetworkFilter | CosmeticFilter | null;
interface NonSupportedFilter {
    lineNumber: number;
    filter: string;
    filterType: FilterType;
}
export declare function parseFilters(list: string, config?: Partial<Config>): {
    networkFilters: NetworkFilter[];
    cosmeticFilters: CosmeticFilter[];
    preprocessors: Preprocessor[];
    notSupportedFilters: NonSupportedFilter[];
};
export interface IListDiff {
    newNetworkFilters: NetworkFilter[];
    newCosmeticFilters: CosmeticFilter[];
    newPreprocessors: Preprocessor[];
    removedCosmeticFilters: number[];
    removedNetworkFilters: number[];
    removedPreprocessors: Preprocessor[];
}
interface IBaseDiff {
    added: string[];
    removed: string[];
}
interface IPreprocessorDiff {
    [key: string]: IBaseDiff;
}
export interface IRawDiff extends IBaseDiff {
    preprocessors?: IPreprocessorDiff;
}
export type IPartialRawDiff = Partial<IBaseDiff> & {
    preprocessors?: {
        [key: string]: Partial<IBaseDiff>;
    };
};
/**
 * Helper used to return a set of lines as strings where each line is
 * guaranteed to be a valid filter (i.e.: comments, empty lines and
 * un-supported filters are dropped).
 */
export declare function getLinesWithFilters(list: string, config?: Partial<Config>): Set<string>;
/**
 * Given two versions of the same subscription (e.g.: EasyList) as a string,
 * generate a raw diff (i.e.: a list of filters added and filters removed, in
 * their raw string form).
 */
export declare function generateDiff(prevRevision: string, newRevision: string, config?: Partial<Config>): IRawDiff;
/**
 * Merge several raw diffs into one, taking care of accumulating added and
 * removed filters, even if several diffs add/remove the same ones.
 */
export declare function mergeDiffs(diffs: IPartialRawDiff[]): IRawDiff;
export {};
//# sourceMappingURL=lists.d.ts.map