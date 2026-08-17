//
//  UnknownModelLabelReporter.swift
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

import AIChat
import Foundation

@MainActor
protocol UnknownModelLabelReporting {
    func reportUnknownLabels(in models: [AIChatModel])
}

/// Reports `/v1/models` recommendation labels the updated model picker doesn't recognise. An unknown
/// label renders as a model row with no subline, so a new backend label is otherwise invisible on the
/// client — this is the debug signal that one shipped.
@MainActor
final class UnknownModelLabelReporter: UnknownModelLabelReporting {
    private let firing: UTIPixelFiring
    private let isUpdatedModelPickerEnabled: () -> Bool
    /// Labels already reported by this instance. The same unknown label repeats on every `/models`
    /// refresh, and this is a monitoring signal — one report per label per app run is enough.
    private var reportedLabels: Set<String> = []

    init(firing: UTIPixelFiring = .live, isUpdatedModelPickerEnabled: @escaping () -> Bool = { UpdatedModelPickerFeature().isAvailable }) {
        self.firing = firing
        self.isUpdatedModelPickerEnabled = isUpdatedModelPickerEnabled
    }

    func reportUnknownLabels(in models: [AIChatModel]) {
        guard isUpdatedModelPickerEnabled() else { return }

        let labels = Set(models.compactMap { Self.unrecognisedRawLabel(of: $0) })
        let unreportedLabels = labels.subtracting(reportedLabels)
        reportedLabels.formUnion(unreportedLabels)

        unreportedLabels.forEach {
            firing.fire(.unifiedToggleInputUnknownModelLabelDebug, ["label": $0])
        }
    }

    private static func unrecognisedRawLabel(of model: AIChatModel) -> String? {
        switch model.label {
        case .some(.unknown(let rawValue)):
            return rawValue
        case .some(.everydayUse), .some(.usesLimitsFaster), .none:
            return nil
        }
    }
}
