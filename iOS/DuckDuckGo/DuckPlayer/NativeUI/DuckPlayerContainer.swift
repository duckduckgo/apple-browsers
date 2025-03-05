//
//  DuckPlayerContainer.swift
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
import SwiftUI

private let sheetTopMargin = 44.0

public enum DuckPlayerContainer {

  public struct Constants {
    enum Animation {
      static let easeInOutDuration: Double = 0.3
      static let shortDuration: Double = 0.2
      static let springDuration: Double = 0.5
      static let springBounce: Double = 0.2
    }
    
    enum Offset {
      static let extraHeight: Double = 200.0
      static let initialValue: Double = 10000.0
      static let fixedContainerHeight: Double = 300.0
    }
  }

  public struct PresentationMetrics {
    public let contentWidth: Double
  }

  @MainActor
  public final class ViewModel: ObservableObject {
    @Published public private(set) var sheetVisible = false

    private var subscriptions = Set<AnyCancellable>()
    
    private var shouldAnimate = true
    
    public var springAnimation: Animation? {
      shouldAnimate ? .spring(duration: 0.4, bounce: 0.5, blendDuration: 1.0) : nil
    }

    public func show() {
      sheetVisible = true
    }

    public func dismiss() {
      sheetVisible = false
    }
  }

  public struct Container<Content: View>: View {
    @ObservedObject var viewModel: ViewModel
    
    @State private var sheetHeight = 0.0

    let hasBackground: Bool
    let content: (PresentationMetrics) -> Content

    public init(viewModel: ViewModel, hasBackground: Bool = true, @ViewBuilder content: @escaping (PresentationMetrics) -> Content) {
      self.viewModel = viewModel
      self.hasBackground = hasBackground
      self.content = content
    }
  
    @ViewBuilder private func sheet(containerHeight: Double) -> some View {
      SheetView(
        viewModel: viewModel,
        containerHeight: containerHeight,
        content: content,
        onHeightChange: { sheetHeight = $0 }
      )
    }

    public var body: some View {
      VStack(spacing: 0) {
        // Add a spacer at the top to push content to the bottom
        Spacer(minLength: 0)
        
        if hasBackground {
          Color.black
            .ignoresSafeArea()
            .opacity(viewModel.sheetVisible ? 1 : 0)
            .animation(viewModel.springAnimation, value: viewModel.sheetVisible)
        }
        
        // Use a fixed container height for offset calculations
        sheet(containerHeight: DuckPlayerContainer.Constants.Offset.fixedContainerHeight)
          .frame(alignment: .bottom)
      }
    }
  }
}

// MARK: - Private

private func calculateSheetOffset(for visible: Bool, containerHeight: Double) -> Double {
  visible ? 0 : containerHeight + DuckPlayerContainer.Constants.Offset.extraHeight
}

@MainActor
private struct SheetView<Content: View>: View {
  @ObservedObject var viewModel: DuckPlayerContainer.ViewModel
  let containerHeight: Double
  let content: (DuckPlayerContainer.PresentationMetrics) -> Content
  let onHeightChange: (Double) -> Void

  @State private var sheetHeight: Double = 0
  @State private var sheetWidth: Double?
  @State private var opacity: Double = 0
  @State private var sheetOffset = DuckPlayerContainer.Constants.Offset.initialValue

  var body: some View {
    VStack(alignment: .center) {
      
      if let sheetWidth {
        content(DuckPlayerContainer.PresentationMetrics(contentWidth: sheetWidth))
      }
    }
    .onWidthChange { newWidth in
      sheetWidth = newWidth
    }
    .frame(maxWidth: .infinity)
    .offset(y: sheetOffset)
    .opacity(opacity)
    .animation(.easeInOut(duration: DuckPlayerContainer.Constants.Animation.easeInOutDuration), value: opacity)
    
    .onAppear {
      sheetOffset = calculateSheetOffset(for: viewModel.sheetVisible, containerHeight: containerHeight)
      opacity = viewModel.sheetVisible ? 1 : 0
    }
        
    .onChange(of: viewModel.sheetVisible) { sheetVisible in
      withAnimation(.spring(duration: DuckPlayerContainer.Constants.Animation.springDuration, bounce: DuckPlayerContainer.Constants.Animation.springBounce)) {
        sheetOffset = calculateSheetOffset(for: sheetVisible, containerHeight: containerHeight)
      }
      withAnimation(viewModel.springAnimation) {
        opacity = sheetVisible ? 1 : 0
      }
    }

    .onChange(of: containerHeight) { containerHeight in
      withAnimation(.spring(duration: DuckPlayerContainer.Constants.Animation.springDuration, bounce: DuckPlayerContainer.Constants.Animation.springBounce)) {
        sheetOffset = calculateSheetOffset(for: viewModel.sheetVisible, containerHeight: containerHeight)
      }
      withAnimation(viewModel.springAnimation) {
        opacity = viewModel.sheetVisible ? 1 : 0
      }
    }
    
    .onHeightChange { newHeight in
      sheetHeight = newHeight
      onHeightChange(newHeight)
    }
  }
}

// MARK: - View Extensions

extension View {
  func onWidthChange(perform action: @escaping (Double) -> Void) -> some View {
    background(
      GeometryReader { geometry in
        Color.clear
          .preference(key: WidthPreferenceKey.self, value: geometry.size.width)
          .onPreferenceChange(WidthPreferenceKey.self, perform: action)
      }
    )
  }
  
  func onHeightChange(perform action: @escaping (Double) -> Void) -> some View {
    background(
      GeometryReader { geometry in
        Color.clear
          .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
          .onPreferenceChange(HeightPreferenceKey.self, perform: action)
      }
    )
  }
}

private struct WidthPreferenceKey: PreferenceKey {
  static var defaultValue: Double = 0
  static func reduce(value: inout Double, nextValue: () -> Double) {
    value = nextValue()
  }
}

private struct HeightPreferenceKey: PreferenceKey {
  static var defaultValue: Double = 0
  static func reduce(value: inout Double, nextValue: () -> Double) {
    value = nextValue()
  }
}
