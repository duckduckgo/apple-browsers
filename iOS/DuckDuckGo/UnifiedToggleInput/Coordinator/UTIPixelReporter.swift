//
//  UTIPixelReporter.swift
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
import Core
import Foundation

/// Injectable pixel-firing seam: bundles the two standard firers (`PixelFiring` for one-off pixels,
/// `DailyPixelFiring` for daily-and-count) behind one value so UTI pixel firing has a single
/// injection point. `.live` fires for real; tests pass `PixelFiringMock` to assert what was fired.
struct UTIPixelFiring {
    var pixel: PixelFiring.Type = Pixel.self
    var daily: DailyPixelFiring.Type = DailyPixel.self

    static let live = UTIPixelFiring()

    func fire(_ event: Pixel.Event, _ parameters: [String: String] = [:]) {
        pixel.fire(event, withAdditionalParameters: parameters)
    }

    func fireDailyAndCount(_ event: Pixel.Event, _ parameters: [String: String] = [:]) {
        daily.fireDailyAndCount(event, error: nil, withAdditionalParameters: parameters)
    }
}

/// Live snapshot of the coordinator state a pixel needs, resolved at fire time (never captured) so a
/// pixel always reports the surface/mode as they are the instant it fires. Kept to O(1) reads —
/// per-call inputs (e.g. the mode-switch text/default) are passed to the reporting method instead.
struct UTIPixelContext {
    let surface: UnifiedToggleInputPixelSurface
    let isDuckAISurfaceForAttribution: Bool
    let inputMode: TextEntryMode
}

/// Owns the omnibar UTI's pixel firing. Resolves the surface (and the other live inputs) through a
/// per-fire context so call sites no longer thread `surface:`/`isAITabState:` around; routes every
/// fire through the injected `UTIPixelFiring` seam. Wraps the shared
/// `UnifiedToggleInputCoordinatorPixelHelper` for the pixels also fired from other surfaces (iPad).
@MainActor
final class UTIPixelReporter {

    private let firing: UTIPixelFiring
    private let context: () -> UTIPixelContext?

    init(firing: UTIPixelFiring = .live, context: @escaping () -> UTIPixelContext?) {
        self.firing = firing
        self.context = context
    }

    // MARK: - Session / omnibar surface

    /// The pair fired whenever the unified input surface first appears in the omnibar host.
    func reportOmnibarInputSurfaceShown() {
        firing.fireDailyAndCount(.aiChatInternalSwitchBarDisplayed)
        firing.fireDailyAndCount(.aiChatExperimentalOmnibarShown)
    }

    func reportBackButtonPressed() {
        withContext { firing.fire(.aiChatExperimentalOmnibarBackButtonPressed, ["mode": $0.inputMode.rawValue]) }
    }

    func reportFloatingReturnPressed() {
        firing.fire(.aiChatExperimentalOmnibarFloatingReturnPressed)
    }

    func reportModeSwitched(to mode: TextEntryMode, currentText: String, defaultOmnibarMode: DefaultOmnibarMode) {
        let direction = mode == .search ? "to_search" : "to_duckai"
        let hadText = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        firing.fire(.aiChatExperimentalOmnibarModeSwitched, [
            "direction": direction,
            "had_text": String(hadText),
            "default_position": defaultOmnibarMode.rawValue
        ])
    }

    func reportStopGenerationTapped() {
        withContext { firing.fire(.unifiedToggleInputStopGenerationTapped, ["surface": $0.surface.rawValue]) }
    }

    func reportVoiceTapped(hasPendingPageContext: Bool) {
        withContext {
            firing.fireDailyAndCount(.unifiedToggleInputVoiceTapped, [
                "source": $0.surface.rawValue,
                "has_pending_page_context": hasPendingPageContext ? "true" : "false"
            ])
        }
    }

    // MARK: - Attachments

