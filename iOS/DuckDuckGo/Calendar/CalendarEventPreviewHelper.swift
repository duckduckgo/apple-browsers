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

    /// Fires after the editor dismisses, or immediately when we fall back to QuickLook.
    var onDismiss: (() -> Void)?

    /// Fires after the editor dismisses with the user having tapped Add.
    var onSaved: (() -> Void)?

    /// Fires after QuickLook is presented for the fallback cases; never on iOS <17.
    var onFailure: ((Failure) -> Void)?

    private let filePath: URL
    private weak var viewController: UIViewController?

    required init(_ filePath: URL, viewController: UIViewController) {
        self.filePath = filePath
        self.viewController = viewController
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
            fallbackToQuickLook(reporting: .parseFailure)
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

    /// Toast fires in QL's `present` completion so it stacks above QL. The pre-dismiss
    /// keeps UIKit from silently dropping `present` when a modal (address-bar editing,
    /// etc.) is already up.
    private func fallbackToQuickLook(reporting failure: Failure?) {
        let reportFailure = onFailure
        let reportDismiss = onDismiss
        guard let viewController else {
            if let failure { reportFailure?(failure) }
            reportDismiss?()
            return
        }
        let presentQuickLook = { [filePath] in
            let iPadFormSheet: UIModalPresentationStyle? = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : nil
            QuickLookPreviewHelper(filePath, viewController: viewController)
                .preview(modalPresentationStyle: iPadFormSheet) {
                    if let failure { reportFailure?(failure) }
                    reportDismiss?()
                }
        }
        if let presented = viewController.presentedViewController {
            presented.dismiss(animated: false, completion: presentQuickLook)
        } else {
            presentQuickLook()
        }
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
