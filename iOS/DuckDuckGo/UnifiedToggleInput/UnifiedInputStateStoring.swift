//
//  UnifiedInputStateStoring.swift
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

struct LastUsedInputDefaults: Equatable {
    var toggleMode: TextEntryMode
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
}

@MainActor
protocol UnifiedInputStateStoring: AnyObject {
    func state(for uid: TabUID) -> TabInputState
    func update(_ state: TabInputState, for uid: TabUID)
    func remove(for uid: TabUID)
    var lastUsed: LastUsedInputDefaults { get }
}
