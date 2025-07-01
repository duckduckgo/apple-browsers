//
//  AutofillCreditCardDetailsView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import BrowserServicesKit

struct AutofillCreditCardDetailsView: View {
    
    @ObservedObject var viewModel: AutofillCreditCardDetailsViewModel
    
    var body: some View {
        if viewModel.authenticationRequired {
            LockScreenView()
                .frame(maxHeight: .infinity)
                .ignoresSafeArea()
        } else {
            list
        }
    }
    
    private var list: some View {
        List {
            switch viewModel.viewMode {
            case .edit:
                editingContentView
            case .view:
                viewingContentView
            case .new:
                editingContentView
            }
        }
        .simultaneousGesture(
            DragGesture().onChanged({_ in
                viewModel.selectedCell = nil
            }))
        .applyInsetGroupedListStyle()
        .animation(.easeInOut, value: viewModel.viewMode)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            viewModel.viewMode == .view ? false : true
        )
    }
    
    private var viewingContentView: some View {
        Group {
            Section {
                AutofillCopyableRow(title: UserText.autofillCreditCardDetailsCardNumber,
                                    subtitle: viewModel.formattedCardNumber,
                                    selectedCell: $viewModel.selectedCell,
                                    isMonospaced: true,
                                    actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCardNumber),
                                    action: { viewModel.copyToPasteboard(.cardNumber) },
                                    buttonImage: DesignSystemImages.Glyphs.Size24.copy,
                                    buttonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCardNumber),
                                    buttonAction: { viewModel.copyToPasteboard(.cardNumber) })
                
                AutofillCopyableRow(title: UserText.autofillCreditCardDetailsExpirationDate,
                                    subtitle: viewModel.formattedExpiration,
                                    selectedCell: $viewModel.selectedCell,
                                    actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsExpirationDate),
                                    action: { viewModel.copyToPasteboard(.expirationDate) },
                                    buttonImage: DesignSystemImages.Glyphs.Size24.copy,
                                    buttonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsExpirationDate),
                                    buttonAction: { viewModel.copyToPasteboard(.expirationDate) })
                
                AutofillCopyableRow(title: UserText.autofillCreditCardDetailsCVV,
                                    subtitle: viewModel.userVisibleCardSecurityCode,
                                    selectedCell: $viewModel.selectedCell,
                                    isMonospaced: true,
                                    actionTitle: viewModel.isSecurityCodeHidden ? UserText.autofillShowCreditCardCVV : UserText.autofillHideCreditCardCVV,
                                    action: { viewModel.isSecurityCodeHidden.toggle() },
                                    secondaryActionTitle: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCVV),
                                    secondaryAction: { viewModel.copyToPasteboard(.cardSecurityCode) },
                                    buttonImage: viewModel.isSecurityCodeHidden ? DesignSystemImages.Glyphs.Size24.eye : DesignSystemImages.Glyphs.Size24.eyeClosed,
                                    buttonAccessibilityLabel: viewModel.isSecurityCodeHidden ? UserText.autofillShowCreditCardCVV : UserText.autofillHideCreditCardCVV,
                                    buttonAction: { viewModel.isSecurityCodeHidden.toggle() },
                                    secondaryButtonImage: DesignSystemImages.Glyphs.Size24.copy,
                                    secondaryButtonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCVV),
                                    secondaryButtonAction: { viewModel.copyToPasteboard(.cardSecurityCode) })
                
                AutofillCopyableRow(title: UserText.autofillCreditCardDetailsCardName,
                                    subtitle: viewModel.cardholderName,
                                    selectedCell: $viewModel.selectedCell,
                                    actionTitle: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCardName),
                                    action: { viewModel.copyToPasteboard(.cardholderName) },
                                    buttonImage: DesignSystemImages.Glyphs.Size24.copy,
                                    buttonAccessibilityLabel: UserText.autofillCopyPrompt(for: UserText.autofillCreditCardDetailsCardName),
                                    buttonAction: { viewModel.copyToPasteboard(.cardholderName) })
            }

            Section {
                deleteCell()
            }
        }
    }
    
    private var editingContentView: some View {
        Group {
            Section {
                EditableCreditCardNumberCell(title: UserText.autofillCreditCardDetailsCardNumberEditing,
                                             placeholderText: UserText.autofillCreditCardDetailsEditCardNumberPlaceholder,
                                             text: $viewModel.cardNumber,
                                             formattedText: $viewModel.formattedCardNumber,
                                             isCardValid: $viewModel.isCardValid,
                                             selectedCell: $viewModel.selectedCell)
                .accessibilityIdentifier("Field_CardNumber")
                
                EditableDateCell(title: UserText.autofillCreditCardDetailsExpirationDate,
                                 placeholderText: UserText.autofillCreditCardDetailsEditExpirationDatePlaceholder,
                                 expirationMonth: $viewModel.expirationMonth,
                                 expirationYear: $viewModel.expirationYear,
                                 formattedExpiration: $viewModel.formattedExpiration,
                                 selectedCell: $viewModel.selectedCell,
                                 formatExpiration: viewModel.expirationDateString)
                .accessibilityIdentifier("Field_ExpirationDate")
                
                if viewModel.viewMode == .new {
                    AutofillEditableCell(title: UserText.autofillCreditCardDetailsCVV,
                                         text: $viewModel.cardSecurityCode,
                                         placeholderText: UserText.autofillCreditCardDetailsEditCVVPlaceholder,
                                         secure: true,
                                         keyboardType: .numberPad,
                                         inEditMode: viewModel.viewMode == .edit,
                                         characterLimit: 4,
                                         selectedCell: $viewModel.selectedCell)
                    .accessibilityIdentifier("Field_SecurityCode")
                } else {
                    AutofillEditableMaskedCell(title: UserText.autofillCreditCardDetailsCVV,
                                               placeholderText: UserText.autofillCreditCardDetailsEditCVVPlaceholder,
                                               unmaskedString: $viewModel.cardSecurityCode,
                                               maskedString: .constant(viewModel.userVisibleCardSecurityCode),
                                               isMasked: $viewModel.isSecurityCodeHidden,
                                               keyboardType: .numberPad,
                                               characterLimit: 4,
                                               selectedCell: $viewModel.selectedCell)
                    .accessibilityIdentifier("Field_SecurityCode")
                }
                
                AutofillEditableCell(title: UserText.autofillCreditCardDetailsCardName,
                                     text: $viewModel.cardholderName,
                                     placeholderText: UserText.autofillCreditCardDetailsEditCardNamePlaceholder,
                                     autoCapitalizationType: .words,
                                     disableAutoCorrection: true,
                                     inEditMode: viewModel.viewMode == .edit,
                                     selectedCell: $viewModel.selectedCell)
                .accessibilityIdentifier("Field_CardName")
            }
            
            Section {
                AutofillEditableCell(title: UserText.autofillCreditCardDetailsCardNickname,
                                     text: $viewModel.cardTitle,
                                     placeholderText: UserText.autofillCreditCardDetailsEditCardNicknamePlaceholder,
                                     autoCapitalizationType: .words,
                                     inEditMode: viewModel.viewMode == .edit,
                                     selectedCell: $viewModel.selectedCell)
                .accessibilityIdentifier("Field_CardNickname")
            }
            
            if viewModel.viewMode == .edit {
                deleteCell()
            }
        }
    }
    
    private func deleteCell() -> some View {
        AutofillDeleteButtonCell(deleteButtonText: UserText.autofillCreditCardDetailsDeleteButton,
                                 confirmationTitle: UserText.autofillCreditCardDetailsDeleteConfirmationMessage,
                                 confirmationButtonTitle: UserText.autofillCreditCardDetailsDeleteConfirmationButtonTitle,
                                 onDelete: {
            viewModel.delete()
        })
    }
}