    func reportFileValidationFailed(reason: UTIAttachmentPolicy.FileValidationFailureReason, source: String) {
        reportFileValidationFailed(reason: reason.rawValue, source: source)
    }

    /// Raw-reason variant for the paste-rejection path, which derives its reason outside the policy's `FileValidationFailureReason`.
    func reportFileValidationFailed(reason: String, source: String) {
        withContext {
            firing.fireDailyAndCount(.unifiedToggleInputFileValidationFailed, [
                "reason": reason,
                "surface": $0.surface.rawValue,
                "source": source
            ])
        }
    }

    func reportFileAttached(source: String) {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputFileAttached, ["surface": $0.surface.rawValue, "source": source]) }
    }

    func reportImageAttached(source: String) {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputImageAttached, ["surface": $0.surface.rawValue, "source": source]) }
    }

    func reportAttachmentRemoved(_ attachment: UnifiedToggleInputAttachment) {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireAttachmentRemovedPixel(for: attachment, surface: $0.surface, firing: firing) }
    }

    // MARK: - Model / reasoning / tools

    func reportModelSelected(modelId: String) {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireModelSelectedPixel(modelId: modelId, surface: $0.surface, firing: firing) }
    }

    func reportReasoningEffortSelected(mode: AIChatReasoningMode) {
        withContext {
            firing.fire(.unifiedToggleInputReasoningEffortSelected, [
                "effort_level": mode.rawValue,
                "surface": $0.surface.rawValue
            ])
        }
    }

    func reportModelPickerShown() {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireModelPickerShownPixel(isAITabState: $0.isDuckAISurfaceForAttribution, firing: firing) }
    }

    func reportReasoningPickerShown() {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireReasoningPickerShownPixel(isAITabState: $0.isDuckAISurfaceForAttribution, firing: firing) }
    }

    func reportShowModelPicker() {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputShowModelPicker, ["surface": $0.surface.rawValue]) }
    }

    func reportSubmitChangeModel(modelId: String) {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputSubmitChangeModel, ["model_id": modelId, "surface": $0.surface.rawValue]) }
    }

    func reportSubmitChangeModelPromptSent() {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputSubmitChangeModelPromptSent, ["surface": $0.surface.rawValue]) }
    }

    func reportToolSelected(_ tool: AIChatRAGTool) {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireToolSelectedPixel(for: tool, surface: $0.surface, firing: firing) }
    }

    func reportToolDeselected(_ tool: AIChatRAGTool) {
        withContext { UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: tool, surface: $0.surface, firing: firing) }
    }

    func reportCustomizeResponsesSelected() {
        withContext { firing.fireDailyAndCount(.unifiedToggleInputCustomizeResponsesSelected, ["surface": $0.surface.rawValue]) }
    }

    // MARK: - Submission

    func reportPromptSubmitted(hasText: Bool,
                               selectedTool: AIChatRAGTool?,
                               attachments: [UnifiedToggleInputAttachment],
                               reasoningMode: AIChatReasoningMode?,
                               modelId: String?) {
        withContext {
            UnifiedToggleInputCoordinatorPixelHelper.fireUnifiedPromptSubmittedPixel(
                hasText: hasText,
                selectedTool: selectedTool,
                attachments: attachments,
                reasoningMode: reasoningMode,
                modelId: modelId,
                surface: $0.surface,
                firing: firing
            )
        }
    }

    func reportToolSubmittedIfNeeded(selectedTool: AIChatRAGTool?, attachments: [UnifiedToggleInputAttachment]) {
        withContext {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolSubmittedPixelIfNeeded(
                selectedTool: selectedTool,
                attachments: attachments,
                surface: $0.surface,
                firing: firing
            )
        }
    }

    // MARK: - Context resolution

    /// Resolves the live context and runs `body`; a nil context (coordinator gone) fires nothing.
    private func withContext(_ body: (UTIPixelContext) -> Void) {
        guard let context = context() else { return }
        body(context)
    }
}
