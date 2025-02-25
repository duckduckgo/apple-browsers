//
//  AlertPlaygroundView.swift
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

import SwiftUI

struct AlertPlaygroundView: View {
    
    enum ActionStyle: String, CaseIterable {
        case `default`
        case cancel
        case destructive
        
        var uikitStyle: UIAlertAction.Style {
            switch self {
            case .default:
                return .default
            case .cancel:
                return .cancel
            case .destructive:
                return .destructive
            }
        }
        
    }
    
    @State var title: String = "Example title"
    @State var message: String = "An example of a message"
    @State var primary: String = "Primary"
    @State var secondary: String = "Secondary"

    @State var primaryStyle: ActionStyle = .default
    @State var secondaryStyle: ActionStyle = .default
    
    @State var alertPresented = false
    
    var isDoubleCancel: Bool {
        primaryStyle == .cancel && secondaryStyle == .cancel
    }
    
    func showUIAlert() {
        guard let controller = UIApplication.shared.window?.rootViewController?.presentedViewController else { return }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(title: primary, style: primaryStyle.uikitStyle)
        alert.addAction(title: secondary, style: secondaryStyle.uikitStyle)
        controller.present(alert, animated: true)
        
    }

    var body: some View {
        List {
            Section {
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Title")
                        .font(.caption)
                    TextField("Title", text: $title)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Message")
                        .font(.caption)
                    TextField("Message", text: $message)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Primary / First Action")
                        .font(.caption)
                    HStack {
                        TextField("Primary / First Action", text: $primary)
                        Spacer()
                        Picker("", selection: $primaryStyle, content: {
                            ForEach(ActionStyle.allCases, id: \.rawValue) { style in
                                Text(style.rawValue).tag(style)
                            }
                        })
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Secondary / Second Action")
                        .font(.caption)
                    HStack {
                        TextField("Secondary / Second Action", text: $secondary)
                        Spacer()
                        Picker("", selection: $secondaryStyle, content: {
                            ForEach(ActionStyle.allCases, id: \.rawValue) { style in
                                Text(style.rawValue).tag(style)
                            }
                        })
                    }
                }
            } footer: {
                VStack {
                    HStack {
                        
                        Button {
                            alertPresented = true
                        } label: {
                            Text("SwiftUI Alert")
                        }
                        .buttonStyle(.bordered)
                        .alert(title, isPresented: $alertPresented, actions: {
                            
                            switch primaryStyle {
                            case .default:
                                Button(primary) { }
                            case .cancel:
                                Button(primary, role: .cancel) { }
                            case .destructive:
                                Button(primary, role: .destructive) { }
                            }
                            
                            switch secondaryStyle {
                            case .default:
                                Button(secondary) { }
                            case .cancel:
                                Button(secondary, role: .cancel) { }
                            case .destructive:
                                Button(secondary, role: .destructive) { }
                            }
                            
                        }, message: {
                            Text(message)
                        })
                        .disabled(isDoubleCancel)
                        
                        Button {
                            showUIAlert()
                        } label: {
                            Text("UIAlert")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDoubleCancel)
                    }
                    
                    if isDoubleCancel {
                        Text("Cancel is not allowed more than once")
                            .bold()
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Alert Playground")

    }
    
}
