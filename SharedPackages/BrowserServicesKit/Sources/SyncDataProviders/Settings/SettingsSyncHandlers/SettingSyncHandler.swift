//
//  SettingSyncHandler.swift
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
import Common
import Foundation

open class SettingSyncHandler: SettingSyncHandling {

    open var setting: SettingsProvider.Setting {
        assertionFailure("implementation missing for \(#function)")
        return .init(key: "")
    }

    open var valueDidChangePublisher: AnyPublisher<Void, Never> {
        assertionFailure("implementation missing for \(#function)")
        return Empty<Void, Never>().eraseToAnyPublisher()
    }

    open func getValue() throws -> String? {
        assertionFailure("implementation missing for \(#function)")
        return nil
    }

    open func setValue(_ value: String?, shouldDetectOverride: Bool) throws {
        assertionFailure("implementation missing for \(#function)")
    }

    public init(metricsEvents: EventMapping<MetricsEvent>? = nil) {
        self.metricsEvents = metricsEvents
        valueDidChangeCancellable = valueDidChangePublisher
            .sink { [weak self] in
                guard let self else {
                    return
                }
                assert(self.delegate != nil, "delegate has not been set for \(type(of: self))")
                self.delegate?.syncHandlerDidUpdateSettingValue(self)
            }
    }

    let metricsEvents: EventMapping<MetricsEvent>?
    weak var delegate: SettingSyncHandlingDelegate?
    private var valueDidChangeCancellable: AnyCancellable?
}
