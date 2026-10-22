//
//  BrowserToolFormModelTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BrowserToolFormModelTests: XCTestCase {

    typealias Labels = BrowserToolRawPage.Labels
    typealias Field = BrowserToolRawPage.Field
    typealias Button = BrowserToolRawPage.Button

    // MARK: - Labels

    func testWhenEverySourceIsPresentThenTheLabelForWins() {
        let labels = Labels(labelFor: "Full name", wrapping: "Name", ariaLabel: "Your name", ariaLabelledBy: "Name heading",
                            placeholder: "Jane Doe", nearby: "Name text", legend: "You", title: "Name title")

        XCTAssertEqual(BrowserToolForms.label(for: labels, name: "fullName"), "Full name")
    }

    /// The model fills by label, so each source is a fallback for the ones before it, in the spec's order.
    func testWhenEarlierSourcesAreEmptyThenEachLaterSourceIsUsedInOrder() {
        var labels = Labels(wrapping: "Wrapping", ariaLabel: "Aria", ariaLabelledBy: "Labelled by",
                            placeholder: "Placeholder", nearby: "Nearby", legend: "Legend", title: "Title")
        var resolved: [String] = []
        for _ in 0..<7 {
            let label = BrowserToolForms.label(for: labels, name: "name")
            resolved.append(label)
            switch label {
            case "Wrapping": labels.wrapping = ""
            case "Aria": labels.ariaLabel = ""
            case "Labelled by": labels.ariaLabelledBy = ""
            case "Placeholder": labels.placeholder = ""
            case "Nearby": labels.nearby = ""
            case "Legend": labels.legend = ""
            default: labels.title = ""
            }
        }

        XCTAssertEqual(resolved, ["Wrapping", "Aria", "Labelled by", "Placeholder", "Nearby", "Legend", "Title"])
        XCTAssertEqual(BrowserToolForms.label(for: labels, name: "name"), "name")
    }

    func testWhenALabelHasExtraWhitespaceThenItIsCollapsed() {
        let labels = Labels(labelFor: "  Moving \n from   (city or ZIP) ")

        XCTAssertEqual(BrowserToolForms.label(for: labels, name: "from"), "Moving from (city or ZIP)")
    }

    func testWhenSourcesAreOnlyWhitespaceThenTheNameIsUsed() {
        XCTAssertEqual(BrowserToolForms.label(for: Labels(labelFor: "   ", placeholder: "\n"), name: "zip"), "zip")
    }

    // MARK: - Radio groups

    func testWhenRadiosShareANameThenTheyBecomeOneFieldNamedAfterTheGroup() throws {
        let page = self.page(fields: [
            radio("e1", name: "ownership", value: "own", label: "I own", group: "Do you own or rent?"),
            radio("e2", name: "ownership", value: "rent", label: "I rent", group: "Do you own or rent?", checked: true)
        ])

        let fields = BrowserToolForms.fields(in: page)

        XCTAssertEqual(fields.count, 1)
        let group = try XCTUnwrap(fields.first)
        XCTAssertEqual(group.ref, "e1")
        XCTAssertEqual(group.type, "radio")
        XCTAssertEqual(group.label, "Do you own or rent?")
        XCTAssertEqual(group.options, [.init(value: "own", label: "I own"), .init(value: "rent", label: "I rent")])
        XCTAssertEqual(group.value, "rent")
        XCTAssertEqual(group.radioRefs, ["own": "e1", "rent": "e2"])
    }

    func testWhenNoRadioIsCheckedThenTheGroupHasNoValue() {
        let fields = BrowserToolForms.fields(in: page(fields: [radio("e1", name: "shade", value: "none", label: "None")]))

        XCTAssertNil(fields.first?.value)
    }

    func testWhenRadiosShareANameInDifferentFormsThenTheyAreSeparateGroups() {
        let fields = BrowserToolForms.fields(in: page(fields: [
            radio("e1", form: "f1", name: "choice", value: "a", label: "A"),
            radio("e2", form: "f2", name: "choice", value: "b", label: "B")
        ]))

        XCTAssertEqual(fields.map(\.ref), ["e1", "e2"])
    }

    func testWhenAGroupHasNoAriaOrNearbyTextThenTheLegendThenTheNameLabelIt() {
        let legendOnly = radio("e1", name: "size", value: "s", label: "Small", groupLabels: .init(legend: "Pick a size"))
        let nothing = radio("e2", name: "colour", value: "red", label: "Red", groupLabels: .init())
        let aria = radio("e3", name: "speed", value: "fast", label: "Fast", groupLabels: .init(ariaGroup: "Delivery speed", nearby: "Speed", legend: "Options"))

        let labels = BrowserToolForms.fields(in: page(fields: [legendOnly, nothing, aria])).map(\.label)

        XCTAssertEqual(labels, ["Pick a size", "colour", "Delivery speed"])
    }

    func testWhenEveryRadioInAGroupIsHiddenThenTheGroupIsHiddenAndRestricted() {
        let fields = BrowserToolForms.fields(in: page(fields: [
            radio("e1", name: "shade", value: "none", label: "None", visible: false),
            radio("e2", name: "shade", value: "some", label: "Some", visible: false)
        ]))

        XCTAssertEqual(fields.first?.visible, false)
        XCTAssertEqual(fields.first?.restricted, true)
    }

    // MARK: - Submit buttons

    func testWhenAButtonSubmitsByTypeThenItIsASubmit() {
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b1", formRef: "f1", tag: "button", typeAttribute: "submit", text: "See my savings")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b2", formRef: "f1", tag: "button", typeAttribute: nil, inForm: true, text: "Go")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b3", formRef: "f1", tag: "input", typeAttribute: "submit", text: "Go")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b4", formRef: "f1", tag: "input", typeAttribute: "image", text: "")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b5", formRef: "f1", tag: "button", typeAttribute: "bogus", inForm: true, text: "Go")))
    }

    func testWhenAButtonOnlyMovesBetweenStepsThenItIsNotASubmit() {
        XCTAssertFalse(BrowserToolForms.isSubmit(Button(ref: "b1", formRef: "f1", tag: "button", typeAttribute: "button", text: "Next")))
        XCTAssertFalse(BrowserToolForms.isSubmit(Button(ref: "b2", formRef: "f1", tag: "button", typeAttribute: "button", text: "Back")))
        XCTAssertFalse(BrowserToolForms.isSubmit(Button(ref: "b3", formRef: "f1", tag: "button", typeAttribute: "reset", text: "Clear")))
        XCTAssertFalse(BrowserToolForms.isSubmit(Button(ref: "b4", formRef: "f1", tag: "div", typeAttribute: nil, inForm: false, text: "Show more")))
    }

    /// Outside a form a typeless button submits nothing by itself.
    func testWhenATypelessButtonIsOutsideAFormThenOnlyItsTextDecides() {
        XCTAssertFalse(BrowserToolForms.isSubmit(Button(ref: "b1", formRef: "f9", tag: "button", typeAttribute: nil, inForm: false, text: "Continue")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b2", formRef: "f9", tag: "button", typeAttribute: nil, inForm: false, text: "Get my quote")))
    }

    /// A script-driven "Get my quote" must not be clickable without the user's approval.
    func testWhenANonSubmitButtonReadsLikeASubmitThenItCountsAsOne() {
        for text in ["Get my quote", "Send", "Request a callback", "Book now", "Confirm", "Place order", "Pay", "Sign up", "Submit request"] {
            XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b1", formRef: "f1", tag: "button", typeAttribute: "button", text: text)), text)
        }
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b2", formRef: "f1", tag: "div", typeAttribute: nil, inForm: true, text: "Send it")))
        XCTAssertTrue(BrowserToolForms.isSubmit(Button(ref: "b3", formRef: "f1", tag: "input", typeAttribute: "button", text: "Request quote")))
    }

    // MARK: - Restricted fields

    func testWhenAFieldHoldsSecretsOrCannotBeSeenThenItIsRestricted() {
        let restricted = [
            Field(ref: "e1", formRef: "f1", type: "password"),
            Field(ref: "e2", formRef: "f1", type: "file"),
            Field(ref: "e3", formRef: "f1", type: "hidden"),
            Field(ref: "e4", formRef: "f1", type: "text", visible: false),
            Field(ref: "e5", formRef: "f1", type: "text", autocomplete: "cc-number"),
            Field(ref: "e6", formRef: "f1", type: "text", autocomplete: "shipping cc-exp"),
            Field(ref: "e7", formRef: "f1", type: "text", autocomplete: "current-password"),
            Field(ref: "e8", formRef: "f1", type: "text", autocomplete: "section-blue new-password")
        ]

        for field in restricted {
            XCTAssertTrue(BrowserToolForms.isRestricted(field), field.ref)
        }
    }

    func testWhenAFieldIsAnOrdinaryVisibleInputThenItIsNotRestricted() {
        XCTAssertFalse(BrowserToolForms.isRestricted(Field(ref: "e1", formRef: "f1", type: "email", autocomplete: "email")))
        XCTAssertFalse(BrowserToolForms.isRestricted(Field(ref: "e2", formRef: "f1", tag: "select", type: "select")))
        XCTAssertFalse(BrowserToolForms.isRestricted(Field(ref: "e3", formRef: "f1", type: "tel", autocomplete: "tel")))
    }

    // MARK: - Restricted pages

    func testWhenAFormIsMostlyAPasswordThenThePageIsASignInPage() {
        let page = self.page(fields: [
            Field(ref: "e1", formRef: "f1", type: "email"),
            Field(ref: "e2", formRef: "f1", type: "password"),
            Field(ref: "e3", formRef: "f1", type: "checkbox")
        ])

        XCTAssertTrue(BrowserToolForms.isRestrictedPage(page))
    }

    func testWhenAPasswordFormHasASignInButtonThenThePageIsRestrictedHoweverManyFieldsItHas() {
        let fields = (1...5).map { Field(ref: "e\($0)", formRef: "f1", type: "text") } + [Field(ref: "e9", formRef: "f1", type: "password")]
        let page = self.page(fields: fields, buttons: [Button(ref: "b1", formRef: "f1", typeAttribute: "submit", text: "Log in")])

        XCTAssertTrue(BrowserToolForms.isRestrictedPage(page))
    }

    func testWhenThePageAsksForCardDetailsThenItIsRestricted() {
        XCTAssertTrue(BrowserToolForms.isRestrictedPage(page(fields: [Field(ref: "e1", formRef: "f1", autocomplete: "cc-number")])))
        XCTAssertTrue(BrowserToolForms.isRestrictedPage(page(fields: [Field(ref: "e1", formRef: "f1", name: "cardNumber")])))
        XCTAssertTrue(BrowserToolForms.isRestrictedPage(page(fields: [Field(ref: "e1", formRef: "f1", name: "cvv")])))
    }

    /// The cleaning quote offers an optional account password among many other fields.
    func testWhenAQuoteFormHasAnOptionalPasswordThenThePageIsNotRestricted() {
        let fields = ["name", "email", "phone", "zip", "date", "bedrooms", "bathrooms"].enumerated().map {
            Field(ref: "e\($0.offset)", formRef: "f1", name: $0.element)
        } + [Field(ref: "e20", formRef: "f1", type: "password", autocomplete: "new-password")]
        let page = self.page(fields: fields, buttons: [Button(ref: "b1", formRef: "f1", typeAttribute: "submit", text: "Get my price")])

        XCTAssertFalse(BrowserToolForms.isRestrictedPage(page))
    }

    func testWhenAPasswordFieldIsHiddenThenItDoesNotMakeThePageRestricted() {
        let page = self.page(fields: [Field(ref: "e1", formRef: "f1", type: "email"), Field(ref: "e2", formRef: "f1", type: "password", visible: false)])

        XCTAssertFalse(BrowserToolForms.isRestrictedPage(page))
    }

    // MARK: - Snapshot

    func testWhenSnapshottedThenOnlyVisibleEnabledFieldsAndButtonsAreListed() throws {
        let page = self.page(fields: [
            Field(ref: "e1", formRef: "f1", labels: Labels(labelFor: "Street"), value: "1 Main St"),
            Field(ref: "e2", formRef: "f1", visible: false, labels: Labels(labelFor: "Later step")),
            Field(ref: "e3", formRef: "f1", disabled: true, labels: Labels(labelFor: "Locked"))
        ], buttons: [
            Button(ref: "b1", formRef: "f1", typeAttribute: "button", text: "Next"),
            Button(ref: "b2", formRef: "f1", typeAttribute: "submit", text: "Send", visible: false)
        ])

        let snapshot = BrowserToolForms.snapshot(of: page, tabID: "tab-1")

        XCTAssertEqual(snapshot, [
            "tabId": "tab-1",
            "url": "https://quotes.example/movers",
            "title": "Get a quote | Example Movers",
            "forms": [[
                "ref": "f1",
                "name": "quote",
                "fields": [["ref": "e1", "label": "Street", "type": "text", "required": false, "value": "1 Main St"]],
                "buttons": [["ref": "b1", "text": "Next", "isSubmit": false]]
            ]],
            "messages": []
        ])
    }

    func testWhenAFieldIsRestrictedThenItIsListedWithoutItsValue() throws {
        let page = self.page(fields: [
            Field(ref: "e1", formRef: "f1", type: "password", labels: Labels(labelFor: "Password"), value: "should never be here"),
            Field(ref: "e2", formRef: "f1", type: "text", autocomplete: "cc-number", labels: Labels(labelFor: "Card"), value: "4111")
        ])

        let fields = try XCTUnwrap(BrowserToolForms.snapshot(of: page, tabID: "t")["forms"]?.arrayValue?.first?["fields"]?.arrayValue)

        XCTAssertEqual(fields, [
            ["ref": "e1", "label": "Password", "type": "password", "required": false],
            ["ref": "e2", "label": "Card", "type": "text", "required": false]
        ])
    }

    func testWhenFieldsHaveOptionsStatesAndErrorsThenTheyAreListed() throws {
        let page = self.page(fields: [
            Field(ref: "e1", formRef: "f1", tag: "select", type: "select", required: true, labels: Labels(labelFor: "Home size"),
                  value: "", options: [.init(value: "", label: "Choose…"), .init(value: "2br", label: "2 bedrooms")]),
            Field(ref: "e2", formRef: "f1", type: "checkbox", labels: Labels(labelFor: "Packing"), value: "on", checked: false),
            Field(ref: "e3", formRef: "f1", type: "tel", labels: Labels(labelFor: "Phone"), error: "Enter a 10-digit US phone number.", value: "12"),
            radio("e4", name: "ownership", value: "own", label: "I own", group: "Do you own or rent?")
        ])

        let fields = try XCTUnwrap(BrowserToolForms.snapshot(of: page, tabID: "t")["forms"]?.arrayValue?.first?["fields"]?.arrayValue)

        XCTAssertEqual(fields, [
            ["ref": "e1", "label": "Home size", "type": "select", "required": true,
             "options": [["value": "", "label": "Choose…"], ["value": "2br", "label": "2 bedrooms"]]],
            ["ref": "e2", "label": "Packing", "type": "checkbox", "required": false, "value": "false"],
            ["ref": "e3", "label": "Phone", "type": "tel", "required": false, "value": "12", "error": "Enter a 10-digit US phone number."],
            ["ref": "e4", "label": "Do you own or rent?", "type": "radio", "required": false, "options": [["value": "own", "label": "I own"]]]
        ])
    }

    func testWhenThePageHasMoreThanTheCapThenFieldsAndButtonsAreCut() throws {
        let fields = (1...200).map { Field(ref: "e\($0)", formRef: "f1") }
        let buttons = (1...40).map { Button(ref: "b\($0)", formRef: "f1", typeAttribute: "button", text: "Option \($0)") }

        let form = try XCTUnwrap(BrowserToolForms.snapshot(of: page(fields: fields, buttons: buttons), tabID: "t")["forms"]?.arrayValue?.first)

        XCTAssertEqual(form["fields"]?.arrayValue?.count, BrowserToolForms.maxFields)
        XCTAssertEqual(form["buttons"]?.arrayValue?.count, BrowserToolForms.maxButtons)
    }

    func testWhenAFormHasNothingVisibleThenItIsLeftOutAndMessagesAreListed() throws {
        var page = self.page(fields: [Field(ref: "e1", formRef: "f1", visible: false)])
        page.messages = [.init(text: "Thanks! Your quote request was received.", isAlert: false)]

        let snapshot = BrowserToolForms.snapshot(of: page, tabID: "t")

        XCTAssertEqual(snapshot["forms"], [])
        XCTAssertEqual(snapshot["messages"], ["Thanks! Your quote request was received."])
    }

    // MARK: - Filling

    func testWhenFillingThenEachFieldKindGetsItsOwnAction() {
        let fields = BrowserToolForms.fields(in: quotePage())

        let plan = BrowserToolForms.fillPlan(for: [
            ("e1", "Pat Doe"),
            ("e2", "2br"),
            ("e3", "true"),
            ("e5", "I rent")
        ], fields: fields)

        XCTAssertEqual(plan.steps.map(\.action), [
            .text(ref: "e1", value: "Pat Doe"),
            .select(ref: "e2", value: "2br"),
            .check(ref: "e3", checked: true),
            .check(ref: "e6", checked: true)
        ])
        XCTAssertEqual(plan.steps.map(\.fieldRef), ["e1", "e2", "e3", "e5"])
        XCTAssertTrue(plan.failed.isEmpty)
    }

    func testWhenAnOptionIsGivenByLabelThenCaseIsIgnored() {
        let fields = BrowserToolForms.fields(in: quotePage())

        let plan = BrowserToolForms.fillPlan(for: [("e2", "2 BEDROOMS"), ("e5", "own")], fields: fields)

        XCTAssertEqual(plan.steps.map(\.action), [.select(ref: "e2", value: "2br"), .check(ref: "e5", checked: true)])
    }

    func testWhenAFieldCannotBeFilledThenItFailsWithItsReasonAndTheRestStillFill() {
        let fields = BrowserToolForms.fields(in: quotePage())

        let plan = BrowserToolForms.fillPlan(for: [
            ("e2", "castle"),
            ("e3", "yes"),
            ("e7", "hunter2"),
            ("e8", "x"),
            ("e9", "x"),
            ("e99", "x"),
            ("e1", "Pat Doe")
        ], fields: fields)

        XCTAssertEqual(plan.failed.map { $0.ref }, ["e2", "e3", "e7", "e8", "e9", "e99"])
        XCTAssertEqual(plan.failed.map { $0.error }, ["invalid_option", "invalid_option", "restricted", "restricted", "disabled", "not_found"])
        XCTAssertEqual(plan.steps.map(\.action), [.text(ref: "e1", value: "Pat Doe")])
    }

    // MARK: - Preview

    func testWhenPreviewingThenValuesAreShownAsTheUserWouldReadThem() throws {
        var page = quotePage()
        page.fields[0].value = "Pat Doe"
        page.fields[1].value = "2br"
        page.fields[2].checked = true
        page.fields[4].checked = true
        page.fields[6].value = "hunter2"

        let preview = try XCTUnwrap(BrowserToolForms.preview(of: "f1", in: page))

        XCTAssertEqual(preview.site, "Example Movers")
        XCTAssertEqual(preview.url, "https://quotes.example/movers")
        XCTAssertEqual(preview.formName, "quote")
        XCTAssertEqual(preview.fields.map { $0.label }, ["Full name", "Home size", "Packing", "Do you own or rent?"])
        XCTAssertEqual(preview.fields.map { $0.value }, ["Pat Doe", "2 bedrooms", "Yes", "I own"])
    }

    func testWhenAFieldIsEmptyHiddenOrSecretThenThePreviewLeavesItOut() throws {
        let page = self.page(fields: [
            Field(ref: "e1", formRef: "f1", labels: Labels(labelFor: "Name"), value: ""),
            Field(ref: "e2", formRef: "f1", visible: false, labels: Labels(labelFor: "Hidden"), value: "x"),
            Field(ref: "e3", formRef: "f1", type: "password", labels: Labels(labelFor: "Password"), value: "x"),
            Field(ref: "e4", formRef: "f1", type: "checkbox", labels: Labels(labelFor: "Newsletter"), checked: false)
        ])

        let preview = try XCTUnwrap(BrowserToolForms.preview(of: "f1", in: page))

        XCTAssertEqual(preview.fields.map { $0.label }, ["Newsletter"])
        XCTAssertEqual(preview.fields.map { $0.value }, ["No"])
    }

    func testWhenTheFormIsUnknownThenThereIsNoPreview() {
        XCTAssertNil(BrowserToolForms.preview(of: "f42", in: quotePage()))
    }

    func testWhenPreviewedThenItEncodesTheContractShape() throws {
        let preview = BrowserToolFormPreview(site: "Example Movers", url: "https://quotes.example", formName: nil, fields: [("Name", "Pat")])

        XCTAssertEqual(preview.jsonValue, ["site": "Example Movers", "url": "https://quotes.example", "fields": [["label": "Name", "value": "Pat"]]])
    }

    func testSiteNameComesFromSiteNameThenTheTitleThenTheHost() {
        func site(_ siteName: String?, _ title: String, _ url: String) -> String {
            BrowserToolForms.siteName(of: BrowserToolRawPage(url: url, title: title, siteName: siteName))
        }

        XCTAssertEqual(site("Acme Movers", "Quote | Something else", "https://acme.example"), "Acme Movers")
        XCTAssertEqual(site(nil, "Free Moving Quote | Bluebird Movers", "https://test.duck.co/quotes/movers.html"), "Bluebird Movers")
        XCTAssertEqual(site(nil, "Sunpeak Solar - Your solar quote", "https://www.sunpeaksolar.com/quote"), "Sunpeak Solar")
        XCTAssertEqual(site(nil, "Quote form", "https://www.tidynest.com/quote"), "tidynest.com")
        XCTAssertEqual(site("  ", "Book a Cleaning Quote · Tidy Nest", "https://x.example"), "Tidy Nest")
    }

    // MARK: - Submit outcome

    func testWhenTheSubmitNavigatedOrTheFormWentAwayThenItWasSubmitted() {
        let before = quotePage()
        var replaced = BrowserToolRawPage(url: before.url, title: "Quote request received | Example Movers")
        replaced.messages = [.init(text: "Thanks! Your quote request was received.", isAlert: false)]

        XCTAssertTrue(BrowserToolForms.submitOutcome(navigated: true, formRef: "f1", before: before, after: nil).submitted)
        XCTAssertTrue(BrowserToolForms.submitOutcome(navigated: false, formRef: "f1", before: before, after: replaced).submitted)
    }

    func testWhenTheFormShowsErrorsAfterSubmittingThenItWasNotSubmittedAndTheErrorsAreReturned() {
        var after = quotePage()
        after.fields[0].error = "This field is required."
        after.messages = [.init(text: "Please fix the errors below.", isAlert: true)]

        let outcome = BrowserToolForms.submitOutcome(navigated: false, formRef: "f1", before: quotePage(), after: after)

        XCTAssertFalse(outcome.submitted)
        XCTAssertEqual(outcome.errors, [.init(ref: "e1", message: "This field is required."), .init(ref: nil, message: "Please fix the errors below.")])
    }

    /// Saying a quote was requested when it was not would mislead the user.
    func testWhenNothingVisiblyChangedThenItWasNotSubmitted() {
        let outcome = BrowserToolForms.submitOutcome(navigated: false, formRef: "f1", before: quotePage(), after: quotePage())

        XCTAssertFalse(outcome.submitted)
        XCTAssertTrue(outcome.errors.isEmpty)
    }

    func testWhenANewStatusMessageAppearsBesideTheFormThenItWasSubmitted() {
        var after = quotePage()
        after.messages = [.init(text: "Request sent.", isAlert: false)]

        XCTAssertTrue(BrowserToolForms.submitOutcome(navigated: false, formRef: "f1", before: quotePage(), after: after).submitted)
    }

    func testConfirmationTextPrefersStatusMessagesThenTheMainTextAndIsCapped() {
        var withStatus = BrowserToolRawPage(url: "https://x.example", mainText: "Main")
        withStatus.messages = [.init(text: "Thanks!", isAlert: false), .init(text: "Reference BBM-1234.", isAlert: false)]
        let long = BrowserToolRawPage(url: "https://x.example", mainText: String(repeating: "a", count: 5000))

        XCTAssertEqual(BrowserToolForms.confirmationText(of: withStatus), "Thanks!\nReference BBM-1234.")
        XCTAssertEqual(BrowserToolForms.confirmationText(of: long).count, BrowserToolForms.maxConfirmationLength)
        XCTAssertEqual(BrowserToolForms.confirmationText(of: nil), "")
    }

    // MARK: -

    private func page(fields: [Field] = [], buttons: [Button] = []) -> BrowserToolRawPage {
        BrowserToolRawPage(url: "https://quotes.example/movers",
                           title: "Get a quote | Example Movers",
                           forms: [.init(ref: "f1", name: "quote"), .init(ref: "f2"), .init(ref: "f9", isPage: true)],
                           fields: fields,
                           buttons: buttons)
    }

    /// e1 name, e2 home size, e3 packing, e4 notes, e5/e6 a radio group, e7 password, e8 hidden, e9 disabled.
    private func quotePage() -> BrowserToolRawPage {
        page(fields: [
            Field(ref: "e1", formRef: "f1", labels: Labels(labelFor: "Full name"), value: ""),
            Field(ref: "e2", formRef: "f1", tag: "select", type: "select", labels: Labels(labelFor: "Home size"), value: "",
                  options: [.init(value: "", label: "Choose…"), .init(value: "2br", label: "2 bedrooms")]),
            Field(ref: "e3", formRef: "f1", type: "checkbox", labels: Labels(labelFor: "Packing"), value: "on", checked: false),
            Field(ref: "e4", formRef: "f1", tag: "textarea", type: "textarea", labels: Labels(labelFor: "Notes"), value: ""),
            radio("e5", name: "ownership", value: "own", label: "I own", group: "Do you own or rent?"),
            radio("e6", name: "ownership", value: "rent", label: "I rent", group: "Do you own or rent?"),
            Field(ref: "e7", formRef: "f1", type: "password", autocomplete: "new-password", labels: Labels(labelFor: "Password")),
            Field(ref: "e8", formRef: "f1", visible: false, labels: Labels(labelFor: "Later")),
            Field(ref: "e9", formRef: "f1", disabled: true, labels: Labels(labelFor: "Locked"))
        ], buttons: [Button(ref: "b1", formRef: "f1", typeAttribute: "submit", text: "Get my quote")])
    }

    private func radio(_ ref: String,
                       form: String = "f1",
                       name: String,
                       value: String,
                       label: String,
                       group: String = "",
                       groupLabels: BrowserToolRawPage.GroupLabels? = nil,
                       checked: Bool = false,
                       visible: Bool = true) -> Field {
        Field(ref: ref, formRef: form, type: "radio", name: name, visible: visible, labels: Labels(wrapping: label),
              value: value, checked: checked, groupLabels: groupLabels ?? .init(nearby: group))
    }
}
