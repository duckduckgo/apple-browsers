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
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.StreamingHtmlFilter = exports.Resources = exports.Config = exports.isUTF8 = exports.tokenize = exports.hasUnicode = exports.parseFilters = exports.parseFilter = exports.mergeDiffs = exports.getLinesWithFilters = exports.generateDiff = exports.f = exports.detectFilterType = exports.FilterType = exports.NetworkFilter = exports.CosmeticFilter = exports.getHostnameHashesFromLabelsBackward = exports.makeRequest = exports.Request = exports.ReverseIndex = exports.ENGINE_VERSION = exports.FiltersEngine = void 0;
var engine_js_1 = require("./engine/engine.js");
Object.defineProperty(exports, "FiltersEngine", { enumerable: true, get: function () { return __importDefault(engine_js_1).default; } });
Object.defineProperty(exports, "ENGINE_VERSION", { enumerable: true, get: function () { return engine_js_1.ENGINE_VERSION; } });
var reverse_index_js_1 = require("./engine/reverse-index.js");
Object.defineProperty(exports, "ReverseIndex", { enumerable: true, get: function () { return __importDefault(reverse_index_js_1).default; } });
var request_js_1 = require("./request.js");
Object.defineProperty(exports, "Request", { enumerable: true, get: function () { return __importDefault(request_js_1).default; } });
Object.defineProperty(exports, "makeRequest", { enumerable: true, get: function () { return request_js_1.makeRequest; } });
Object.defineProperty(exports, "getHostnameHashesFromLabelsBackward", { enumerable: true, get: function () { return request_js_1.getHostnameHashesFromLabelsBackward; } });
var cosmetic_js_1 = require("./filters/cosmetic.js");
Object.defineProperty(exports, "CosmeticFilter", { enumerable: true, get: function () { return __importDefault(cosmetic_js_1).default; } });
var network_js_1 = require("./filters/network.js");
Object.defineProperty(exports, "NetworkFilter", { enumerable: true, get: function () { return __importDefault(network_js_1).default; } });
var lists_js_1 = require("./lists.js");
Object.defineProperty(exports, "FilterType", { enumerable: true, get: function () { return lists_js_1.FilterType; } });
Object.defineProperty(exports, "detectFilterType", { enumerable: true, get: function () { return lists_js_1.detectFilterType; } });
Object.defineProperty(exports, "f", { enumerable: true, get: function () { return lists_js_1.f; } });
Object.defineProperty(exports, "generateDiff", { enumerable: true, get: function () { return lists_js_1.generateDiff; } });
Object.defineProperty(exports, "getLinesWithFilters", { enumerable: true, get: function () { return lists_js_1.getLinesWithFilters; } });
Object.defineProperty(exports, "mergeDiffs", { enumerable: true, get: function () { return lists_js_1.mergeDiffs; } });
Object.defineProperty(exports, "parseFilter", { enumerable: true, get: function () { return lists_js_1.parseFilter; } });
Object.defineProperty(exports, "parseFilters", { enumerable: true, get: function () { return lists_js_1.parseFilters; } });
__exportStar(require("./fetch.js"), exports);
var utils_js_1 = require("./utils.js");
Object.defineProperty(exports, "hasUnicode", { enumerable: true, get: function () { return utils_js_1.hasUnicode; } });
Object.defineProperty(exports, "tokenize", { enumerable: true, get: function () { return utils_js_1.tokenizeNoSkip; } });
var encoding_js_1 = require("./encoding.js");
Object.defineProperty(exports, "isUTF8", { enumerable: true, get: function () { return encoding_js_1.isUTF8; } });
var config_js_1 = require("./config.js");
Object.defineProperty(exports, "Config", { enumerable: true, get: function () { return __importDefault(config_js_1).default; } });
var resources_js_1 = require("./resources.js");
Object.defineProperty(exports, "Resources", { enumerable: true, get: function () { return __importDefault(resources_js_1).default; } });
var html_filtering_js_1 = require("./html-filtering.js");
Object.defineProperty(exports, "StreamingHtmlFilter", { enumerable: true, get: function () { return __importDefault(html_filtering_js_1).default; } });
//# sourceMappingURL=index.js.map