private struct EditableCreditCardNumberCell: View {
    @Environment(\.sizeCategory) private var sizeCategory
    
    @State private var id = UUID()
    let title: String
    let placeholderText: String
    @Binding var text: String
    @Binding var formattedText: String
    @Binding var isCardValid: Bool
    @Binding var selectedCell: UUID?
    @State private var closeButtonVisible: Bool?
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: Constants.verticalPadding) {
            Text(title)
                .daxBodyRegular()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            
            HStack {
                CreditCardNumberField(
                    id: id,
                    placeholder: placeholderText,
                    cardNumber: $text,
                    formattedCardNumber: $formattedText,
                    isCardValid: $isCardValid,
                    isEditing: $closeButtonVisible,
                    selectedCell: $selectedCell)
                .frame(height: heightForSizeCategory(sizeCategory))
                
                Spacer()
                
                if text.count > 0 {
                    if let closeButtonVisible = closeButtonVisible {
                        if closeButtonVisible {
                            Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                                .onTapGesture {
                                    self.text = ""
                                    self.formattedText = ""
                                    self.isCardValid = CreditCardValidation.isValidCardNumber(text)
                                }
                        } else if !isCardValid {
                            Image(uiImage: DesignSystemImages.Glyphs.Size16.exclamationRecolorable)
                        }
                    }
                }
            }
        }
        .frame(minHeight: Constants.minRowHeight)
        .listRowInsets(Constants.insets)
    }
    
    private func heightForSizeCategory(_ category: ContentSizeCategory) -> CGFloat {
        switch category {
        case .accessibilityMedium, .extraExtraLarge, .extraExtraExtraLarge:
            return 24
        case .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return 40
        default:
            return 20
        }
    }
    
    private struct CreditCardNumberField: UIViewRepresentable {
        var id: UUID
        var placeholder: String?
        @Binding var cardNumber: String
        @Binding var formattedCardNumber: String
        @Binding var isCardValid: Bool
        @Binding var isEditing: Bool?
        @Binding var selectedCell: UUID?
        
        func makeUIView(context: Context) -> UITextField {
            let textField = UITextField(frame: .zero)
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.keyboardType = .numberPad
            textField.placeholder = placeholder
            textField.delegate = context.coordinator
            textField.pasteDelegate = context.coordinator
            textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange), for: .editingChanged)
            textField.textColor = UIColor(designSystemColor: .textPrimary)
            textField.font = UIFont.monospacedSystemFont(ofSize: UIFont.daxBodyRegular().pointSize, weight: .regular)

            return textField
        }
        
        func updateUIView(_ uiView: UITextField, context: Context) {
            // Only update text if it's different to avoid cursor jumps
            if uiView.text != formattedCardNumber {
                // Store current cursor position
                let currentPosition = uiView.selectedTextRange
                uiView.text = formattedCardNumber
                
                // Restore cursor position if possible
                if let position = currentPosition {
                    uiView.selectedTextRange = position
                }
            }
            
            if selectedCell != id && uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.resignFirstResponder()
                }
           }
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, UITextFieldDelegate, UITextPasteDelegate {
            let parent: CreditCardNumberField
            private var isEditingActive: Bool = false
            private var isPasteOperation = false
            private var needsEndCursorPositioning = false
            
            init(_ parent: CreditCardNumberField) {
                self.parent = parent
            }
            
            func textPasteConfigurationSupporting(
                _ supportingPasteboard: UITextPasteConfigurationSupporting,
                transform item: UITextPasteItem
            ) {
                isPasteOperation = true
                needsEndCursorPositioning = true
                
                // Allow paste to proceed normally
                item.setDefaultResult()
            }
            
            @objc func textFieldDidChange(_ textField: UITextField) {
                let text = textField.text ?? ""
                let currentSelectedRange = textField.selectedTextRange
                var digitsOnly = CreditCardValidation.extractDigits(from: text)
                
                if digitsOnly.count > 19 {
                    digitsOnly = String(digitsOnly.prefix(19))
                }
                
                let formatted = CreditCardValidation.formattedCardNumber(digitsOnly)
                
                parent.cardNumber = digitsOnly
                textField.text = formatted
                parent.formattedCardNumber = formatted
                parent.isCardValid = CreditCardValidation.isValidCardNumber(digitsOnly)
                
                updateCursorPosition(textField, oldText: text, newText: formatted, currentSelection: currentSelectedRange)
                
                if needsEndCursorPositioning {
                    DispatchQueue.main.async {
                        if let newPosition = textField.position(from: textField.beginningOfDocument, offset: formatted.count) {
                            textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
                        }
                        self.isPasteOperation = false
                        self.needsEndCursorPositioning = false
                    }
                }
            }
            
            private func updateCursorPosition(_ textField: UITextField, oldText: String, newText: String, currentSelection: UITextRange?) {
                guard let selectedRange = currentSelection else { return }
                
                let cursorPosition = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
                
                let oldTextPrefix = oldText.prefix(cursorPosition)
                let oldSpacesBeforeCursor = oldTextPrefix.filter { $0 == " " }.count
                var newCursorPosition = cursorPosition
                
                if newCursorPosition < newText.count {
                    let newTextPrefix = newText.prefix(newCursorPosition)
                    let newSpacesBeforeCursor = newTextPrefix.filter { $0 == " " }.count
                    
                    newCursorPosition += (newSpacesBeforeCursor - oldSpacesBeforeCursor)
                    newCursorPosition = min(newCursorPosition, newText.count)
                    
                    if let newCursorLocation = textField.position(from: textField.beginningOfDocument, offset: newCursorPosition) {
                        textField.selectedTextRange = textField.textRange(from: newCursorLocation, to: newCursorLocation)
                    }
                }
            }
            
            func textFieldDidBeginEditing(_ textField: UITextField) {
                isEditingActive = true
                parent.isEditing = true
                parent.selectedCell = parent.id
                
                textField.textColor = UIColor(designSystemColor: .textPrimary)
            }
            
            func textFieldDidEndEditing(_ textField: UITextField) {
                isEditingActive = false
                parent.isEditing = false
                parent.selectedCell = nil
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !self.parent.isCardValid && !self.parent.formattedCardNumber.isEmpty {
                        textField.textColor = .systemRed
                    } else {
                        textField.textColor = UIColor(designSystemColor: .textPrimary)
                    }
                }
            }
        }
    }
}

