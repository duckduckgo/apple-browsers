//
//  PillSegmentedControl.swift
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
import AppKit

public struct PillSegment: Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let image: Image

    public init(id: Int, title: String, image: Image) {
        self.id = id
        self.title = title
        self.image = image
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
    }

}

public struct PillSegmentedControl: View {
    @Binding var selection: Int
    let segments: [PillSegment]
    @State private var selectionCircleOpacity: Double = 1.0
    @State private var pressedUnderlayIndex: Int?
    @State private var hoveredIndex: Int?
    @State private var hoverFadeOutIndex: Int?
    @State private var hoverFadeOutOpacity: Double = 0

    // Appearance
    let containerBackground: Color
    let selectedForeground: Color
    let unselectedForeground: Color
    let containerBorder: Color
    let selectedIconBackground: Color
    let unselectedIconBackground: Color
    let selectedSegmentFill: Color
    let selectedSegmentStroke: Color
    let selectedSegmentShadowColor: Color
    let selectedSegmentShadowRadius: CGFloat
    let selectedSegmentShadowY: CGFloat
    let selectedSegmentTopStroke: Color
    let hoverSegmentBackground: Color
    let pressedSegmentBackground: Color
    let hoverOverlay: Color

    public init(
        selection: Binding<Int>,
        segments: [PillSegment],
        containerBackground: Color,
        containerBorder: Color,
        selectedForeground: Color,
        unselectedForeground: Color,
        selectedIconBackground: Color,
        unselectedIconBackground: Color = .clear,
        selectedSegmentFill: Color,
        selectedSegmentStroke: Color,
        selectedSegmentShadowColor: Color,
        selectedSegmentShadowRadius: CGFloat = 6,
        selectedSegmentShadowY: CGFloat = 2,
        selectedSegmentTopStroke: Color = .clear,
        hoverSegmentBackground: Color,
        pressedSegmentBackground: Color,
        hoverOverlay: Color
    ) {
        _selection = selection
        self.segments = segments
        self.containerBackground = containerBackground
        self.selectedForeground = selectedForeground
        self.unselectedForeground = unselectedForeground
        self.containerBorder = containerBorder
        self.selectedIconBackground = selectedIconBackground
        self.unselectedIconBackground = unselectedIconBackground
        self.selectedSegmentFill = selectedSegmentFill
        self.selectedSegmentStroke = selectedSegmentStroke
        self.selectedSegmentShadowColor = selectedSegmentShadowColor
        self.selectedSegmentShadowRadius = selectedSegmentShadowRadius
        self.selectedSegmentShadowY = selectedSegmentShadowY
        self.selectedSegmentTopStroke = selectedSegmentTopStroke
        self.hoverSegmentBackground = hoverSegmentBackground
        self.pressedSegmentBackground = pressedSegmentBackground
        self.hoverOverlay = hoverOverlay
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(containerBackground)

            // Separators underlay (placed below selection and content)
            GeometryReader { proxy in
                let count = max(1, segments.count)
                let step = proxy.size.width / CGFloat(count)
                ZStack {
                    ForEach(1..<count, id: \.self) { i in
                        Rectangle()
                            .fill(containerBorder)
                            .frame(width: 1, height: 40)
                            .position(x: CGFloat(i) * step, y: proxy.size.height / 2)
                    }
                }
                .allowsHitTesting(false)
            }

            GeometryReader { geo in
                let count = max(1, segments.count)
                let segmentWidth = geo.size.width / CGFloat(count)
                let selectedIndex = segments.firstIndex(where: { $0.id == selection }) ?? 0
                let separatorThickness: CGFloat = 1
                // Cover adjacent separators symmetrically by 1pt each side
                let extraLeft: CGFloat = selectedIndex > 0 ? separatorThickness : 0
                let extraRight: CGFloat = selectedIndex < count - 1 ? separatorThickness : 0
                let selectedWidth = max(0, segmentWidth + extraLeft + extraRight)
                let xOffset = CGFloat(selectedIndex) * segmentWidth - extraLeft
                // Compensate selection pill's separator overhang so the circle stays centered under the icon
                let circleCenterOffset: CGFloat = -((extraRight - extraLeft) * 2)

                // Hover underlay: fixed per segment, no slide; fades out on mouse-out
                if let hover = hoveredIndex, pressedUnderlayIndex == nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hoverSegmentBackground)
                        .padding(2)
                        .frame(width: max(0, segmentWidth), height: geo.size.height)
                        .offset(x: CGFloat(hover) * segmentWidth)
                        .allowsHitTesting(false)
                }

