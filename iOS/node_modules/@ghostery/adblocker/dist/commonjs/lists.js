"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FilterType = void 0;
exports.detectFilterType = detectFilterType;
exports.parseFilter = parseFilter;
exports.f = f;
exports.parseFilters = parseFilters;
exports.getLinesWithFilters = getLinesWithFilters;
exports.generateDiff = generateDiff;
exports.mergeDiffs = mergeDiffs;
const config_js_1 = __importDefault(require("./config.js"));
const cosmetic_js_1 = __importDefault(require("./filters/cosmetic.js"));
const network_js_1 = __importDefault(require("./filters/network.js"));
const preprocessor_js_1 = __importStar(require("./preprocessor.js"));
const utils_js_1 = require("./utils.js");
var FilterType;
(function (FilterType) {
    FilterType[FilterType["NOT_SUPPORTED"] = 0] = "NOT_SUPPORTED";
    FilterType[FilterType["NETWORK"] = 1] = "NETWORK";
    FilterType[FilterType["COSMETIC"] = 2] = "COSMETIC";
    // available only with `extendedNonSupportedTypes` option for #detectFilterType
    FilterType[FilterType["NOT_SUPPORTED_EMPTY"] = 100] = "NOT_SUPPORTED_EMPTY";
    FilterType[FilterType["NOT_SUPPORTED_COMMENT"] = 101] = "NOT_SUPPORTED_COMMENT";
    FilterType[FilterType["NOT_SUPPORTED_ADGUARD"] = 102] = "NOT_SUPPORTED_ADGUARD";
})(FilterType || (exports.FilterType = FilterType = {}));
/**
 * Given a single line (string), checks if this would likely be a cosmetic
 * filter, a network filter or something that is not supported. This check is
 * performed before calling a more specific parser to create an instance of
 * `NetworkFilter` or `CosmeticFilter`.
 */
