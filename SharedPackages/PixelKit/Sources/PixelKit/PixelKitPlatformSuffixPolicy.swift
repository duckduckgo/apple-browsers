//
//  PixelKitPlatformSuffixPolicy.swift
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

/// Where PixelKit puts the iOS platform and form-factor marker, `_ios_phone` or `_ios_tablet`.
///
/// Set on the event, via `PixelKit.Event.platformSuffixPolicy`. Defaults to `.standard`.
///
/// Only observable on iOS. On macOS the marker is empty and every case produces the same name.
public enum PixelKitPlatformSuffixPolicy: Equatable {

    /// `<name>_<frequency>_ios_<formFactor>`, e.g. `m_example_count_ios_phone`.
    ///
    /// Matches the `["first_daily_count", "platform", "form_factor"]` suffix order used by the
    /// pixel definitions. Use this for new pixels.
    case standard

    /// `<name>_ios_<formFactor>_<frequency>`, e.g. `m_example_ios_phone_count`.
    ///
    /// Legacy. Only for pixels already sending this shape, whose definitions declare
    /// `["platform", "form_factor", "first_daily_count"]`.
    case legacyBeforeFrequencySuffix

    /// `<name>_<frequency>`, with no marker, e.g. `m_example_count`.
    ///
    /// Legacy, and the right choice for an event that builds the marker into `name` itself, such as
    /// `OSDistributionPixel`.
    case legacyOmitted
}
