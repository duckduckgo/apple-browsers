//
//  BrowserToolFormModel.swift
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
import Foundation

/// What `BrowserToolForms.js` reads from a page. Raw on purpose: every decision about it is made
/// in `BrowserToolForms`, where it can be tested without a web view.
struct BrowserToolRawPage: Decodable, Equatable {

    struct Form: Decodable, Equatable {
        var ref: String
        var name: String = ""
        var visible: Bool = true
        /// Stands for the controls outside any `<form>`.
        var isPage: Bool = false
    }

    struct Labels: Decodable, Equatable {
        var labelFor: String = ""
        var wrapping: String = ""
        var ariaLabel: String = ""
        var ariaLabelledBy: String = ""
        var placeholder: String = ""
        var nearby: String = ""
        var legend: String = ""
        var title: String = ""
    }

    struct GroupLabels: Decodable, Equatable {
        var ariaGroup: String = ""
        var nearby: String = ""
        var legend: String = ""
    }

    struct Option: Codable, Equatable {
        var value: String
        var label: String
    }

    struct Field: Decodable, Equatable {
        var ref: String
        var formRef: String
        var tag: String = "input"
        var type: String = "text"
        var name: String = ""
        var autocomplete: String = ""
        var required: Bool = false
        var disabled: Bool = false
        var visible: Bool = true
        var labels = Labels()
        var error: String = ""
        /// Absent for password, file and card fields: the page never sends those values.
        var value: String?
        var checked: Bool?
        var options: [Option]?
        var groupLabels: GroupLabels?
        var readOnly: Bool = false
        /// DuckDuckGo Autofill's classification of the field, e.g. `creditCards.cardNumber`.
        var ddgInputType: String = ""
    }

    struct Button: Decodable, Equatable {
        var ref: String
        var formRef: String
        var tag: String = "button"
        /// Nil when the attribute is absent, which for a `<button>` in a form means submit.
        var typeAttribute: String?
        var inForm: Bool = true
        var text: String = ""
        var visible: Bool = true
        var disabled: Bool = false
    }

    struct Message: Decodable, Equatable {
        var text: String
        var isAlert: Bool = false
    }

    var url: String
    var title: String = ""
    var siteName: String?
    var forms: [Form] = []
    var fields: [Field] = []
    var buttons: [Button] = []
    var messages: [Message] = []
    var mainText: String = ""

    init(url: String, title: String = "", siteName: String? = nil, forms: [Form] = [], fields: [Field] = [],
         buttons: [Button] = [], messages: [Message] = [], mainText: String = "") {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.forms = forms
        self.fields = fields
        self.buttons = buttons
        self.messages = messages
        self.mainText = mainText
    }

    init?(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
              let page = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = page
    }
}

/// One field as the model sees it: a radio group is one field, and its label is resolved.
struct BrowserToolFormField: Equatable {
    var ref: String
    var formRef: String
    var label: String
    var type: String
    var required: Bool
    var disabled: Bool
    var visible: Bool
    /// Never filled, and its value is never shown.
    var restricted: Bool
    var value: String?
    var options: [BrowserToolRawPage.Option]?
    /// For a radio group: the ref of the radio behind each option value.
    var radioRefs: [String: String] = [:]
    var error: String?
    var autocomplete: String = ""
    var readOnly: Bool = false
    /// Card data. Only the user fills it, and its value is never read.
    var payment: Bool = false
}

struct BrowserToolFormError: Equatable {
    var ref: String?
    var message: String

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = ["message": .string(message)]
        if let ref { object["ref"] = .string(ref) }
        return .object(object)
    }
}

enum BrowserToolFillAction: Equatable {
    case text(ref: String, value: String)
    case select(ref: String, value: String)
    case check(ref: String, checked: Bool)

    var ref: String {
        switch self {
        case .text(let ref, _), .select(let ref, _), .check(let ref, _): ref
        }
    }

    /// The shape `BrowserToolForms.js` takes.
    var bridgeValue: [String: Any] {
        switch self {
        case .text(let ref, let value): ["ref": ref, "kind": "text", "value": value]
        case .select(let ref, let value): ["ref": ref, "kind": "select", "value": value]
        case .check(let ref, let checked): ["ref": ref, "kind": "check", "checked": checked]
        }
    }
}

struct BrowserToolFillReadback: Decodable, Equatable {
    var ref: String
    var found: Bool
    var value: String?
    var checked: Bool?
}

