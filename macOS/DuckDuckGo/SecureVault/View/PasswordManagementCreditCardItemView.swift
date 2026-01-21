//
//  PasswordManagementCreditCardItemView.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import SwiftUI
import BrowserServicesKit
import SwiftUIExtensions

private let interItemSpacing: CGFloat = 23
private let itemSpacing: CGFloat = 13

struct PasswordManagementCreditCardItemView: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    var body: some View {

        if model.card != nil {

            ZStack(alignment: .top) {
                Spacer()

                if model.isInEditMode {

                    RoundedRectangle(cornerRadius: 8)
                        .foregroundColor(Color(.editingPanel))
                        .shadow(radius: 6)

                }

                VStack(alignment: .leading, spacing: 0) {

                    HeaderView()
                        .padding(.top, 16)
                        .padding(.bottom, model.isInEditMode ? 20 : 30)

                    EditableCreditCardField(textFieldValue: $model.cardNumber, title: UserText.pmCardNumber, accessibilityIdentifier: "Card Number TextField")
                    ExpirationField()
                    EditableCreditCardField(textFieldValue: $model.cardholderName, title: UserText.pmCardholderName, accessibilityIdentifier: "Cardholder Name TextField", placeholder: UserText.pmCardholderNamePlaceholder)
                    SecureEditableCreditCardField(textFieldValue: $model.cardSecurityCode,
                                                  title: UserText.pmCardVerificationValue,
                                                  hiddenTextLength: 3,
                                                  toolTipHideText: UserText.autofillHideCardCvvTooltip,
                                                  toolTipShowText: UserText.autofillShowCardCvvTooltip,
                                                  placeholder: UserText.pmCardVerificationValuePlaceholder)

                    Spacer(minLength: 0)

                    Buttons()
                        .padding(.top, model.isInEditMode ? 12 : 10)
                        .padding(.bottom, model.isInEditMode ? 12 : 3)

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)

            }
            .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 10))

        }

    }

}

private struct HeaderView: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    var body: some View {

        HStack(alignment: .center, spacing: 0) {

            if let card = model.card {
                Image(nsImage: card.iconImage)
                    .padding(.trailing, 10)
            } else {
                Image(.card)
                    .padding(.trailing, 10)
            }

            if model.isNew || model.isEditing {

                TextField(UserText.pmCardNicknamePlaceholder, text: $model.title)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .frame(height: 32)
                    .background(Color.white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                    .accessibility(identifier: "Title TextField")

            } else {

                Text(model.title)
                    .font(.title)

            }

        }

    }

}

// MARK: - Generic Views

private struct Buttons: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    var body: some View {
        HStack {

            if model.isEditing && !model.isNew {
                Button(UserText.pmDelete) {
                    model.requestDelete()
                }
                .buttonStyle(StandardButtonStyle())
            }

            Spacer()

            if model.isEditing || model.isNew {
                Button(UserText.pmCancel) {
                    model.cancel()
                }
                .buttonStyle(StandardButtonStyle())
                Button(UserText.pmSave) {
                    model.save()
                }
                .disabled(!model.isDirty)
                .buttonStyle(DefaultActionButtonStyle(enabled: model.isDirty))

            } else {
                Button(UserText.pmDelete) {
                    model.requestDelete()
                }
                .buttonStyle(StandardButtonStyle())

                Button(UserText.pmEdit) {
                    model.edit()
                }
                .buttonStyle(StandardButtonStyle())

            }

        }
    }

}

private struct EditableCreditCardField: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    @State var isHovering = false
    @Binding var textFieldValue: String

    let title: String
    let accessibilityIdentifier: String
    let placeholder: String

    var body: some View {

        if model.isInEditMode || !textFieldValue.isEmpty {

            VStack(alignment: .leading, spacing: 0) {

                Text(title)
                    .bold()
                    .padding(.bottom, 5)

                if model.isEditing || model.isNew {

                    TextField(placeholder, text: $textFieldValue)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.bottom, interItemSpacing)
                        .accessibility(identifier: accessibilityIdentifier)

                } else {

                    HStack(spacing: 6) {
                        Text(textFieldValue)

                        if isHovering {
                            Button {
                                model.copy(textFieldValue)
                            } label: {
                                Image(.copy)
                            }.buttonStyle(PlainButtonStyle())
                        }

                        Spacer()
                    }
                    .padding(.bottom, interItemSpacing)
                }

            }
            .onHover {
                isHovering = $0
            }

        }
    }
}

