//
//  WKWebsiteDataStore+FireWindowSession.swift
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

import ObjectiveC
import WebKit

extension WKWebsiteDataStore {

    private static let fireWindowSessionKey = UnsafeRawPointer(bitPattern: "fireWindowSessionKey".hashValue)!

    /// The `FireWindowSession` for the burner session this data store belongs to.
    /// Populated in `WindowsManager` when the Fire Window is created; `nil` for persistent stores.
    /// Allows resolving the session in `DownloadsTabExtension` before `webView.window` is set.
    var fireWindowSession: FireWindowSession? {
        get { (objc_getAssociatedObject(self, Self.fireWindowSessionKey) as? FireWindowSessionRef)?.fireWindowSession }
        set { objc_setAssociatedObject(self, Self.fireWindowSessionKey, newValue.map(FireWindowSessionRef.init(session:)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

}