struct BrowserToolFillPlan: Equatable {
    struct Step: Equatable {
        /// The ref the model used. For a radio group that is the group, while the action clicks one radio.
        var fieldRef: String
        var fieldType: String
        var action: BrowserToolFillAction
    }

    var steps: [Step] = []
    var failed: [(ref: String, error: String)] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.steps == rhs.steps && lhs.failed.map { "\($0.ref)|\($0.error)" } == rhs.failed.map { "\($0.ref)|\($0.error)" }
    }
}

struct BrowserToolFormPreview: Equatable {
    var site: String
    var url: String
    var formName: String?
    var fields: [(label: String, value: String)]

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "site": .string(site),
            "url": .string(url),
            "fields": .array(fields.map { ["label": .string($0.label), "value": .string($0.value)] })
        ]
        if let formName { object["formName"] = .string(formName) }
        return .object(object)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.site == rhs.site && lhs.url == rhs.url && lhs.formName == rhs.formName
            && lhs.fields.map { [$0.label, $0.value] } == rhs.fields.map { [$0.label, $0.value] }
    }
}

/// The rules behind the form tools. Kept apart from the page script so each one is unit tested.
enum BrowserToolForms {

    static let maxFields = 150
    static let maxButtons = 30
    static let maxConfirmationLength = 2000

    // MARK: - Labels

    /// The model fills by label, so the most specific source wins: `<label for>`, a wrapping
    /// label, ARIA, the placeholder, then text near the field. The name is the last resort.
    static func label(for labels: BrowserToolRawPage.Labels, name: String) -> String {
        let candidates = [labels.labelFor, labels.wrapping, labels.ariaLabel, labels.ariaLabelledBy,
                          labels.placeholder, labels.nearby, labels.legend, labels.title]
        return candidates.lazy.map(collapsed).first { !$0.isEmpty } ?? name
    }

    static func groupLabel(for labels: BrowserToolRawPage.GroupLabels?, name: String) -> String {
        guard let labels else { return name }
        return [labels.ariaGroup, labels.nearby, labels.legend].lazy.map(collapsed).first { !$0.isEmpty } ?? name
    }

    // MARK: - Fields

    /// Every field in document order, with each radio group folded into one field named after the
    /// group and offering its radios as options.
    static func fields(in page: BrowserToolRawPage) -> [BrowserToolFormField] {
        var fields: [BrowserToolFormField] = []
        var groupIndexes: [String: Int] = [:]

        for raw in page.fields {
            guard raw.type == "radio" else {
                fields.append(field(from: raw))
                continue
            }
            // A radio without a name is a group of its own.
            let key = raw.name.isEmpty ? raw.ref : raw.formRef + "\u{1F}" + raw.name
            let option = BrowserToolRawPage.Option(value: raw.value ?? "", label: label(for: raw.labels, name: raw.value ?? ""))
            if let index = groupIndexes[key] {
                fields[index].options?.append(option)
                fields[index].radioRefs[option.value] = fields[index].radioRefs[option.value] ?? raw.ref
                fields[index].required = fields[index].required || raw.required
                fields[index].visible = fields[index].visible || raw.visible
                fields[index].disabled = fields[index].disabled && raw.disabled
                fields[index].restricted = !fields[index].visible
                if raw.checked == true { fields[index].value = option.value }
                if fields[index].error == nil, !raw.error.isEmpty { fields[index].error = raw.error }
            } else {
                groupIndexes[key] = fields.count
                fields.append(BrowserToolFormField(ref: raw.ref,
                                                   formRef: raw.formRef,
                                                   label: groupLabel(for: raw.groupLabels, name: raw.name),
                                                   type: "radio",
                                                   required: raw.required,
                                                   disabled: raw.disabled,
                                                   visible: raw.visible,
                                                   restricted: !raw.visible,
                                                   value: raw.checked == true ? option.value : nil,
                                                   options: [option],
                                                   radioRefs: [option.value: raw.ref],
                                                   error: raw.error.isEmpty ? nil : raw.error,
                                                   autocomplete: raw.autocomplete))
            }
        }
        return fields
    }

