//
//  AssistedOptOutText.swift
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

import Foundation

enum AssistedOptOutText {
    static let notStarted = NSLocalizedString("pir.assisted.status.not-started", bundle: .module,
                                                 value: "Not started",
                                                 comment: "Status before an assisted removal begins.")

    static let agentInControl = NSLocalizedString("pir.assisted.status.agent", bundle: .module,
                                                 value: "DuckDuckGo is in control",
                                                 comment: "Status while DuckDuckGo fills in a removal form.")

    static let waitingForYou = NSLocalizedString("pir.assisted.status.user", bundle: .module,
                                                 value: "DuckDuckGo is waiting for you",
                                                 comment: "Status while the user completes a removal step.")

    static let finished = NSLocalizedString("pir.assisted.status.finished", bundle: .module,
                                                 value: "Finished",
                                                 comment: "Status after the removal request is submitted.")

    static let closingStops = NSLocalizedString("pir.assisted.closing-stops", bundle: .module,
                                                 value: "Closing stops this removal",
                                                 comment: "Explains that closing an unfinished removal window cancels it.")

    static let experimentalNote = NSLocalizedString("pir.assisted.experimental-note", bundle: .module,
                                                 value: "Getting help with removals is new. Your feedback will help us improve it.",
                                                 comment: "Footer note in the assisted removal window saying the feature is new, followed by a Send Feedback link.")

    static let sendFeedback = NSLocalizedString("pir.assisted.send-feedback", bundle: .module,
                                                 value: "Send Feedback",
                                                 comment: "Inline link after the assisted removal footer note. Opens the feedback form in the browser.")

    static func removingFrom(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.removing-from", bundle: .module,
                                      value: "Removing you from %@",
                                      comment: "Window and panel title. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static func submittedTo(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.submitted-to", bundle: .module,
                                      value: "Request submitted to %@",
                                      comment: "Completed panel title. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static func readySubtitle(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.ready.subtitle", bundle: .module,
                                      value: "When you're ready, we'll fill in %@'s opt-out form. We'll pause whenever we need your help.",
                                      comment: "Intro panel detail. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static let submittedSubtitle = NSLocalizedString("pir.assisted.submitted.subtitle", bundle: .module,
                                                 value: "Nice work. That's the hard part done.",
                                                 comment: "Panel detail after submitting a removal request.")

    static func userSubtitle(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.user.subtitle", bundle: .module,
                                      value: "We've paused. %@ needs a person for this step.",
                                      comment: "Panel detail when user input is needed. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static func openingBroker(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.opening", bundle: .module,
                                      value: "Opening %@…",
                                      comment: "Status while opening a broker form. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static let fillingDetails = NSLocalizedString("pir.assisted.filling", bundle: .module,
                                                 value: "Filling in your details.",
                                                 comment: "Panel detail while DuckDuckGo fills the form.")

    static let whatHappensNext = NSLocalizedString("pir.assisted.next.title", bundle: .module,
                                                 value: "What happens next",
                                                 comment: "Heading after submitting a removal request.")

    static let followUp = NSLocalizedString("pir.assisted.next.detail", bundle: .module,
                                                 value: "We'll follow up on the request and check your info is gone on our next scan.",
                                                 comment: "Explains follow-up after submitting a removal request.")

    static let cancel = NSLocalizedString("pir.assisted.cancel", bundle: .module,
                                                 value: "Cancel",
                                                 comment: "Cancels the removal before it begins.")

    static let backToDashboard = NSLocalizedString("pir.assisted.back", bundle: .module,
                                                 value: "Back to dashboard",
                                                 comment: "Closes the completed removal window and returns to the dashboard.")

    static let stop = NSLocalizedString("pir.assisted.stop", bundle: .module,
                                                 value: "Stop",
                                                 comment: "Stops the current removal attempt.")

    static func stopConfirmationTitle(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.stop-confirmation.title", bundle: .module,
                                      value: "Stop removing you from %@?",
                                      comment: "Title of the confirmation shown when closing an unfinished removal window. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static let stopConfirmationDetail = NSLocalizedString("pir.assisted.stop-confirmation.detail", bundle: .module,
                                                 value: "Closing this window stops the request. You can start it again from the dashboard.",
                                                 comment: "Explains what closing an unfinished removal window does.")

