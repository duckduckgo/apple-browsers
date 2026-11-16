//
//  AIChatNativePermissionPresenter.swift
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
import UIKit

@MainActor
protocol AIChatNativePermissionPresenting: AnyObject {
    func isAvailable(for requestID: String?) -> Bool
    var isPresentingPermission: Bool { get }
    func present(_ prompt: ClientToolPermissionPrompt, message: String, decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool
    func withdraw(requestID: String, completion: @escaping @MainActor () -> Void)
    func withdrawActive(completion: @escaping @MainActor () -> Void)
}

@MainActor
final class AIChatNativePermissionPresenter: AIChatNativePermissionPresenting {
    private enum Phase { case presenting, presented, dismissing }

    private final class Presentation {
        let requestID: String
        let alert: UIAlertController
        var phase = Phase.presenting
        var dismissalRequested = false
        var decisionSelected = false
        var completions: [@MainActor () -> Void] = []

        init(requestID: String, alert: UIAlertController) {
            self.requestID = requestID
            self.alert = alert
        }
    }

    private let surface: @MainActor () -> UIViewController?
    private let show: @MainActor (UIViewController, UIAlertController, @escaping @MainActor () -> Void) -> Bool
    private let dismiss: @MainActor (UIAlertController, @escaping @MainActor () -> Void) -> Void
    private var active: Presentation?

    init(surface: @escaping @MainActor () -> UIViewController?,
         show: @escaping @MainActor (UIViewController, UIAlertController, @escaping @MainActor () -> Void) -> Bool = { owner, alert, completion in
             owner.present(alert, animated: true, completion: completion)
             return alert.presentingViewController != nil
         },
         dismiss: @escaping @MainActor (UIAlertController, @escaping @MainActor () -> Void) -> Void = { alert, completion in
             guard alert.presentingViewController != nil else { completion(); return }
             if alert.isBeingDismissed, let transition = alert.transitionCoordinator,
                transition.animate(alongsideTransition: nil, completion: { _ in completion() }) {
                 return
             }
             alert.dismiss(animated: true, completion: completion)
         }) {
        self.surface = surface
        self.show = show
        self.dismiss = dismiss
    }

    var isPresentingPermission: Bool { active != nil }

    func isAvailable(for requestID: String?) -> Bool {
        if let active, active.requestID != requestID { return false }
        guard let owner = surface(), owner.viewIfLoaded?.window != nil,
              !owner.isBeingDismissed, !owner.isBeingPresented else { return false }
        var branch: UIViewController? = owner
        var child: UIViewController?
        while let controller = branch {
            guard !controller.isBeingDismissed, !controller.isBeingPresented else { return false }
            if let presented = controller.presentedViewController, presented !== active?.alert, presented !== child { return false }
            child = controller
            branch = controller.parent ?? controller.presentingViewController
        }
        return true
    }

    func present(_ prompt: ClientToolPermissionPrompt, message: String, decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool {
        guard active == nil, isAvailable(for: prompt.requestID), let owner = surface() else { return false }
        let alert = UIAlertController(title: "Duck.ai", message: message, preferredStyle: .alert)
        let presentation = Presentation(requestID: prompt.requestID, alert: alert)
        let choices: [(String, ClientToolPermissionDecision, UIAlertAction.Style)] = [
            ("Allow once", .allowOnce, .default), ("Always", .always, .default),
            ("Never", .never, .destructive), ("Cancel", .dismiss, .cancel)
        ]
        for (title, choice, style) in choices {
            alert.addAction(UIAlertAction(title: title, style: style) { [weak self, weak presentation] _ in
                guard let self, let presentation, self.active === presentation, !presentation.decisionSelected else { return }
                presentation.decisionSelected = true
                self.withdraw(requestID: presentation.requestID) { decision(choice) }
            })
        }
        active = presentation
        let shown = show(owner, alert) { [weak self, weak presentation] in
            guard let self, let presentation, self.active === presentation else { return }
            presentation.phase = .presented
            if presentation.dismissalRequested { self.dismiss(presentation) }
        }
        if !shown { completeDismissal(presentation) }
        return shown
    }

    func withdrawActive(completion: @escaping @MainActor () -> Void) {
        guard let active else { completion(); return }
        withdraw(requestID: active.requestID, completion: completion)
    }

    func withdraw(requestID: String, completion: @escaping @MainActor () -> Void) {
        guard let presentation = active, presentation.requestID == requestID else {
            completion()
            return
        }
        presentation.completions.append(completion)
        presentation.dismissalRequested = true
        if case .presented = presentation.phase { dismiss(presentation) }
    }

    private func dismiss(_ presentation: Presentation) {
        presentation.phase = .dismissing
        dismiss(presentation.alert) { [weak self, presentation] in
            self?.completeDismissal(presentation)
        }
    }

    private func completeDismissal(_ presentation: Presentation) {
        guard active === presentation else { return }
        active = nil
        let completions = presentation.completions
        presentation.completions.removeAll()
        completions.forEach { $0() }
    }
}
