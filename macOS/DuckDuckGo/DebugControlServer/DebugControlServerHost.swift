//
//  DebugControlServerHost.swift
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

#if DEBUG

import Foundation
import os.log

/// Owns the debug control server and the recorder that tabs report into.
///
/// The recorder exists from the first tab onwards so that navigation responders can be attached at
/// `Tab.init` time, but it stays inert until the server starts.
@MainActor
enum DebugControlServerHost {

    static let recorder = DebugControlRecorder()

    private static var server: DebugControlServer?

    static func startIfNeeded(windowControllersManager: WindowControllersManager, contentBlocking: AnyContentBlocking) {
        guard server == nil else { return }
        guard let port = DebugControlServer.configuredPort() else {
            Logger.debugControlServer.log("Debug control server disabled by DDG_CONTROL_PORT=0")
            return
        }

        let router = DebugControlRouter(windowControllersManager: windowControllersManager,
                                        contentBlocking: contentBlocking,
                                        recorder: recorder)
        do {
            server = try DebugControlServer(port: port, router: router)
            recorder.isEnabled = true
            router.attachToAllTabs()
        } catch {
            Logger.debugControlServer.error("Failed to start debug control server: \(error.localizedDescription)")
        }
    }
}

#endif
