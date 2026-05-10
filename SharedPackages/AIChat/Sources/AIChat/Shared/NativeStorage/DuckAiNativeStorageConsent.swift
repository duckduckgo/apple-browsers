//
//  DuckAiNativeStorageConsent.swift
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

/// Cross-mode consent state for Duck.ai native storage.
///
/// Ephemeral storage handlers (the in-memory fire-window store on macOS and the
/// fire-mode disk store on iOS) read the keys in `entryKeys` through to a
/// persistent seed source on a miss, so a user who has accepted T&C / granted
/// voice-mode consent in normal mode isn't re-prompted in a fire context — and
/// the behavior survives `replaceAllEntries`.
public enum DuckAiNativeStorageConsent {

    public static let entryKeys: Set<String> = [
        "duckaiHasAgreedToTerms",
        "hasVoiceModeConsent"
    ]
}
