//
//  SlidingPickerView.swift
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

public struct SlidingPickerSettings {
    let backgroundColor: Color
    let borderColor: Color
    let selectionBackgroundColor: Color
    let selectionBorderColor: Color
    let cornerRadius: CGFloat
    let dividerSize: CGSize?
    let elementsPadding: CGFloat
    let sliderInset: CGFloat
    let sliderLineWidth: CGFloat

    public init(
        backgroundColor: Color = .clear,
        borderColor: Color = .clear,
        selectionBackgroundColor: Color = .clear,
        selectionBorderColor: Color = .clear,
        cornerRadius: CGFloat = 4,
        dividerSize: CGSize? = nil,
        elementsPadding: CGFloat = .zero,
        sliderInset: CGFloat = .zero,
        sliderLineWidth: CGFloat = 1)
    {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.selectionBackgroundColor = selectionBackgroundColor
        self.selectionBorderColor = selectionBorderColor
        self.cornerRadius = cornerRadius
        self.dividerSize = dividerSize
        self.elementsPadding = elementsPadding
        self.sliderInset = sliderInset
        self.sliderLineWidth = sliderLineWidth
    }
}

public struct SlidingPickerView<SelectionValue>: View where SelectionValue: Hashable {

    // MARK: - Constants
    private let pickerCoordinateSpaceName = "Picker"

    // MARK: - Properties
    private let settings: SlidingPickerSettings
    private let allValues: [SelectionValue]
    private let displayContentBuilder: (SelectionValue) -> AnyView

    // MARK: - State
    @Binding private var selectedValue: SelectionValue
    @State private var contentSize = CGSize.zero
    @State private var buttonFrames = [Int: CGRect]()
    @State private var highlightSize = CGSize.zero
    @State private var highlightOffset = CGFloat.zero
    @State private var animationsEnabled = false

    /// Designated Initializer
    ///
    public init(settings: SlidingPickerSettings, allValues: [SelectionValue], selectedValue: Binding<SelectionValue>, displayContentBuilder: @escaping (SelectionValue) -> AnyView) {
        self.settings = settings
        self.allValues = allValues
        self._selectedValue = selectedValue
        self.displayContentBuilder = displayContentBuilder
    }

    public var body: some View {
        ZStack {
            // Background + Outer Border
            RoundedRectangle(cornerRadius: settings.cornerRadius)
                .fill(settings.backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: settings.cornerRadius)
                        .stroke(settings.borderColor)
                )
                .frame(width: contentSize.width)

            // Slider
            RoundedRectangle(cornerRadius: settings.cornerRadius)
                .fill(settings.selectionBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: settings.cornerRadius)
                        .inset(by: -2 * settings.sliderInset)
                        .stroke(settings.selectionBorderColor, lineWidth: settings.sliderLineWidth)
                )
                .offset(x: highlightOffset)
                .frame(width: highlightSize.width, height: highlightSize.height)
                .animation(sliderAnimation, value: highlightOffset)

            // Content
            HStack(spacing: settings.elementsPadding) {
                ForEach(Array(allValues.enumerated()), id: \.element) { index, appearance in
                    displayContentBuilder(appearance)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedValue = appearance
                        }
                        .readFrame(coordinateSpace: .named(pickerCoordinateSpaceName)) { frame in
                            buttonFrames[index] = frame
                        }

                    if let dividerSize = settings.dividerSize, mustDrawDivider(atIndex: index) {
                        Divider()
                            .frame(width: dividerSize.width, height: dividerSize.height)
                            .opacity(opacityForDivider(atIndex: index))
                            .animation(.easeInOut(duration: 0.2), value: selectedValue)
                    }
                }
            }
            .coordinateSpace(name: pickerCoordinateSpaceName)
            .readFrame(coordinateSpace: .local) { frame in
                contentSize = frame.size
                refreshHighlight()
            }
            .onChange(of: selectedValue) { _ in
                refreshHighlight()
            }
            .onChange(of: buttonFrames) { _ in
                refreshHighlight()
            }
        }
    }
}

// MARK: - Private API(s)
//
private extension SlidingPickerView {

    var selectedIndex: Int {
        allValues.firstIndex(of: selectedValue) ?? 0
    }

    var sliderAnimation: Animation? {
        animationsEnabled ? .spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0) : .none
    }

    func mustDrawDivider(atIndex index: Int) -> Bool {
        index < allValues.count - 1
    }

    func refreshHighlight() {
        guard let buttonFrame = buttonFrames[selectedIndex] else {
            return
        }

        // Note: Avoid animating from Zero Size -> Actual Size
        animationsEnabled = highlightSize != .zero

        // Note: Our Highlight with Zero Offset appears at the center of the ZStack
        highlightOffset = buttonFrame.minX - (contentSize.width - buttonFrame.width) * 0.5

        let sliderInset = settings.sliderInset
        highlightSize = CGSize(
            width: buttonFrame.width + sliderInset * 2,
            height: buttonFrame.height + sliderInset * 2
        )
    }

    func opacityForDivider(atIndex index: Int) -> CGFloat {
        let selectedIndex = selectedIndex
        let shouldSkipDivider = [selectedIndex, selectedIndex - 1].contains(index)

        return shouldSkipDivider ? .zero : 1
    }
}