function detectFilterType(line, { extendedNonSupportedTypes = false } = {}) {
    // Ignore empty line
    if (line.length === 0 || line.length === 1) {
        if (extendedNonSupportedTypes) {
            return FilterType.NOT_SUPPORTED_EMPTY;
        }
        return FilterType.NOT_SUPPORTED;
    }
    // Ignore comments
    const firstCharCode = line.charCodeAt(0);
    const secondCharCode = line.charCodeAt(1);
    if (firstCharCode === 33 /* '!' */ ||
        (firstCharCode === 35 /* '#' */ && secondCharCode <= 32) ||
        (firstCharCode === 91 /* '[' */ && (0, utils_js_1.fastStartsWith)(line, '[Adblock'))) {
        if (extendedNonSupportedTypes) {
            return FilterType.NOT_SUPPORTED_COMMENT;
        }
        return FilterType.NOT_SUPPORTED;
    }
    // Fast heuristics to detect network filters
    const lastCharCode = line.charCodeAt(line.length - 1);
    if ((firstCharCode === 36 /* '$' */ &&
        secondCharCode !== 36 &&
        secondCharCode !== 64) /* $$ and $@ as those may be Adguard HTML filtering rules */ ||
        firstCharCode === 38 /* '&' */ ||
        firstCharCode === 42 /* '*' */ ||
        firstCharCode === 45 /* '-' */ ||
        firstCharCode === 46 /* '.' */ ||
        firstCharCode === 47 /* '/' */ ||
        firstCharCode === 58 /* ':' */ ||
        firstCharCode === 61 /* '=' */ ||
        firstCharCode === 63 /* '?' */ ||
        firstCharCode === 64 /* '@' */ ||
        firstCharCode === 95 /* '_' */ ||
        firstCharCode === 124 /* '|' */ ||
        lastCharCode === 124 /* '|' */) {
        return FilterType.NETWORK;
    }
    // Ignore Adguard cosmetics
    // `$$` = HTML filtering rules
    const dollarIndex = line.indexOf('$');
    if (dollarIndex !== -1 && dollarIndex !== line.length - 1) {
        const afterDollarIndex = dollarIndex + 1;
        const afterDollarCharCode = line.charCodeAt(afterDollarIndex);
        // Ignore Adguard HTML rewrite rules
        if (afterDollarCharCode === 36 /* '$' */ ||
            (afterDollarCharCode === 64 /* '@' */ &&
                (0, utils_js_1.fastStartsWithFrom)(line, /* $@$ */ '@$', afterDollarIndex))) {
            if (extendedNonSupportedTypes) {
                return FilterType.NOT_SUPPORTED_ADGUARD;
            }
            return FilterType.NOT_SUPPORTED;
        }
    }
    // Check if filter is cosmetics
    const sharpIndex = line.indexOf('#');
    if (sharpIndex !== -1 && sharpIndex !== line.length - 1) {
        const afterSharpIndex = sharpIndex + 1;
        const afterSharpCharCode = line.charCodeAt(afterSharpIndex);
        if (afterSharpCharCode === 35 /* '#'*/ ||
            (afterSharpCharCode === 64 /* '@' */ &&
                (0, utils_js_1.fastStartsWithFrom)(line, /* #@# */ '@#', afterSharpIndex))
        // TODO - support ADB/AdGuard extended css selectors
        // || (afterSharpCharCode === 63 /* '?' */ &&
        //   fastStartsWithFrom(line, /* #?# */ '?#', afterSharpIndex))
        ) {
            // Parse supported cosmetic filter
            // `##` `#@#`
            return FilterType.COSMETIC;
        }
        else if ((afterSharpCharCode === 64 /* '@'*/ &&
            ((0, utils_js_1.fastStartsWithFrom)(line, /* #@$# */ '@$#', afterSharpIndex) ||
                (0, utils_js_1.fastStartsWithFrom)(line, /* #@%# */ '@%#', afterSharpIndex) ||
                (0, utils_js_1.fastStartsWithFrom)(line, /* #@?# */ '@?#', afterSharpIndex))) ||
            (afterSharpCharCode === 37 /* '%' */ &&
                (0, utils_js_1.fastStartsWithFrom)(line, /* #%# */ '%#', afterSharpIndex)) ||
            (afterSharpCharCode === 36 /* '$' */ &&
                ((0, utils_js_1.fastStartsWithFrom)(line, /* #$# */ '$#', afterSharpIndex) ||
                    (0, utils_js_1.fastStartsWithFrom)(line, /* #$?# */ '$?#', afterSharpIndex))) ||
            (afterSharpCharCode === 63 /* '?' */ &&
                (0, utils_js_1.fastStartsWithFrom)(line, /* #?# */ '?#', afterSharpIndex))) {
            if (extendedNonSupportedTypes) {
                return FilterType.NOT_SUPPORTED_ADGUARD;
            }
            return FilterType.NOT_SUPPORTED;
        }
    }
    // Everything else is a network filter
    return FilterType.NETWORK;
}
function parseFilter(filter) {
    const filterType = detectFilterType(filter);
    if (filterType === FilterType.NETWORK) {
        return network_js_1.default.parse(filter, true);
    }
    else if (filterType === FilterType.COSMETIC) {
        return cosmetic_js_1.default.parse(filter, true);
    }
    return null;
}
function f(strings) {
    return parseFilter(strings[0]);
}
function parseFilters(list, config = new config_js_1.default()) {
    config = new config_js_1.default(config);
    const networkFilters = [];
    const cosmeticFilters = [];
    const notSupportedFilters = [];
    const lines = list.split('\n');
    const preprocessors = [];
    const preprocessorStack = [];
    for (let i = 0; i < lines.length; i += 1) {
        let line = lines[i];
        // Check if `line` should be left-trimmed
        if (line.length !== 0 && line.charCodeAt(0) <= 32) {
            line = line.trim();
        }
        // Handle continuations
        if (line.length > 2) {
            while (i < lines.length - 1 &&
                line.charCodeAt(line.length - 1) === 92 &&
                line.charCodeAt(line.length - 2) === 32) {
                line = line.slice(0, -2);
                const nextLine = lines[i + 1];
                if (nextLine.length > 4 &&
                    nextLine.charCodeAt(0) === 32 &&
                    nextLine.charCodeAt(1) === 32 &&
                    nextLine.charCodeAt(2) === 32 &&
                    nextLine.charCodeAt(3) === 32 &&
                    nextLine.charCodeAt(4) !== 32) {
                    line += nextLine.slice(4);
                    i += 1;
                }
                else {
                    break;
                }
            }
        }
        // Check if `line` should be right-trimmed
        if (line.length !== 0 && line.charCodeAt(line.length - 1) <= 32) {
            line = line.trim();
        }
        // Detect if filter is supported, network or cosmetic
        const filterType = detectFilterType(line, { extendedNonSupportedTypes: true });
        if (filterType === FilterType.NETWORK && config.loadNetworkFilters === true) {
            const filter = network_js_1.default.parse(line, config.debug);
            if (filter !== null) {
                networkFilters.push(filter);
                if (preprocessorStack.length > 0) {
                    preprocessorStack[preprocessorStack.length - 1].filterIDs.add(filter.getId());
                }
            }
            else {
                notSupportedFilters.push({
                    lineNumber: i,
                    filter: line,
                    filterType,
                });
            }
        }
        else if (filterType === FilterType.COSMETIC && config.loadCosmeticFilters === true) {
            const filter = cosmetic_js_1.default.parse(line, config.debug);
            if (filter !== null) {
                if (config.loadGenericCosmeticsFilters === true || filter.isGenericHide() === false) {
                    cosmeticFilters.push(filter);
                    if (preprocessorStack.length > 0) {
                        preprocessorStack[preprocessorStack.length - 1].filterIDs.add(filter.getId());
                    }
                }
            }
            else {
                notSupportedFilters.push({
                    lineNumber: i,
                    filter: line,
                    filterType: FilterType.COSMETIC,
                });
            }
        }
        else if (config.loadPreprocessors) {
            const preprocessorToken = (0, preprocessor_js_1.detectPreprocessor)(line);
            if (preprocessorToken === preprocessor_js_1.PreprocessorTokens.BEGIF) {
                if (preprocessorStack.length > 0) {
                    preprocessorStack.push(new preprocessor_js_1.default({
                        condition: `(${preprocessorStack[preprocessorStack.length - 1].condition})&&(${preprocessor_js_1.default.getCondition(line)})`,
                    }));
                }
                else {
                    preprocessorStack.push(preprocessor_js_1.default.parse(line));
                }
            }
            else if ((preprocessorToken === preprocessor_js_1.PreprocessorTokens.ENDIF ||
                preprocessorToken === preprocessor_js_1.PreprocessorTokens.ELSE) &&
                preprocessorStack.length > 0) {
                const lastPreprocessor = preprocessorStack.pop();
                preprocessors.push(lastPreprocessor);
                if (preprocessorToken === preprocessor_js_1.PreprocessorTokens.ELSE) {
                    preprocessorStack.push(new preprocessor_js_1.default({
                        condition: `!(${lastPreprocessor.condition})`,
                    }));
                }
            }
            else if (filterType === FilterType.NOT_SUPPORTED_ADGUARD) {
                notSupportedFilters.push({
                    lineNumber: i,
                    filter: line,
                    filterType,
                });
            }
        }
        else if (filterType === FilterType.NOT_SUPPORTED_ADGUARD) {
            notSupportedFilters.push({
                lineNumber: i,
                filter: line,
                filterType,
            });
        }
    }
    return {
        networkFilters,
        cosmeticFilters,
        preprocessors: preprocessors.filter((preprocessor) => preprocessor.filterIDs.size > 0),
        notSupportedFilters,
    };
}
function getFilters(list, config) {
    const { networkFilters, cosmeticFilters, preprocessors } = parseFilters(list, config);
    const filters = [];
    return {
        filters: filters.concat(networkFilters).concat(cosmeticFilters),
        preprocessors,
    };
}
/**
 * Helper used to return a set of lines as strings where each line is
 * guaranteed to be a valid filter (i.e.: comments, empty lines and
 * un-supported filters are dropped).
 */
