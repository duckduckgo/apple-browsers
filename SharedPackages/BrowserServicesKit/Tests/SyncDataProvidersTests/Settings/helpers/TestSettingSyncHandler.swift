//
//  TestSettingSyncHandler.swift
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

import Bookmarks
import Combine
import Foundation
import SyncDataProviders

extension SettingsProvider.Setting {
    static let testSetting = SettingsProvider.Setting(key: "test_setting")
}

final class TestSettingSyncHandler: SettingSyncHandler {

    override var setting: SettingsProvider.Setting {
        .testSetting
    }

    override func getValue() throws -> String? {
        syncedValue
    }

    override func setValue(_ value: String?, shouldDetectOverride: Bool) throws {
        DispatchQueue.main.async {
            self.notifyValueDidChange = false
            self.syncedValue = value
        }
    }

    override var valueDidChangePublisher: AnyPublisher<Void, Never> {
        $syncedValue.dropFirst().map({ _ in })
            .filter { [weak self] in
                self?.notifyValueDidChange == true
            }
            .eraseToAnyPublisher()
    }

    @Published var syncedValue: String? {
        didSet {
            notifyValueDidChange = true
        }
    }

    private var notifyValueDidChange: Bool = true
}
