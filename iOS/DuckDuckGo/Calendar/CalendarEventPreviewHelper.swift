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
import UIKitExtensions

/// Owner must keep a strong reference until `onDismiss` fires — the editor's delegate is weak.
final class CalendarEventPreviewHelper: NSObject, FilePreview {

    enum Failure {
        case multipleEvents
        case unrecognizedTimeZone
        case parseFailure
    }

    /// Presents `filePath` in QuickLook as a fallback, calling `completion` once it animates in.
    typealias QuickLookPresentation = (_ filePath: URL, _ viewController: UIViewController, _ completion: @escaping () -> Void) -> Void

    /// Fires after the editor dismisses, after a fallback QuickLook preview is presented, or
    /// immediately when a malformed file is reported without a preview.
    var onDismiss: (() -> Void)?

    /// Fires after the editor dismisses with the user having tapped Add.
    var onSaved: (() -> Void)?

    /// Fires when a fallback is reported: alongside a QuickLook preview for valid-but-unhandled files
    /// (`multipleEvents`, `unrecognizedTimeZone`), or on its own for a malformed file. Never on iOS <17.
    var onFailure: ((Failure) -> Void)?

    private let filePath: URL
    private weak var viewController: UIViewController?
    private let presentQuickLook: QuickLookPresentation

    required convenience init(_ filePath: URL, viewController: UIViewController) {
        self.init(filePath, viewController: viewController, presentQuickLook: QuickLookPreviewHelper.presentAsFallback)
    }

    init(_ filePath: URL,
         viewController: UIViewController,
         presentQuickLook: @escaping QuickLookPresentation) {
        self.filePath = filePath
        self.viewController = viewController
        self.presentQuickLook = presentQuickLook
        super.init()
    }

    func preview() {
        // No EKEventEditViewController flow on iOS <17, so skip classification — failure
        // toasts would wrongly imply the file is the problem.
        guard #available(iOS 17.0, *) else {
            fallbackToQuickLook(reporting: nil)
            return
        }
        let result = ICSFileReader.read(at: filePath)
        if result.warnings.contains(.unsupportedRRulePart) {
            Pixel.fire(pixel: .icsCalendarUnsupportedRRule)
        }
        switch result.outcome {
        case .singleEvent(let event):
            presentEventEditor(for: event)
        case .multipleEvents:
            Pixel.fire(pixel: .icsCalendarFallbackMultipleEvents)
            fallbackToQuickLook(reporting: .multipleEvents)
        case .unrecognizedTimeZone:
            Pixel.fire(pixel: .icsCalendarFallbackUnrecognizedTimeZone)
            fallbackToQuickLook(reporting: .unrecognizedTimeZone)
        case .parseFailure:
            Pixel.fire(pixel: .icsCalendarFallbackParseFailure)
            reportFailureWithoutPreview(.parseFailure)
        }
    }

    @available(iOS 17.0, *)
    private func presentEventEditor(for icsEvent: ICSEvent) {
        guard let viewController else {
            onDismiss?()
            return
        }
        let presenter = viewController.topMostPresentedViewController() ?? viewController
        let store = EKEventStore()
        let editor = EKEventEditViewController()
        editor.event = Self.makeEKEvent(from: icsEvent, in: store)
        editor.eventStore = store
        editor.editViewDelegate = self
        Pixel.fire(pixel: .icsCalendarEditorPresented)
        presenter.present(editor, animated: true)
    }

    @available(iOS 17.0, *)
    static func firePixel(for action: EKEventEditViewAction) {
        switch action {
        case .saved:
            Pixel.fire(pixel: .icsCalendarEditorSaved)
        case .canceled, .deleted:
            Pixel.fire(pixel: .icsCalendarEditorCancelled)
        @unknown default:
            break
        }
    }

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

    private func fallbackToQuickLook(reporting failure: Failure?) {
        let reportFailure = onFailure
        let reportDismiss = onDismiss
        let report = {
            if let failure { reportFailure?(failure) }
            reportDismiss?()
        }
        guard let viewController else {
            report()
            return
        }
        presentQuickLook(filePath, viewController, report)
    }

    /// A malformed `.ics` only renders a "couldn't open" placeholder in QuickLook, so we skip the
    /// preview entirely: the failure toast already points the user to Downloads.
    private func reportFailureWithoutPreview(_ failure: Failure) {
        onFailure?(failure)
        onDismiss?()
    }
}

@available(iOS 17.0, *)
extension CalendarEventPreviewHelper: EKEventEditViewDelegate {

    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        CalendarEventPreviewHelper.firePixel(for: action)
        controller.dismiss(animated: true) { [weak self] in
            if action == .saved {
                self?.onSaved?()
            }
            self?.onDismiss?()
        }
    }
}
