//
//  DriverProgress.swift
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

import AppUpdaterShared

/// Lightweight progress signals from the Sparkle user driver.
///
/// The driver doesn't know about `Update` — the controller maps these
/// to `UpdateCycleProgress` by attaching the current update.
enum DriverProgress {
    case updateCycleDidStart
    case updateCycleDone(UpdateCycleProgress.DoneReason)
    case updaterError(Error)
    case downloadDidStart
    case downloading(Double)
    case extractionDidStart
    case extracting(Double)
    case installationDidStart
    case installing
}