private struct EditableDateCell: View {
    @State private var id = UUID()
    let title: String
    let placeholderText: String
    @Binding var expirationMonth: Int?
    @Binding var expirationYear: Int?
    @Binding var formattedExpiration: String
    @Binding var selectedCell: UUID?
    let formatExpiration: (() -> String)
    
    @State private var showingPicker = false
    @State private var closeButtonVisible = false
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: Constants.verticalPadding) {
            Text(title)
                .daxBodyRegular()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            
            HStack {
                TextField(placeholderText, text: $formattedExpiration)
                    .daxBodyRegular()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .allowsHitTesting(false)
                    .disabled(true)
                    .overlay(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                hideKeyboard()
                                showingPicker = true
                                selectedCell = self.id
                            }
                    )
                
                Spacer()
                
                if formattedExpiration.count > 0 {
                    if selectedCell == id {
                        Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                            .onTapGesture {
                                self.formattedExpiration = ""
                                self.expirationMonth = nil
                                self.expirationYear = nil
                            }
                    }
                }
            }
        }
        .frame(minHeight: Constants.minRowHeight)
        .listRowInsets(Constants.insets)
        .sheet(isPresented: $showingPicker) {
            MonthYearPickerView(
                expirationMonth: $expirationMonth,
                expirationYear: $expirationYear,
                formattedExpiration: $formattedExpiration,
                isPresented: $showingPicker,
                formatExpiration: formatExpiration
            )
            .setPrestentationDetents(height: 260.0)
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct MonthYearPickerView: View {
    @Binding var expirationMonth: Int?
    @Binding var expirationYear: Int?
    @Binding var formattedExpiration: String
    @Binding var isPresented: Bool
    let formatExpiration: (() -> String)
    
    @State private var selectedDate: Date
    
    internal init(expirationMonth: Binding<Int?>,
                  expirationYear: Binding<Int?>,
                  formattedExpiration: Binding<String>,
                  isPresented: Binding<Bool>,
                  formatExpiration: @escaping () -> String) {
        self._expirationMonth = expirationMonth
        self._expirationYear = expirationYear
        self._formattedExpiration = formattedExpiration
        self._isPresented = isPresented
        self.formatExpiration = formatExpiration
        
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        var initialDate: Date = oneYearFromNow
        
        // Initialize selectedDate based on the current expirationMonth and expirationYear (if set)
        if expirationMonth.wrappedValue != nil && expirationYear.wrappedValue != nil {
            var dateComponents = DateComponents()
            dateComponents.day = 1
            dateComponents.month = expirationMonth.wrappedValue
            dateComponents.year = expirationYear.wrappedValue
            if let specificDate = Calendar.current.date(from: dateComponents) {
                initialDate = specificDate
            }
        }
        
        self._selectedDate = State(initialValue: initialDate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Text(UserText.actionCancel)
                        .daxBodyRegular()
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                }
                
                Spacer()
                
                Button {
                    let calendar = Calendar.current
                    expirationMonth = calendar.component(.month, from: selectedDate)
                    expirationYear = calendar.component(.year, from: selectedDate)
                    formattedExpiration = formatExpiration()
                    isPresented = false
                } label: {
                    Text(UserText.navigationTitleDone)
                        .daxBodyBold()
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            MonthYearPicker(date: $selectedDate)
                .frame(height: 200)
                .padding(.top, 0)
                .padding(.bottom, 0)
        }
    }
    
    // UIViewRepresentable wrapper for UIDatePicker that only shows month and year
    private struct MonthYearPicker: UIViewRepresentable {
        @Binding var date: Date
        
        func makeUIView(context: Context) -> UIDatePicker {
            let picker = UIDatePicker()
            if #available(iOS 17.4, *) {
                picker.datePickerMode = .yearAndMonth
            } else {
                picker.datePickerMode = .date
                picker.datePickerMode = .init(rawValue: 4269) ?? .date
            }
            picker.preferredDatePickerStyle = .wheels
            
            let calendar = Calendar.current
            let currentDate = Date()
            
            // Set minimum date as current date
            picker.minimumDate = currentDate
            
            // Set maximum date (current year + 15 years)
            if let maxDate = calendar.date(byAdding: .year, value: 15, to: currentDate) {
                picker.maximumDate = maxDate
            }
            
            picker.addTarget(
                context.coordinator,
                action: #selector(Coordinator.dateChanged(_:)),
                for: .valueChanged
            )
            
            return picker
        }
        
        func updateUIView(_ uiView: UIDatePicker, context: Context) {
            uiView.date = date
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject {
            var parent: MonthYearPicker
            
            init(_ parent: MonthYearPicker) {
                self.parent = parent
            }
            
            @objc func dateChanged(_ sender: UIDatePicker) {
                parent.date = sender.date
            }
        }
    }
}

private extension View {
    
    @ViewBuilder
    func setPrestentationDetents(height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.height(height)])
        } else {
            self
        }
    }
    
}

private struct Constants {
    static let verticalPadding: CGFloat = 4
    static let minRowHeight: CGFloat = 60
    static let insets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
}

#Preview {
    AutofillCreditCardDetailsView(viewModel: AutofillCreditCardDetailsViewModel(authenticator: AutofillLoginListAuthenticator(reason: UserText.autofillCreditCardAuthenticationReason, cancelTitle: UserText.autofillLoginListAuthenticationCancelButton)))
}
