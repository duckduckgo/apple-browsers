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

/// Where PixelKit places the platform and form-factor marker (`_ios_phone` / `_ios_tablet`) in a
/// pixel's name.
///
/// Only observable on iOS. On macOS the marker is empty, so every case produces the same name and
/// annotating a macOS-only event has no effect.
///
/// `standard` is the default for any event that does not say otherwise, so a newly added pixel gets
/// the right name without its author having to know this type exists. The two `legacy` cases exist
/// solely to freeze the names of pixels that shipped before the marker was applied consistently.
/// **Do not use them for new pixels.**
public enum PixelKitPlatformSuffixPolicy: Equatable {

    /// `<name>_<frequencySuffix>_ios_<formFactor>`, for example `m_example_count_ios_phone`.
    ///
    /// The convention the pixel definitions declare (`suffixes: ["first_daily_count", "platform",
    /// "form_factor"]`) and the one iOS' legacy `Pixel` type has always produced. The marker is
    /// appended when the request is built, after the frequency suffix, so it cannot be skipped by
    /// forgetting to opt in.
    case standard

    /// `<name>_ios_<formFactor>_<frequencySuffix>`, for example `m_example_ios_phone_count`.
    ///
    /// What conformance to `PixelKitEventWithCustomPrefix` used to imply on its own. Frozen for the
    /// pixels already sending this shape; their definitions declare
    /// `["platform", "form_factor", "first_daily_count"]` to match.
    case legacyBeforeFrequencySuffix

    /// `<name>_<frequencySuffix>`, with no platform marker at all, for example `m_example_count`.
    ///
    /// What every event that did *not* conform to `PixelKitEventWithCustomPrefix` produced on iOS,
    /// which is why a pixel like `m_privacy-pro_keychain_manager_data_added_to_backlog_count` cannot
    /// be told apart from its macOS counterpart by name. Frozen for the pixels already sending this
    /// shape.
    ///
    /// Also the right answer for an event that builds the marker into `name` itself, such as
    /// `OSDistributionPixel`, since a second marker would produce `..._ios_phone_ios_phone`.
    case legacyOmitted
}
