//
//  NewTabPageConfigurationEventHandler.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Common
import FoundationExtensions
import NewTabPage
import PixelKit

final class NewTabPageConfigurationEventHandler: EventMapping<NewTabPageConfigurationEvent> {

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        super.init { event, _, _, _ in
            switch event {
            case .newTabPageError:
                PixelKit.fire(DebugEvent(NewTabPagePixel.newTabPageExceptionReported), frequency: .dailyAndStandard)

            case .newTabPageTelemetry(.customizerOpened(let themePopoverWasOpen)):
                PixelKit.fire(NewTabPagePixel.customizerShown(themePopoverWasOpen: themePopoverWasOpen))

            case .newTabPageTelemetry(.customizerClosed):
                PixelKit.fire(NewTabPagePixel.customizerHidden)

            // Duck.ai omnibar picker impressions. The frontend owns these pickers, so a reported
            // telemetry event is the only signal native gets that a gated row was on screen.
            case .newTabPageTelemetry(.omnibarModelPickerShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpModelPickerShown, .newTabPageModelPicker)

            case .newTabPageTelemetry(.omnibarModelPickerTryForFreeShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpModelPickerTryForFreeShown, .newTabPageModelPicker)

            case .newTabPageTelemetry(.omnibarModelPickerUpgradeShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpModelPickerUpgradeShown, .newTabPageModelPicker)

            case .newTabPageTelemetry(.omnibarReasoningPickerShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpReasoningPickerShown, .newTabPageReasoningDropdown)

            case .newTabPageTelemetry(.omnibarReasoningPickerTryForFreeShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpReasoningPickerTryForFreeShown, .newTabPageReasoningDropdown)

            case .newTabPageTelemetry(.omnibarReasoningPickerUpgradeShown):
                Self.fireOmnibarPickerImpression(AIChatPixel.aiChatNtpReasoningPickerUpgradeShown, .newTabPageReasoningDropdown)

            // Image and screenshot chips: the page owns them, so its telemetry is the only signal.
            case .newTabPageTelemetry(.omnibarImageAttached(let rawSource)):
                guard let source = AIChatImageAttachmentSource(rawValue: rawSource) else { return }
                pixelFiring?.fire(AIChatPixel.aiChatNtpImageAttached(source: source), frequency: .dailyAndCount)

            case .newTabPageTelemetry(.omnibarImageRemoved(let rawSource)):
                guard let source = AIChatImageAttachmentSource(rawValue: rawSource) else { return }
                pixelFiring?.fire(AIChatPixel.aiChatNtpImageRemoved(source: source), frequency: .dailyAndCount)

            case .newTabPageTelemetry(.omnibarScreenshotTaken(let rawKind)):
                guard let kind = AIChatScreenshotKind(rawValue: rawKind) else { return }
                pixelFiring?.fire(AIChatPixel.aiChatNtpScreenshotTaken(kind: kind), frequency: .dailyAndCount)

            case .newTabPageTelemetry(.omnibarScreenshotRemoved):
                pixelFiring?.fire(AIChatPixel.aiChatNtpScreenshotRemoved, frequency: .dailyAndCount)

            case .newTabPageTelemetry(.omnibarScreenshotFailed(let rawReason)):
                guard let reason = AIChatScreenshotFailureReason(rawValue: rawReason) else { return }
                pixelFiring?.fire(AIChatPixel.aiChatNtpScreenshotFailed(reason: reason), frequency: .dailyAndCount)
            }
        }
    }

    override init(mapping: @escaping EventMapping<NewTabPageConfigurationEvent>.Mapping) {
        fatalError("Use init()")
    }

    private static func fireOmnibarPickerImpression(_ makePixel: (String) -> AIChatPixel,
                                                    _ origin: SubscriptionFunnelOrigin) {
        PixelKit.fire(makePixel(origin.rawValue), frequency: .dailyAndCount, includeAppVersionParameter: true)
    }
}
