//
//  JSContextPolyfills.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Globals a bare `JSContext` lacks but every extension page has, for the scripts under test that
/// reach for them.
enum JSContextPolyfills {

    /// Just enough of the WHATWG `URL` parser for the scripts under test: absolute passthrough,
    /// root-absolute and directory-relative resolution against a base.
    static let url = """
    function isAbsoluteURL(value) {
        var separator = value.indexOf("://");
        return separator > 0 && value.slice(0, separator).indexOf("/") === -1;
    }

    globalThis.URL = function(url, base) {
        if (isAbsoluteURL(url)) {
            this.href = url;
            return;
        }
        if (!base || !isAbsoluteURL(base)) {
            throw new TypeError("Invalid URL: " + url);
        }
        var pathStart = base.indexOf("/", base.indexOf("://") + 3);
        var origin = pathStart === -1 ? base : base.slice(0, pathStart);
        if (url.charAt(0) === "/") {
            this.href = origin + url;
            return;
        }
        var path = pathStart === -1 ? "/" : base.slice(pathStart);
        this.href = origin + path.slice(0, path.lastIndexOf("/") + 1) + url;
    };
    """
}
