//
//  VPNExclusionSuggestionAlert.swift
//  NetworkProtectionMac
//
//  Created by ddg on 3/24/25.
//

import SwiftUI
import SwiftUIExtensions

public struct VPNExclusionSuggestionAlert: ModalView {

    public enum Result: Sendable {
        case stopVPN
        case excludeApp
        case excludeWebsite
    }

    @Environment(\.dismiss) private var dismiss
    @Binding private var result: Result
    @State private var dontAskAgain = false

    public init(result: Binding<Result>) {
        _result = result
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Is the VPN causing problems with a Website or App?")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            // Description
            Text("You can exclude websites and apps from the VPN without turning it off.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Checkbox
            Toggle(isOn: $dontAskAgain) {
                Text("Don't Ask Again")
                    .font(.subheadline)
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.horizontal)

            // Buttons
            HStack(spacing: 10) {
                Button(action: {
                    result = .stopVPN
                    dismiss()
                }) {
                    Text("Turn off VPN")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: {
                    result = .excludeWebsite
                    dismiss()
                }) {
                    Text("Exclude a Website")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }

                Button(action: {
                    result = .excludeApp
                    dismiss()
                }) {
                    Text("Exclude an App")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 400)
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 10)
    }
}

// Custom Checkbox Style for Toggle
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}

struct VPNExclusionSuggestionAlert_Previews: PreviewProvider {

    static var previews: some View {
        VPNExclusionSuggestionAlert(result: .constant(.stopVPN))
    }
}