function getLinesWithFilters(list, config = new config_js_1.default()) {
    // Set config to `debug` so that we keep track of raw lines for each filter
    return new Set(getFilters(list, new config_js_1.default(Object.assign({}, config, { debug: true }))).filters.map(({ rawLine }) => rawLine));
}
/**
 * Given two versions of the same subscription (e.g.: EasyList) as a string,
 * generate a raw diff (i.e.: a list of filters added and filters removed, in
 * their raw string form).
 */
function generateDiff(prevRevision, newRevision, config = new config_js_1.default()) {
    // Set config to `debug` so that we keep track of raw lines for each filter
    const debugConfig = new config_js_1.default(Object.assign({}, config, { debug: true }));
    const prevRevisionData = getFilters(prevRevision, debugConfig);
    const prevRevisionIds = new Set(prevRevisionData.filters.map((filter) => filter.getId()));
    const newRevisionData = getFilters(newRevision, debugConfig);
    const newRevisionIds = new Set(newRevisionData.filters.map((filter) => filter.getId()));
    // Check which filters were added, based on ID
    const added = new Set();
    for (const filter of newRevisionData.filters) {
        if (!prevRevisionIds.has(filter.getId())) {
            added.add(filter.rawLine);
        }
    }
    // Check which filters were removed, based on ID
    const removed = new Set();
    for (const filter of prevRevisionData.filters) {
        if (!newRevisionIds.has(filter.getId())) {
            removed.add(filter.rawLine);
        }
    }
    // Fast exit if we don't want to handle preprocessors.
    if (!config.loadPreprocessors) {
        return {
            added: Array.from(added),
            removed: Array.from(removed),
            preprocessors: {},
        };
    }
    const index = new Map();
    for (const filter of newRevisionData.filters) {
        index.set(filter.getId(), filter.rawLine);
    }
    for (const filter of prevRevisionData.filters) {
        index.set(filter.getId(), filter.rawLine);
    }
    // Create preprocessor diffs
    const preprocessors = {};
    // Get the diff of preprocessors
    for (const preprocessor of prevRevisionData.preprocessors) {
        // Find the same preprocessor in `newRevisionData`
        const newPreprocessor = newRevisionData.preprocessors.find((newPreprocessor) => newPreprocessor.condition === preprocessor.condition);
        // If the preprocessor in the revision is not found, it means the whole block was removed
        if (!newPreprocessor) {
            const removedInScope = new Set();
            // Remove all filters
            for (const filterID of preprocessor.filterIDs) {
                removedInScope.add(index.get(filterID));
            }
            preprocessors[preprocessor.condition] = {
                added: [],
                removed: Array.from(removedInScope),
            };
            continue;
        }
        // If the preprocessor in the revision is found, it means the block was updated
        // Create subsets
        const scope = {
            added: new Set(),
            removed: new Set(),
        };
        for (const filterID of preprocessor.filterIDs) {
            if (!newPreprocessor.filterIDs.has(filterID)) {
                scope.removed.add(index.get(filterID));
            }
        }
        for (const filterID of newPreprocessor.filterIDs) {
            if (!preprocessor.filterIDs.has(filterID)) {
                scope.added.add(index.get(filterID));
            }
        }
        preprocessors[preprocessor.condition] = {
            added: Array.from(scope.added),
            removed: Array.from(scope.removed),
        };
    }
    // Iterate over only "added" preprocessors
    for (const preprocessor of newRevisionData.preprocessors) {
        // If the preprocessor in the previous revision was not found, it means the whole block was added
        if (!preprocessors[preprocessor.condition]) {
            const addedInScope = new Set();
            // Remove all filters
            for (const filterID of preprocessor.filterIDs) {
                addedInScope.add(index.get(filterID));
            }
            preprocessors[preprocessor.condition] = {
                added: Array.from(addedInScope),
                removed: [],
            };
        }
    }
    for (const [condition, { added, removed }] of Object.entries(preprocessors)) {
        if (added.length === 0 && removed.length === 0) {
            delete preprocessors[condition];
        }
    }
    return {
        added: Array.from(added),
        removed: Array.from(removed),
        // For the filters under `preprocessors` property, it doesn't mean those are "filters".
        // Those are "a list of filters affected by preprocessors" not the "filters" itself.
        // Therefore, they shouldn't be treated as filters.
        // Instead, we put "filters" in `added` and `removed` properties.
        // This provides backward-compatibility and simplicity.
        preprocessors,
    };
}
/**
 * Merge several raw diffs into one, taking care of accumulating added and
 * removed filters, even if several diffs add/remove the same ones.
 */
