//
//  VPNStartCancellationSource.swift
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

/// Identifies which stage of the VPN start sequence was cancelled.
///
/// Reported as a parameter on the controller start cancelled pixel so cancellations can be
/// attributed to the stage they originated from (e.g. distinguishing a user declining the system
/// extension prompt from a tunnel-start race).
public enum VPNStartCancellationSource: String {
    case systemExtensionActivation
    case tunnelManagerLoad
    case startupOptions
    case startTunnel
    /// A cancellation that reached the top-level handler without being attributed to a specific stage.
    case unknown
}
