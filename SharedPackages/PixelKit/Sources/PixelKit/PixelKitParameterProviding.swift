//
//  PixelKitParameterProviding.swift
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

/// Supplies parameter values that PixelKit cannot derive on its own.
///
/// PixelKit deliberately sits below the layers that own this state and does not depend on them, so
/// it cannot reach a statistics store directly. The host app injects a conformer at `setUp`.
///
/// Values are read at fire time rather than snapshotted at setup, because they change while the app
/// runs: there is no ATB until the app has completed its first ATB request, and it is updated
/// afterwards. Conformers should therefore read through to their underlying store on each access,
/// and must be safe to read from any thread, since pixels are fired from many.
///
/// Injection is optional. With no provider, no pixel carries any of these parameters, which is what
/// keeps a host that has not opted in byte-identical to its previous behaviour.
public protocol PixelKitParameterProviding {

    /// The ATB cohort with its variant suffix, for example `v123-4ma`, or `nil` before the app has
    /// an ATB.
    ///
    /// Only read for pixels that opted in through `Options.includeATB`.
    var atb: String? { get }
}
