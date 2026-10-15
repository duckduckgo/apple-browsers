//
//  AIChatBonusInstallCleanup.swift
//  DuckDuckGo
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

/// Removes the bonus record a previous install of the app left in the Keychain.
///
/// Keychain items outlive the app, but the record must not survive app deletion.
enum AIChatBonusInstallCleanup {

    /// Calls `deleteRecord` when there's no install date yet, which means this is a new install.
    ///
    /// The first successful ATB request saves the install date, and it never changes after that. Deleting the app
    /// removes it but not the Keychain, so after a reinstall the date is missing again while the old record is still there.
    ///
    /// Call at launch, before the first ATB request. Once the install date is saved, the install is no longer
    /// recognised as new, and the record belongs to the current install. Until then this deletes on every launch,
    /// which is harmless: no offer can be claimed without an install date.
    ///
    /// - Parameters:
    ///   - installDate: The install date saved by the first successful ATB request, or `nil` before it.
    ///   - deleteRecord: Deletes the stored record.
    static func deleteRecordIfNewInstall(installDate: Date?, deleteRecord: () -> Void) {
        guard installDate == nil else { return }
        deleteRecord()
    }

}