    private static func field(from raw: BrowserToolRawPage.Field) -> BrowserToolFormField {
        let restricted = isRestricted(raw)
        let payment = isPaymentField(raw)
        let value: String?
        if restricted || payment {
            value = nil
        } else if raw.type == "checkbox" {
            value = raw.checked == true ? "true" : "false"
        } else {
            value = raw.value
        }
        return BrowserToolFormField(ref: raw.ref,
                                    formRef: raw.formRef,
                                    label: label(for: raw.labels, name: raw.name),
                                    type: raw.tag == "input" ? raw.type : raw.tag,
                                    required: raw.required,
                                    disabled: raw.disabled,
                                    visible: raw.visible,
                                    restricted: restricted,
                                    value: value,
                                    options: raw.options,
                                    error: raw.error.isEmpty ? nil : raw.error,
                                    autocomplete: raw.autocomplete,
                                    readOnly: raw.readOnly,
                                    payment: payment)
    }

    // MARK: - Restrictions

    /// Never filled or submitted: secrets, card data, uploads, and anything the user cannot see.
    static func isRestricted(_ field: BrowserToolRawPage.Field) -> Bool {
        if ["password", "file", "hidden"].contains(field.type) || !field.visible {
            return true
        }
        return autocompleteTokens(field).contains { $0.hasPrefix("cc-") || $0 == "current-password" || $0 == "new-password" }
    }

    /// A login page. Its snapshot is still readable, but nothing on it is submitted.
    static func isRestrictedPage(_ page: BrowserToolRawPage) -> Bool {
        let visibleFields = page.fields.filter(\.visible)
        return Dictionary(grouping: visibleFields, by: \.formRef).contains { formRef, fields in
            guard fields.contains(where: { $0.type == "password" }) else { return false }
            // A quote form may offer an optional password; a sign-in form is little else.
            let otherFillable = fields.filter { !["password", "checkbox", "radio", "hidden"].contains($0.type) }
            let hasSignInButton = page.buttons.contains { $0.formRef == formRef && $0.visible && matches($0.text, signInWords) }
            return otherFillable.count <= 2 || hasSignInButton
        }
    }

    /// Card data by `autocomplete`, by Autofill's own classification, or by name.
    static func isPaymentField(_ field: BrowserToolRawPage.Field) -> Bool {
        autocompleteTokens(field).contains { $0.hasPrefix("cc-") }
            || field.ddgInputType.hasPrefix("creditCards.")
            || matches(field.name, paymentFieldNames)
    }

    /// A checkout: the user pays and places the order themselves, so nothing on it is submitted for them.
    static func hasPaymentFields(_ page: BrowserToolRawPage, formRef: String? = nil) -> Bool {
        page.fields.contains { $0.visible && (formRef == nil || $0.formRef == formRef) && isPaymentField($0) }
    }

