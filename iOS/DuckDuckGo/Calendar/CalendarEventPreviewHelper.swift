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

import EventKit
import EventKitUI
import ICSParser
import UIKit

/// Presents a single-VEVENT `.ics` file via `EKEventEditViewController` on iOS 17+; falls back
/// to `QuickLookPreviewHelper` for parse failures, multi-VEVENT files, and older iOS.
///
/// Owner must keep a strong reference until `onDismiss` fires — the editor's delegate is weak.
final class CalendarEventPreviewHelper: NSObject, FilePreview {

    /// Fires after the editor dismisses, or immediately when we fall back to QuickLook.
    var onDismiss: (() -> Void)?

    private let filePath: URL
    private weak var viewController: UIViewController?

    required init(_ filePath: URL, viewController: UIViewController) {
        self.filePath = filePath
        self.viewController = viewController
        super.init()
    }

    func preview() {
        if #available(iOS 17.0, *), let event = singleEvent() {
            presentEventEditor(for: event)
        } else {
            fallbackToQuickLook()
        }
    }

    private func singleEvent() -> ICSEvent? {
        guard let data = try? Data(contentsOf: filePath),
              let events = try? ICSParser.parse(data: data),
              events.count == 1 else {
            return nil
        }
        return events[0]
    }

    @available(iOS 17.0, *)
    private func presentEventEditor(for icsEvent: ICSEvent) {
        guard let viewController else {
            onDismiss?()
            return
        }
        let store = EKEventStore()
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

        let editor = EKEventEditViewController()
        editor.event = event
        editor.eventStore = store
        editor.editViewDelegate = self
        viewController.present(editor, animated: true)
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
        controller.dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}
