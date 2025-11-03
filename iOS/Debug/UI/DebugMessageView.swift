//
//  DebugMessageView.swift
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

//  TODO: This is a simplified replacement for ActionMessageView
//  Consider unifying with main app's message presentation in Phase 3

import SwiftUI
import UIKit

/// Simple message presenter for debug actions
public struct DebugMessageView {
    
    /// Present a temporary message overlay
    public static func present(message: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return
            }
            
            let hostingController = UIHostingController(rootView: MessageOverlay(message: message))
            hostingController.view.backgroundColor = .clear
            hostingController.view.frame = window.bounds
            hostingController.view.isUserInteractionEnabled = false
            
            window.addSubview(hostingController.view)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                UIView.animate(withDuration: 0.3, animations: {
                    hostingController.view.alpha = 0
                }) { _ in
                    hostingController.view.removeFromSuperview()
                }
            }
        }
    }
}

private struct MessageOverlay: View {
    let message: String
    
    var body: some View {
        VStack {
            Spacer()
            
            Text(message)
                .padding()
                .background(Color.black.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom))
    }
}