private struct SecureEditableCreditCardField: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    @Binding var textFieldValue: String

    @State private var isHovering = false
    @State private var isVisible = false

    let title: String
    let hiddenTextLength: Int
    let toolTipHideText: String
    let toolTipShowText: String
    let placeholder: String

    var body: some View {

        if model.isInEditMode || !textFieldValue.isEmpty {

            VStack(alignment: .leading, spacing: 0) {

                Text(title)
                    .bold()
                    .padding(.bottom, 5)

                if model.isEditing || model.isNew {

                    HStack {

                        TextField(placeholder, text: $textFieldValue)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.bottom, interItemSpacing)
                            .accessibility(identifier: "Security Code TextField")

                    }
                    .padding(.bottom, interItemSpacing)

                } else {

                    HStack(spacing: 6) {

                        HiddenText(isVisible: isVisible, text: textFieldValue, hiddenTextLength: hiddenTextLength)

                        if (isHovering || isVisible) && textFieldValue != "" {
                            SecureTextFieldButton(isVisible: $isVisible, toolTipHideText: toolTipHideText, toolTipShowText: toolTipShowText)
                        }

                        if isHovering {
                            CopyButton {
                                model.copy(textFieldValue)
                            }
                        }

                        Spacer()
                    }
                    .padding(.bottom, interItemSpacing)
                }

            }
            .onHover {
                isHovering = $0
            }

        }
    }
}

// MARK: - Expiration Field

/// If the model is currently in edit mode, this will show a picker for the expiration month and year.
/// If the model is not in edit mode, this will show the expiration date in the format of MM/yyyy.
///
private struct ExpirationField: View {

    @EnvironmentObject var model: PasswordManagementCreditCardModel

    @State private var isHovering = false

    var body: some View {

        if model.expirationMonth != nil || model.expirationYear != nil || model.isInEditMode {
            VStack(alignment: .leading, spacing: 0) {

                Text(UserText.pmCardExpiration)
                    .bold()
                    .padding(.bottom, 5)

                if model.isInEditMode {
                    HStack {
                        Picker("", selection: $model.expirationMonth) {
                            if model.expirationMonth == nil {
                                Text(UserText.pmMonth)
                                    .tag(nil as Int?)
                            }
                            ForEach(Date.monthsWithIndex, id: \.self) { month in
                                Text(String(format: "%02d", month.index))
                                    .tag(month.index as Int?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)

                        Picker("", selection: $model.expirationYear) {
                            if model.expirationYear == nil {
                                Text(UserText.pmYear)
                                    .tag(nil as Int?)
                            }
                            ForEach(Date.nextTenYears, id: \.self) { year in
                                Text(String(year))
                                    .tag(year as Int?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)

                    }
                    .padding(.bottom, interItemSpacing)
                } else if let month = model.expirationMonth, let year = model.expirationYear {
                    let components = DateComponents(calendar: Calendar.current, year: year, month: month)

                    if let date = components.date {
                        let expirationString = PasswordManagementCreditCardModel.expirationDateFormatter.string(from: date)

                        HStack(spacing: 6) {
                            Text(expirationString)

                            if isHovering {
                                Button {
                                    model.copy(expirationString)
                                } label: {
                                    Image(.copy)
                                }.buttonStyle(PlainButtonStyle())
                            }

                            Spacer()
                        }
                        .padding(.bottom, interItemSpacing)
                    }
                }

            }
            .onHover {
                isHovering = $0
            }
        }
    }
}
