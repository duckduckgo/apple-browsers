//
//  WKWebView+SessionState.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import WebKit

extension WKWebView {
    struct DoesNotSupportRestoreFromSessionData: Error {}

    @nonobjc
    @available(macOS, deprecated: 12.0)
    func sessionStateData() throws -> Data? {
        if #available(macOS 12.0, *) { return nil }

        guard self.responds(to: #selector(WKWebView._sessionStateData)) else {
            throw DoesNotSupportRestoreFromSessionData()
        }

        return self._sessionStateData()
    }

    @nonobjc
    @available(macOS, deprecated: 12.0)
    func restoreSessionState(from data: Data) throws {
        if #available(macOS 12.0, *) { return }

        guard self.responds(to: #selector(WKWebView._restore(fromSessionStateData:))) else {
            throw DoesNotSupportRestoreFromSessionData()
        }

        self._restore(fromSessionStateData: data)
    }

}
