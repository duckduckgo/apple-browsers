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
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.event = preparedEvent.event
        editor.eventStore = preparedEvent.store
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
            onDismiss()
        }
    }
}
