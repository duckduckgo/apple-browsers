//
//  TaskModelPicker.swift
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

import DuckAIChatMLX
import SwiftUI

/// A menu rather than a Picker, so models that can't run yet are listed but greyed out.
struct TaskModelPicker: View {
    let title: String
    let task: DuckAINativeSettings.LocalTask
    @ObservedObject var settings: DuckAINativeSettings

    private var selection: DuckAINativeSettings.TaskModel {
        settings.taskModels[task] ?? .automatic
    }

    var body: some View {
        LabeledContent(title) {
            Menu {
                option(task == .chat ? "Automatic" : "Same as chat", .automatic)
                option("Stub", .stub)
                option("Apple Foundation Models", .foundationModels, enabled: NativeChatProviderFactory.isFoundationModelsAvailable)
                Section("MLX") {
                    ForEach(ModelCatalog.all) { model in
                        let downloaded = Self.isDownloaded(model)
                        option(downloaded ? model.displayName : "\(model.displayName), not downloaded", .mlx(id: model.id),
                               enabled: downloaded)
                    }
                }
            } label: {
                Text(Self.name(of: selection, task: task))
            }
            .accessibilityIdentifier("NativeChatDebug.Model.\(task.rawValue)")
        }
    }

    private func option(_ label: String, _ model: DuckAINativeSettings.TaskModel, enabled: Bool = true) -> some View {
        Button {
            settings.taskModels[task] = model
        } label: {
            if model == selection {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
        .disabled(!enabled)
    }

    static func isDownloaded(_ model: Model) -> Bool {
        if case .downloaded = NativeChatProviderFactory.modelStore.state(of: model) { return true }
        return false
    }

    static func name(of model: DuckAINativeSettings.TaskModel, task: DuckAINativeSettings.LocalTask) -> String {
        switch model {
        case .automatic: task == .chat ? "Automatic" : "Same as chat"
        case .stub: "Stub"
        case .foundationModels: "Foundation Models"
        case .mlx(let id):
            ModelCatalog.model(withID: id).map { isDownloaded($0) ? $0.displayName : "\($0.displayName) (not downloaded)" } ?? id
        }
    }
}
