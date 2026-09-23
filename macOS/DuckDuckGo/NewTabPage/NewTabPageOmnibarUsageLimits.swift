//
//  NewTabPageOmnibarUsageLimits.swift
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
import NewTabPage

extension NewTabPageDataModel.OmnibarUsageLimits {

    init(warning: DuckAiUsageWarning, alternatives: [AIChatModel]) {
        // A reached limit reads as an alert: a nearly-full ring says less than the copy already does.
        let isApproaching = warning.message == .approaching
        self.init(
            message: warning.localizedHeadline,
            // The drawer inserts no separator of its own.
            secondaryText: " · " + warning.localizedResetsIn,
            dismissible: warning.isDismissible,
            icon: isApproaching ? .ring : .alert,
            percent: isApproaching ? warning.percent : nil,
            severity: isApproaching ? .init(warning.severity) : nil,
            blocksPrompt: warning.blocksInput,
            cta: Cta(warning: warning, alternatives: alternatives)
        )
    }

    init(notice: DuckAiHighUsageModelNotice) {
        self.init(message: UserText.aiChatUsageWarningsHighUsageModel(notice.modelShortName),
                  dismissible: true,
                  icon: .info)
    }
}

private extension NewTabPageDataModel.OmnibarUsageLimits.Severity {

    init(_ severity: DuckAiUsageSeverity) {
        switch severity {
        case .info: self = .neutral
        case .warning: self = .warning
        case .critical, .reached: self = .critical
        }
    }
}

private extension NewTabPageDataModel.OmnibarUsageLimits.Cta {

    /// `nil` hides the button, which is also how a switch with nothing to switch to renders.
    init?(warning: DuckAiUsageWarning, alternatives: [AIChatModel]) {
        guard let label = warning.localizedActionTitle else { return nil }

        let rows = alternatives.map { Alternative(id: $0.id, name: $0.shortName.isEmpty ? $0.name : $0.shortName) }
        self.init(label: label,
                  leadingIcon: warning.actionSwapsModel ? .convert : .textOnly,
                  primaryModelId: warning.action?.suggestedModelId,
                  showMenu: !rows.isEmpty,
                  alternatives: rows)
    }
}
