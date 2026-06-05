//
//  SuggestionsFavoritesView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import UIKit

/// Hosts an already-built `NewTabPageViewController` (favorites/NTP) inside the unified view's
/// `.favorites` state. The controller is constructed by the host with full NTP dependencies.
struct SuggestionsFavoritesView: UIViewControllerRepresentable {
    let controller: NewTabPageViewController

    func makeUIViewController(context: Context) -> NewTabPageViewController { controller }
    func updateUIViewController(_ uiViewController: NewTabPageViewController, context: Context) {}
}