    private static func autocompleteTokens(_ field: BrowserToolRawPage.Field) -> [String] {
        field.autocomplete.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: - Buttons

    /// A submit button by type, or one whose text says it sends something or orders. The second
    /// keeps a script-driven "Get my quote" or "Place order" from being clicked without approval.
    /// Cart buttons such as "Add to cart" stay clickable as long as their form takes no typed-in
    /// details, since then the submit carries nothing personal.
    static func isSubmit(_ button: BrowserToolRawPage.Button, formHasTextEntry: Bool = true) -> Bool {
        let type = button.typeAttribute?.lowercased()
        if type == "reset" {
            return false
        }
        let submitsByType = (button.tag == "input" && (type == "submit" || type == "image"))
            || (button.tag == "button" && button.inForm && type != "button")
        if submitsByType {
            return formHasTextEntry || !matches(button.text, cartWords)
        }
        return matches(button.text, submitWords)
    }

    static func isSubmit(_ button: BrowserToolRawPage.Button, in page: BrowserToolRawPage) -> Bool {
        isSubmit(button, formHasTextEntry: formHasTextEntry(button.formRef, in: page))
    }

    /// Whether the form takes typed-in details, the kind a submit would send.
    static func formHasTextEntry(_ formRef: String, in page: BrowserToolRawPage) -> Bool {
        page.fields.contains { $0.formRef == formRef && $0.visible && !$0.disabled && textEntryTypes.contains($0.type) }
    }

    // MARK: - Snapshot

    static func snapshot(of page: BrowserToolRawPage, tabID: String) -> JSONValue {
        let fields = fields(in: page).filter { $0.visible && !$0.disabled }
        var fieldBudget = maxFields
        var buttonBudget = maxButtons
        var forms: [JSONValue] = []

        for form in page.forms {
            let formFields = fields.filter { $0.formRef == form.ref }.prefix(fieldBudget)
            let formButtons = page.buttons.filter { $0.formRef == form.ref && $0.visible && !$0.disabled }.prefix(buttonBudget)
            let formHasTextEntry = formHasTextEntry(form.ref, in: page)
            fieldBudget -= formFields.count
            buttonBudget -= formButtons.count
            guard !formFields.isEmpty || !formButtons.isEmpty else { continue }

            var object: [String: JSONValue] = [
                "ref": .string(form.ref),
                "fields": .array(formFields.map(snapshotValue)),
                "buttons": .array(formButtons.map {
                    ["ref": .string($0.ref), "text": .string($0.text), "isSubmit": .bool(isSubmit($0, formHasTextEntry: formHasTextEntry))]
                }),
                "hasPaymentFields": .bool(hasPaymentFields(page, formRef: form.ref))
            ]
            if !form.name.isEmpty { object["name"] = .string(form.name) }
            forms.append(.object(object))
        }

        return [
            "tabId": .string(tabID),
            "url": .string(page.url),
            "title": .string(page.title),
            "forms": .array(forms),
            "messages": .array(page.messages.map { .string($0.text) })
        ]
    }

    private static func snapshotValue(of field: BrowserToolFormField) -> JSONValue {
        var object: [String: JSONValue] = [
            "ref": .string(field.ref),
            "label": .string(field.label),
            "type": .string(field.type),
            "required": .bool(field.required),
            "autocomplete": .string(field.autocomplete)
        ]
        if !field.restricted, !field.payment, let value = field.value, !value.isEmpty { object["value"] = .string(value) }
        if field.readOnly { object["readOnly"] = true }
        if field.payment { object["sensitive"] = "payment" }
        if let options = field.options, field.type == "select" || field.type == "radio" {
            object["options"] = .array(options.map { ["value": .string($0.value), "label": .string($0.label)] })
        }
        if let error = field.error { object["error"] = .string(error) }
        return .object(object)
    }

    // MARK: - Errors

    /// Field errors on visible fields, then the page's alerts. `formRef` narrows them to one form.
    static func errors(in page: BrowserToolRawPage, formRef: String? = nil) -> [BrowserToolFormError] {
        let fieldErrors = fields(in: page)
            .filter { $0.visible && (formRef == nil || $0.formRef == formRef) }
            .compactMap { field in field.error.map { BrowserToolFormError(ref: field.ref, message: $0) } }
        let alerts = page.messages.filter(\.isAlert).map { BrowserToolFormError(ref: nil, message: $0.text) }
        return fieldErrors + alerts
    }

    // MARK: - Filling

    static func fillPlan(for entries: [(ref: String, value: String)], fields: [BrowserToolFormField]) -> BrowserToolFillPlan {
        var plan = BrowserToolFillPlan()
        for entry in entries {
            guard let field = fields.first(where: { $0.ref == entry.ref }) else {
                plan.failed.append((entry.ref, "not_found"))
                continue
            }
            if field.payment {
                plan.failed.append((entry.ref, "user_action_required"))
                continue
            }
            if field.restricted {
                plan.failed.append((entry.ref, "restricted"))
                continue
            }
            if field.disabled || field.readOnly {
                plan.failed.append((entry.ref, "disabled"))
                continue
            }
            let action: BrowserToolFillAction?
            switch field.type {
            case "select":
                action = option(matching: entry.value, in: field.options).map { .select(ref: field.ref, value: $0.value) }
            case "radio":
                action = option(matching: entry.value, in: field.options)
                    .flatMap { field.radioRefs[$0.value] }
                    .map { .check(ref: $0, checked: true) }
            case "checkbox":
                switch entry.value.lowercased() {
                case "true": action = .check(ref: field.ref, checked: true)
                case "false": action = .check(ref: field.ref, checked: false)
                default: action = nil
                }
            default:
                action = .text(ref: field.ref, value: entry.value)
            }
            if let action {
                plan.steps.append(.init(fieldRef: field.ref, fieldType: field.type, action: action))
            } else {
                plan.failed.append((entry.ref, "invalid_option"))
            }
        }
        return plan
    }

    /// The option's value first, as the snapshot lists it; then its label, ignoring case.
    static func option(matching value: String, in options: [BrowserToolRawPage.Option]?) -> BrowserToolRawPage.Option? {
        guard let options else { return nil }
        let wanted = collapsed(value)
        return options.first { $0.value == value }
            ?? options.first { collapsed($0.label).caseInsensitiveCompare(wanted) == .orderedSame }
            ?? options.first { $0.value.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    // MARK: - Submitting

    /// What the user approves: the values as the site will receive them, by label, without
    /// anything empty, hidden or secret.
    static func preview(of formRef: String, in page: BrowserToolRawPage) -> BrowserToolFormPreview? {
        guard let form = page.forms.first(where: { $0.ref == formRef }) else { return nil }
        let rows: [(label: String, value: String)] = fields(in: page).compactMap { field in
            // An `<output>` shows a result; the site does not receive it.
            guard field.formRef == formRef, field.visible, !field.restricted, !field.payment, field.type != "output",
                  let value = field.value, !value.isEmpty else { return nil }
            switch field.type {
            case "checkbox":
                return (field.label, value == "true" ? "Yes" : "No")
            case "select", "radio":
                let label = field.options?.first { $0.value == value }?.label ?? value
                return (field.label, label.isEmpty ? value : label)
            default:
                return (field.label, value)
            }
        }
        return BrowserToolFormPreview(site: siteName(of: page),
                                      url: page.url,
                                      formName: form.name.isEmpty ? nil : form.name,
                                      fields: rows)
    }

    /// `og:site_name`, else the part of the title that names the site, else the host.
    static func siteName(of page: BrowserToolRawPage) -> String {
        if let siteName = page.siteName.map(collapsed), !siteName.isEmpty {
            return siteName
        }
        let host = URL(string: page.url)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let segments = titleSeparators
            .reduce(page.title) { title, separator in title.replacingOccurrences(of: separator, with: "\u{1F}") }
            .components(separatedBy: "\u{1F}")
            .map(collapsed)
            .filter { !$0.isEmpty }
        if segments.count > 1 {
            let compactHost = host.map(compact) ?? ""
            let matchingHost = segments.first { segment in
                let compactSegment = compact(segment)
                return !compactSegment.isEmpty && !compactHost.isEmpty && compactHost.contains(compactSegment)
            }
            return matchingHost ?? segments[segments.count - 1]
        }
        return host ?? collapsed(page.title)
    }

    /// Unclear outcomes answer `submitted: false`: telling the user a quote was requested when it
    /// was not is worse than asking the model to look again.
    static func submitOutcome(navigated: Bool,
                              formRef: String,
                              before: BrowserToolRawPage,
                              after: BrowserToolRawPage?) -> (submitted: Bool, errors: [BrowserToolFormError]) {
        if navigated {
            return (true, [])
        }
        guard let after else { return (false, []) }
        let formStillShown = after.forms.contains { $0.ref == formRef && $0.visible }
            && fields(in: after).contains { $0.formRef == formRef && $0.visible }
        if !formStillShown {
            return (true, [])
        }
        let errors = errors(in: after, formRef: formRef)
        if !errors.isEmpty {
            return (false, errors)
        }
        let earlierMessages = Set(before.messages.map(\.text))
        let newStatus = after.messages.contains { !$0.isAlert && !earlierMessages.contains($0.text) }
        return (newStatus, [])
    }

    /// Status and alert text when the page has any, as a confirmation usually is; else the main content.
    static func confirmationText(of page: BrowserToolRawPage?) -> String {
        guard let page else { return "" }
        let messages = page.messages.map(\.text).joined(separator: "\n")
        let text = messages.isEmpty ? page.mainText : messages
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxConfirmationLength))
    }

    // MARK: - Text

    private static let titleSeparators = [" | ", " - ", " – ", " — ", " · ", " :: "]
    private static let submitWords = #"\b(submit|send|request|quote|book|confirm|place order|complete order|order now|pay|buy now|purchase|sign up|register)\b"#
    private static let cartWords = #"\b(add to (cart|bag|basket)|(continue|go|proceed) to checkout|checkout|check out|view (cart|bag|basket))\b"#
    /// Fields a person types details into; a quantity or a choice is not one.
    private static let textEntryTypes: Set<String> = ["text", "email", "tel", "search", "url", "password", "date", "textarea"]
    private static let signInWords = #"\b(sign in|log in|login|sign on)\b"#
    private static let paymentFieldNames = #"(card.?num|cc.?num|cvc|cvv|csc|card.?security)"#

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