function mergeDiffs(diffs) {
    const addedCumul = new Set();
    const removedCumul = new Set();
    const preprocessorsCumul = {};
    for (const { added, removed, preprocessors } of diffs) {
        if (added !== undefined) {
            for (const str of added) {
                if (removedCumul.has(str)) {
                    removedCumul.delete(str);
                }
                addedCumul.add(str);
            }
        }
        if (removed !== undefined) {
            for (const str of removed) {
                if (addedCumul.has(str)) {
                    addedCumul.delete(str);
                }
                removedCumul.add(str);
            }
        }
        if (!preprocessors) {
            continue;
        }
        for (const [condition, details] of Object.entries(preprocessors)) {
            if (!preprocessorsCumul[condition]) {
                preprocessorsCumul[condition] = {
                    added: details.added !== undefined ? new Set(details.added) : new Set(),
                    removed: details.removed !== undefined ? new Set(details.removed) : new Set(),
                };
            }
            else {
                if (details.added !== undefined) {
                    for (const str of details.added) {
                        if (preprocessorsCumul[condition].removed.has(str)) {
                            preprocessorsCumul[condition].removed.delete(str);
                        }
                        preprocessorsCumul[condition].added.add(str);
                    }
                }
                if (details.removed !== undefined) {
                    for (const str of details.removed) {
                        if (preprocessorsCumul[condition].added.has(str)) {
                            preprocessorsCumul[condition].added.delete(str);
                        }
                        preprocessorsCumul[condition].removed.add(str);
                    }
                }
            }
        }
    }
    return {
        added: Array.from(addedCumul),
        removed: Array.from(removedCumul),
        preprocessors: Object.fromEntries(Object.entries(preprocessorsCumul).map(([condition, details]) => [
            condition,
            {
                added: Array.from(details.added),
                removed: Array.from(details.removed),
            },
        ])),
    };
}
//# sourceMappingURL=lists.js.map