    static let keepGoing = NSLocalizedString("pir.assisted.keep-going", bundle: .module,
                                                 value: "Keep Going",
                                                 comment: "Dismisses the stop confirmation and continues the removal.")

    static let yourTurn = NSLocalizedString("pir.assisted.user.title", bundle: .module,
                                                 value: "Your turn",
                                                 comment: "Heading above instructions for the current user step.")

    static func userInstruction(_ stepTitle: String) -> String {
        let format = NSLocalizedString("pir.assisted.user.instruction", bundle: .module,
                                      value: "Complete this step on the page: %@. We will carry on when it is done.",
                                      comment: "User-turn instructions. %@ is the current step label supplied by the data broker configuration.")
        return String(format: format, stepTitle)
    }

    static let userInstructionFallback = NSLocalizedString("pir.assisted.user.instruction-fallback", bundle: .module,
                                                 value: "Complete the highlighted part of the page. We will carry on when it is done.",
                                                 comment: "User-turn instructions when the broker does not supply a current step label.")

    static func readyToRemove(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.intro.title", bundle: .module,
                                      value: "Ready to remove you from %@",
                                      comment: "Intro heading. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static let introDescription = NSLocalizedString("pir.assisted.intro.detail", bundle: .module,
                                                 value: "We'll open their opt-out form here and fill it in for you.",
                                                 comment: "Explains assisted removal before the user starts.")

    static let startRequest = NSLocalizedString("pir.assisted.intro.start", bundle: .module,
                                                 value: "Start request",
                                                 comment: "Starts an assisted removal attempt.")

    static let stopAnytime = NSLocalizedString("pir.assisted.intro.stop-anytime", bundle: .module,
                                                 value: "You can stop anytime",
                                                 comment: "Explains that the user can cancel an assisted removal.")

    static let whereHelpNeeded = NSLocalizedString("pir.assisted.intro.help-title", bundle: .module,
                                                 value: "Where we need your help",
                                                 comment: "Heading above examples of steps that may need user input.")

    static let proveHuman = NSLocalizedString("pir.assisted.intro.human-title", bundle: .module,
                                                 value: "Prove you're human",
                                                 comment: "Example of a removal step that may need the user.")

    static func proveHumanDetail(_ brokerName: String) -> String {
        let format = NSLocalizedString("pir.assisted.intro.human-detail", bundle: .module,
                                      value: "%@ may ask you to prove you're human. We'll pause and show you where.",
                                      comment: "Explains possible human verification. %@ is the data broker name.")
        return String(format: format, brokerName)
    }

    static let reviewAndSubmit = NSLocalizedString("pir.assisted.intro.review-title", bundle: .module,
                                                 value: "Review and submit",
                                                 comment: "Example of a removal step that may need the user.")

    static let reviewDetail = NSLocalizedString("pir.assisted.intro.review-detail", bundle: .module,
                                                 value: "If the form needs your review or confirmation, we'll pause so you can complete that step.",
                                                 comment: "Explains that form review depends on the broker workflow.")

    static let completedStep = NSLocalizedString("pir.assisted.step.completed", bundle: .module,
                                                 value: "Completed",
                                                 comment: "Accessibility status for a completed removal step.")

    static let runningStep = NSLocalizedString("pir.assisted.step.running", bundle: .module,
                                                 value: "In progress",
                                                 comment: "Accessibility status for the current automated removal step.")

    static let upcomingStep = NSLocalizedString("pir.assisted.step.upcoming", bundle: .module,
                                                 value: "Upcoming",
                                                 comment: "Accessibility status for a future removal step.")

    static func pageAddress(_ address: String) -> String {
        let format = NSLocalizedString("pir.assisted.address", bundle: .module,
                                      value: "Page address: %@",
                                      comment: "Accessibility label for the read-only page address. %@ is the current URL.")
        return String(format: format, address)
    }
}
