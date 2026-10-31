//
//  VPNWakeHandshakePixel.swift
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

import PixelKit

/// Fired only by the iOS packet tunnel's wake monitor.
public enum VPNWakeHandshakePixel: PixelKit.Event {
    case timeouts

    public var name: String { "vpn_wake_handshake_timeouts" }
    public var parameters: [String: String]? { nil }
    public var standardParameters: [PixelKitStandardParameter]? { nil }
}
