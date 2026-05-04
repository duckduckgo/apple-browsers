//
//  TabInputState.swift
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

import AIChat

typealias TabUID = String

struct TabInputState: Equatable {
    var text: String
    var toggleMode: TextEntryMode
    var attachments: [AIChatImageAttachment]
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?

    init(
        text: String = "",
        toggleMode: TextEntryMode = .search,
        attachments: [AIChatImageAttachment] = [],
        selectedModelID: String? = nil,
        selectedReasoningMode: AIChatReasoningMode? = nil,
        selectedTool: AIChatRAGTool? = nil
    ) {
        self.text = text
        self.toggleMode = toggleMode
        self.attachments = attachments
        self.selectedModelID = selectedModelID
        self.selectedReasoningMode = selectedReasoningMode
        self.selectedTool = selectedTool
    }
}