                if let fading = hoverFadeOutIndex {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hoverSegmentBackground)
                        .padding(2)
                        .frame(width: max(0, segmentWidth), height: geo.size.height)
                        .offset(x: CGFloat(fading) * segmentWidth)
                        .opacity(hoverFadeOutOpacity)
                        .allowsHitTesting(false)
                }

                // Pressed underlay remains static at press index
                if let idx = pressedUnderlayIndex {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pressedSegmentBackground)
                        .padding(2)
                        .frame(width: max(0, segmentWidth), height: geo.size.height)
                        .offset(x: CGFloat(idx) * segmentWidth)
                        .allowsHitTesting(false)
                }

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedSegmentFill)
                        .shadow(color: selectedSegmentShadowColor, radius: selectedSegmentShadowRadius, x: 0, y: selectedSegmentShadowY)
                    // Top gradient stroke
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [selectedSegmentTopStroke, selectedSegmentTopStroke.opacity(0)]),
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                        .frame(height: 22) // drawing from top to the center (11px high)

                    // Traveling selection circle behind the icon
                    Circle()
                        .fill(selectedIconBackground)
                        .frame(width: 40, height: 40)
                        .padding(.top, 11)
                        .offset(x: circleCenterOffset)
                        .opacity(selectionCircleOpacity)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selectedSegmentStroke, lineWidth: 1)
                }
                .padding(.init(top: 2,
                                leading: selectedIndex == 0 ? 2 : 0,
                                bottom: 2,
                                trailing: selectedIndex == count - 1 ? 2 : 0))
                .frame(width: selectedWidth, height: geo.size.height)
                .offset(x: xOffset)
                .animation(.easeInOut(duration: 0.2), value: selectedIndex)
                .allowsHitTesting(false)
                .onChange(of: selectedIndex) { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        selectionCircleOpacity = 0.5
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeIn(duration: 0.1)) {
                            selectionCircleOpacity = 1.0
                        }
                    }
                    if let idx = pressedUnderlayIndex, idx == selectedIndex {
                        // Remove underlay once selection pill arrives; fade handled by being covered
                        pressedUnderlayIndex = nil
                    }
                }

                // Per-segment overlays are drawn inside each segment; no global hover/press overlay here
            }

            // Content + separators are drawn below the selection background by layering order
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    PillSegmentItemView(
                        segment: segment,
                        isSelected: selection == segment.id,
                        selectedForeground: selectedForeground,
                        unselectedForeground: unselectedForeground,
                        hoverBackground: hoverSegmentBackground,
                        hoverOverlay: hoverOverlay,
                        onTap: { selection = segment.id },
                        onPressChanged: { isPressed in
                            if isPressed {
                                pressedUnderlayIndex = index
                            } else {
                                pressedUnderlayIndex = nil
                            }
                        },
                        onHoverChanged: { isHovering in
                            if isHovering {
                                // begin new hover instantly
                                hoveredIndex = index
                            } else if hoveredIndex == index {
                                // fade out previous hover in place
                                hoverFadeOutIndex = index
                                hoverFadeOutOpacity = 1
                                hoveredIndex = nil
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoverFadeOutOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    hoverFadeOutIndex = nil
                                }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Separators are drawn in the underlay above
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(containerBorder, lineWidth: 1)
                .padding(1)
        }
    }
}

// MARK: - Helpers

private struct PressReportingButtonStyle: ButtonStyle {
    let onChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .onChange(of: configuration.isPressed) { newValue in
                onChange(newValue)
            }
    }
}

private struct PillSegmentItemView: View {
    let segment: PillSegment
    let isSelected: Bool
    let selectedForeground: Color
    let unselectedForeground: Color
    let hoverBackground: Color
    let hoverOverlay: Color
    let onTap: () -> Void
    let onPressChanged: (Bool) -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false
    @State private var pointerUnitPoint: UnitPoint = .center
    @State private var lastSize: CGSize = .zero

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hoverBackground)
                    .padding(2)
                    .opacity((isHovering && !isSelected && !isPressed) ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isHovering)

                // Material-like gradient that follows pointer (appears for both selected and unselected)
                GeometryReader { proxy in
                    RadialGradient(
                        gradient: Gradient(colors: [hoverOverlay.opacity(0.9), hoverOverlay.opacity(0.0)]),
                        center: pointerUnitPoint,
                        startRadius: 0,
                        endRadius: min(proxy.size.width, proxy.size.height) * 0.8
                    )
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
                    .onAppear { lastSize = proxy.size }
                    .onChange(of: proxy.size) { newSize in
                        lastSize = newSize
                    }
                }
                .mask(RoundedRectangle(cornerRadius: 10, style: .continuous).padding(2))
                .allowsHitTesting(false)

                VStack(spacing: 5) {
                    ZStack(alignment: .center) {
                        segment.image
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 24, height: 24)
                            .foregroundColor(isSelected ? selectedForeground : unselectedForeground)
                            .padding(8)
                    }

                    Text(segment.title)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? selectedForeground : unselectedForeground)
                }
            }
        }
        .buttonStyle(PressReportingButtonStyle { pressed in
            isPressed = pressed
            onPressChanged(pressed)
        })
        .onHover { hovering in
            onHoverChanged(hovering)
            if hovering {
                isHovering = true
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = false
                }
            }
        }
        // Track mouse position within the segment to drive the gradient center
        .background(MousePositionReader { point, size in
            guard let point else { return }
            let x = max(0, min(1, point.x / max(1, size.width)))
            let yNorm = max(0, min(1, point.y / max(1, size.height)))
            let y = 1 - yNorm
            pointerUnitPoint = UnitPoint(x: x, y: y)
        })
    }
}

// MARK: - Mouse tracking helper

private struct MousePositionReader: NSViewRepresentable {
    typealias NSViewType = TrackingNSView

    let onUpdate: (_ location: CGPoint?, _ size: CGSize) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onUpdate = onUpdate
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onUpdate = onUpdate
    }
}

private final class TrackingNSView: NSView {
    var onUpdate: ((_ location: CGPoint?, _ size: CGSize) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onUpdate?(point, bounds.size)
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onUpdate?(point, bounds.size)
    }

    override func mouseExited(with event: NSEvent) {
        onUpdate?(nil, bounds.size)
    }
}
