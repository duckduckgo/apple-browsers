//
//  Tab+DebugControlServer.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Navigation

extension Tab {

    /// Passive navigation recorder for the debug control server; always `nil` outside DEBUG builds.
    ///
    /// `setupNavigationDelegate` is nonisolated but only ever runs on the main thread, which
    /// `setResponders` itself asserts.
    var debugControlNavigationResponder: (any NavigationResponder & AnyObject)? {
#if DEBUG
        MainActor.assumeIsolated { DebugControlServerHost.recorder.makeNavigationResponder(for: self) }
#else
        nil
#endif
    }
}
