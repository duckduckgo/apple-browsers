//
//  MultiTabAttachmentRequest.swift
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

/// A frozen attachment selection, collected before its prompt is dispatched.
struct MultiTabAttachmentRequest {
    /// Returns available contexts in attachment order. Additional tabs carry their stable `tabId`;
    /// only the current page may omit it. Preparation and its timeouts belong to the provider.
    let contexts: @MainActor () async -> [AIChatPageContextData]
    let didConsume: @MainActor () -> Void
}
