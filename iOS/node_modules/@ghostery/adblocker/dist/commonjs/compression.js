"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const smaz_1 = require("@remusao/smaz");
const cosmetic_selector_js_1 = __importDefault(require("./codebooks/cosmetic-selector.js"));
const network_csp_js_1 = __importDefault(require("./codebooks/network-csp.js"));
const network_filter_js_1 = __importDefault(require("./codebooks/network-filter.js"));
const network_hostname_js_1 = __importDefault(require("./codebooks/network-hostname.js"));
const network_redirect_js_1 = __importDefault(require("./codebooks/network-redirect.js"));
const raw_network_js_1 = __importDefault(require("./codebooks/raw-network.js"));
const raw_cosmetic_js_1 = __importDefault(require("./codebooks/raw-cosmetic.js"));
class Compression {
    constructor() {
        this.cosmeticSelector = new smaz_1.Smaz(cosmetic_selector_js_1.default);
        this.networkCSP = new smaz_1.Smaz(network_csp_js_1.default);
        this.networkRedirect = new smaz_1.Smaz(network_redirect_js_1.default);
        this.networkHostname = new smaz_1.Smaz(network_hostname_js_1.default);
        this.networkFilter = new smaz_1.Smaz(network_filter_js_1.default);
        this.networkRaw = new smaz_1.Smaz(raw_network_js_1.default);
        this.cosmeticRaw = new smaz_1.Smaz(raw_cosmetic_js_1.default);
    }
}
exports.default = Compression;
//# sourceMappingURL=compression.js.map