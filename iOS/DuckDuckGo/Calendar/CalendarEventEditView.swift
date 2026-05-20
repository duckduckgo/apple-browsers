//
//  CalendarEventEditView.swift
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
import SwiftUI

/// EKEvent + its store. `EKEvent.eventStore` is weak, so we keep both alive while the editor
/// is presented.
struct PreparedCalendarEvent {
    let event: EKEvent
    let store: EKEventStore
}

@available(iOS 17.0, *)
struct CalendarEventEditView: UIViewControllerRepresentable {

    let preparedEvent: PreparedCalendarEvent
    let onSaved: () -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.event = preparedEvent.event
        editor.eventStore = preparedEvent.store
        editor.editViewDelegate = context.coordinator
        Pixel.fire(pixel: .icsCalendarEditorPresented)
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaved: onSaved, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onSaved: () -> Void
        private let onDismiss: () -> Void

        init(onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
            self.onSaved = onSaved
            self.onDismiss = onDismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            CalendarEventPreviewHelper.firePixel(for: action)
            controller.dismiss(animated: true) { [onSaved, onDismiss] in
                if action == .saved {
                    onSaved()
                }
                onDismiss()
            }
        }
    }
}
