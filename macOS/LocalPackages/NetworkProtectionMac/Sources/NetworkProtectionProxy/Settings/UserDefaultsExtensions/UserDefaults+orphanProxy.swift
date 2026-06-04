//
//  UserDefaults+orphanProxy.swift
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

import Combine
import Foundation

extension UserDefaults {

    // MARK: - Orphan proxy detection

    /// The behavior before the orphan-proxy kill switches existed: detection ran unconditionally.
    public static let orphanProxyDetectionEnabledDefaultValue = true

    private var orphanProxyDetectionEnabledKey: String {
        "vpnProxyOrphanDetectionEnabled"
    }

    @objc
    dynamic var vpnProxyOrphanDetectionEnabled: Bool {
        get {
            value(forKey: orphanProxyDetectionEnabledKey) as? Bool ?? Self.orphanProxyDetectionEnabledDefaultValue
        }

        set {
            set(newValue, forKey: orphanProxyDetectionEnabledKey)
        }
    }

    func resetVPNProxyOrphanDetectionEnabled() {
        removeObject(forKey: orphanProxyDetectionEnabledKey)
    }

    // MARK: - Orphan proxy full bypass

    /// The behavior before the orphan-proxy kill switches existed: bypass engaged on detection.
    public static let orphanProxyBypassEnabledDefaultValue = true

    private var orphanProxyBypassEnabledKey: String {
        "vpnProxyOrphanBypassEnabled"
    }

    @objc
    dynamic var vpnProxyOrphanBypassEnabled: Bool {
        get {
            value(forKey: orphanProxyBypassEnabledKey) as? Bool ?? Self.orphanProxyBypassEnabledDefaultValue
        }

        set {
            set(newValue, forKey: orphanProxyBypassEnabledKey)
        }
    }

    func resetVPNProxyOrphanBypassEnabled() {
        removeObject(forKey: orphanProxyBypassEnabledKey)
    }
}
