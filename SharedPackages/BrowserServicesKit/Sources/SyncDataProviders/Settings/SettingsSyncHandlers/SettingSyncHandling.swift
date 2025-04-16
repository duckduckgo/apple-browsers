//
//  SettingSyncHandling.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Persistence

/**
 * Protocol defining communication between Settings Sync Data Provider and a syncable setting.
 *
 * This protocol should be implemented by classes or structs providing integration with Sync
 * for given settings (or, more broadly, key-value pairs).
 *
 * Its responsibilities are:
 *   * provide implementation for getting and updating the setting's value,
 *   * fine-tune Sync behavior for the setting,
 *   * track changes to setting's value and notify delegate accordingly.
 */
protocol SettingSyncHandling: AnyObject {

    var valueDidChangePublisher: AnyPublisher<Void, Never> { get }
    /**
     * Returns setting identifier that this handler supports.
     *
     * `setting.key` is used verbatim as key in the JSON Sync payload.
     */
    var setting: SettingsProvider.Setting { get }

    /**
     * Retrieves setting value.
     *
     * Note: Return `nil` if a "delete" should be sent via Sync.
     */
    func getValue() throws -> String?

    /**
     * Updates setting value with `value` received from Sync.
     *
     * Note: If "delete" was received from Sync, `value` is `nil`.
     */
    func setValue(_ value: String?, shouldDetectOverride: Bool) throws

    /**
     * Delegate that must be notified about updating setting's value.
     *
     * The delegate must be set, otherwise an assertion failure is called.
     */
    var delegate: SettingSyncHandlingDelegate? { get set }
}

/**
 * Protocol defining delegate interface for Setting Sync Handler.
 *
 * It's implemented by SettingsProvider which owns Settings Sync Handlers
 * and sets itself as their delegate.
 */
protocol SettingSyncHandlingDelegate: AnyObject {

    /**
     * This function must be called whenever setting's value changes for a given Setting Sync Handler.
     */
    func syncHandlerDidUpdateSettingValue(_ handler: SettingSyncHandling)
}
