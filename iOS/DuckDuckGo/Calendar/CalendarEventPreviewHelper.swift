//
//  CalendarEventPreviewHelper.swift
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

import Core
import EventKit
import EventKitUI
import ICSParser
import UIKit

/// Presents a single-VEVENT `.ics` file via `EKEventEditViewController` on iOS 17+; falls back
/// to `QuickLookPreviewHelper` for parse failures, multi-VEVENT files, and older iOS.
///
/// Owner must keep a strong reference until `onDismiss` fires — the editor's delegate is weak.
final class CalendarEventPreviewHelper: NSObject, FilePreview {

    /// Reason the helper couldn't auto-add the event. Surfaced via `onFailure` so the caller
    /// can show a toast in the appropriate location.
    enum Failure {
        case multipleEvents
        case unrecognizedTimeZone
        case parseFailure
    }

    /// Fires after the editor dismisses, or immediately when we fall back to QuickLook.
    var onDismiss: (() -> Void)?

    /// Fires before falling back to QuickLook when we can't auto-add the event. Not fired for
    /// pre-iOS-17 devices, since the feature simply isn't supported there.
    var onFailure: ((Failure) -> Void)?

    private let filePath: URL
    private weak var viewController: UIViewController?

    required init(_ filePath: URL, viewController: UIViewController) {
        self.filePath = filePath
        self.viewController = viewController
        super.init()
    }

    func preview() {
        switch readICSFile() {
        case .singleEvent(let event):
            if #available(iOS 17.0, *) {
                presentEventEditor(for: event)
            } else {
                fallbackToQuickLook()
            }
        case .multipleEvents:
            Pixel.fire(pixel: .icsCalendarFallbackMultipleEvents)
            onFailure?(.multipleEvents)
            fallbackToQuickLook()
        case .unrecognizedTimeZone:
            Pixel.fire(pixel: .icsCalendarFallbackUnrecognizedTimeZone)
            onFailure?(.unrecognizedTimeZone)
            fallbackToQuickLook()
        case .parseFailure:
            Pixel.fire(pixel: .icsCalendarFallbackParseFailure)
            onFailure?(.parseFailure)
            fallbackToQuickLook()
        }
    }

    private enum ReadResult {
        case singleEvent(ICSEvent)
        case multipleEvents
        case unrecognizedTimeZone
        case parseFailure
    }

    private func readICSFile() -> ReadResult {
        guard let data = try? Data(contentsOf: filePath) else {
            return .parseFailure
        }
        do {
            let result = try ICSParser.parse(data: data)
            if result.warnings.contains(.unsupportedRRulePart) {
                Pixel.fire(pixel: .icsCalendarUnsupportedRRule)
            }
            return result.events.count == 1 ? .singleEvent(result.events[0]) : .multipleEvents
        } catch ICSParser.Error.unrecognizedTimeZone(_) {
            return .unrecognizedTimeZone
        } catch {
            return .parseFailure
        }
    }

    @available(iOS 17.0, *)
    private func presentEventEditor(for icsEvent: ICSEvent) {
        guard let viewController else {
            onDismiss?()
            return
        }
        let store = EKEventStore()
        let editor = EKEventEditViewController()
        editor.event = Self.makeEKEvent(from: icsEvent, in: store)
        editor.eventStore = store
        editor.editViewDelegate = self
        Pixel.fire(pixel: .icsCalendarEditorPresented)
        viewController.present(editor, animated: true)
    }

    /// Bridges `ICSEvent` to `EKEvent`. Shared by the UIKit and SwiftUI presentation paths.
    @available(iOS 17.0, *)
    static func makeEKEvent(from icsEvent: ICSEvent, in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = icsEvent.title
        event.startDate = icsEvent.startDate
        event.endDate = icsEvent.endDate
        event.isAllDay = icsEvent.isAllDay
        event.location = icsEvent.location
        event.notes = icsEvent.notes
        event.url = icsEvent.url
        if let rule = icsEvent.recurrenceRule {
            event.recurrenceRules = [rule]
        }
        return event
    }

    private func fallbackToQuickLook() {
        defer { onDismiss?() }
        guard let viewController else { return }
        QuickLookPreviewHelper(filePath, viewController: viewController).preview()
    }
}

@available(iOS 17.0, *)
extension CalendarEventPreviewHelper: EKEventEditViewDelegate {

    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        switch action {
        case .saved:
            Pixel.fire(pixel: .icsCalendarEditorSaved)
        case .canceled, .deleted:
            Pixel.fire(pixel: .icsCalendarEditorCancelled)
        @unknown default:
            break
        }
        controller.dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}
