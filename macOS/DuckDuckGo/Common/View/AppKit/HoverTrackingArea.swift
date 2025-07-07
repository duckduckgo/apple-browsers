//
//  HoverTrackingArea.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import os.log

/// Used in `MouseOverView` and `MouseOverButton` to automatically manage `isMouseOver` state and update layer when needed
final class HoverTrackingArea: NSTrackingArea {

    static func updateTrackingAreas(in view: NSView & Hoverable) {
        for trackingArea in view.trackingAreas where trackingArea is HoverTrackingArea {
            view.removeTrackingArea(trackingArea)
        }
        let trackingArea = HoverTrackingArea(owner: view)
        view.addTrackingArea(trackingArea)

        view.isMouseOver = view.isMouseLocationInsideBounds()
        trackingArea.updateLayer(animated: false)
    }

    // mouseEntered and mouseExited events will be received by the HoverTrackingArea itself
    override var owner: AnyObject? {
        self
    }

    fileprivate weak var view: Hoverable? {
        super.owner as? Hoverable
    }

    private var currentBackgroundColor: NSColor? {
        guard let view else { return nil }

        if (view as? NSControl)?.isEnabled == false {
            return nil
        } else if view.isMouseDown {
            return view.mouseDownColor ?? view.mouseOverColor ?? view.backgroundColor
        } else if view.isMouseOver {
            return view.mouseOverColor ?? view.backgroundColor
        } else {
            return view.backgroundColor
        }
    }

    private var observers: [NSKeyValueObservation]?
    private var lastEventTimestamp: TimeInterval = 0

    private static let mouseExitedSelector = NSStringFromSelector(#selector(NSResponder.mouseExited))
    private static let swizzleMouseExitedOnce: Void = {
        guard let originalMethod = class_getInstanceMethod(NSTrackingArea.self, NSSelectorFromString("_" + mouseExitedSelector)),
            let swizzledMethod = class_getInstanceMethod(NSTrackingArea.self, #selector(swizzled_mouseExited(_:))) else {
            assertionFailure("Failed to swizzle _mouseExited:")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    init(owner: some Hoverable) {
        super.init(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: owner, userInfo: nil)
       _=Self.swizzleMouseExitedOnce

        observers = [
            owner.observe(\.backgroundColor) { [weak self] _, _ in self?.updateLayer() },
            owner.observe(\.mouseOverColor) { [weak self] _, _ in self?.updateLayer() },
            owner.observe(\.mouseDownColor) { [weak self] _, _ in self?.updateLayer() },
            owner.observe(\.cornerRadius) { [weak self] _, _ in self?.updateLayer() },
            owner.observe(\.backgroundInset) { [weak self] _, _ in self?.updateLayer() },
            (owner as? NSControl)?.observe(\.isEnabled) { [weak self] _, _ in self?.updateLayer(animated: false) },
            owner.observe(\.isMouseDown) { [weak self] _, _ in self?.mouseDownDidChange() },
            owner.observe(\.isMouseOver, options: .new) { [weak self] _, c in self?.updateLayer(animated: !(c.newValue /* isMouseOver */ ?? false)) },
            owner.observe(\.window) { [weak self] _, _ in self?.viewWindowDidChange() },
        ].compactMap { $0 }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func layer(createIfNeeded: Bool) -> CALayer? {
        view?.backgroundLayer(createIfNeeded: createIfNeeded)
    }

    func updateLayer(animated: Bool = !CATransaction.disableActions()) {
        let color = currentBackgroundColor ?? .clear
        guard let view, let layer = layer(createIfNeeded: color != .clear) else { return }

        layer.cornerRadius = view.cornerRadius
        layer.frame = view.bounds.insetBy(dx: view.backgroundInset.x, dy: view.backgroundInset.y)

        NSAppearance.withAppAppearance {
            NSAnimationContext.runAnimationGroup { context in
                context.allowsImplicitAnimation = true
                // mousedown/over state should be applied instantly
                // animation should be also disabled on view reuse
                if !animated || view.isMouseDown || view.isMouseOver {
                    layer.removeAllAnimations()
                    context.duration = 0.0
                }

                layer.backgroundColor = color.cgColor
            }
        }
    }

    /// Fixes the issue where the mouseExited event is dispatched before the mouseEntered event, and the mouseOver state is stuck
    /// the fix is done by dispatching a new mouseExited if the mouseEntered event has a timestamp older than the last event timestamp.
    /// The second part of the fix is done by swizzling the `_mouseExited:` method.
    /// https://app.asana.com/1/137249556945/project/1199230911884351/task/1208347387296425?focus=true
    private func checkLastEventTimestamp(_ event: NSEvent) {
        // if the mouseEntered event has a timestamp older than the last event timestamp, it means it's a delayed event
        guard self.lastEventTimestamp > event.timestamp else { return }

        let description = String(format: "<HoverTrackingArea %p: %@>", self, self.view?.description ?? "<nil>")
        Logger.general.error("\(description): received delayed mouseEntered event after mouseExited: \(event.eventDescription)")

        DispatchQueue.main.async { [weak self] in
            self?.sendMouseExited(event)
        }
    }

    private func sendMouseExited(_ event: NSEvent) {
        guard let newEvent = NSEvent.enterExitEvent(with: .mouseExited,
                                                    location: view?.window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow,
                                                    modifierFlags: event.modifierFlags,
                                                    timestamp: event.timestamp,
                                                    windowNumber: event.windowNumber,
                                                    context: nil,
                                                    eventNumber: event.eventNumber,
                                                    trackingNumber: [.mouseEntered, .mouseExited].contains(event.type) ? event.trackingNumber : 0,
                                                    userData: nil) else {
            assertionFailure("Failed to create new mouse exited event")
            return
        }
        self.mouseExited(newEvent)
    }

    @objc func mouseEntered(_ event: NSEvent) {
        checkLastEventTimestamp(event)

        view?.isMouseOver = true
        view?.mouseEntered(with: event)
        self.lastEventTimestamp = event.timestamp
    }

    @objc func mouseMoved(_ event: NSEvent) {
        checkLastEventTimestamp(event)

        if let view, !view.isMouseOver {
            view.isMouseOver = true
        }
        view?.mouseMoved(with: event)
        self.lastEventTimestamp = event.timestamp
    }

    @objc func mouseExited(_ event: NSEvent) {
        view?.isMouseOver = false
        view?.mouseExited(with: event)
        self.lastEventTimestamp = event.timestamp
    }

    private func mouseDownDidChange() {
        guard let view else { return }

        if view.isMouseOver,
           view.window?.isKeyWindow != true || view.isMouseLocationInsideBounds() != true,
           let event = NSApp.currentEvent {

            mouseExited(event)
        } else {
            // mouse-down: non-animated
            // mouse-up: animated when mouse is outside
            updateLayer(animated: !view.isMouseDown && !view.isMouseLocationInsideBounds())
        }
    }

    private func viewWindowDidChange() {
        guard let view else { return }
        view.isMouseOver = view.isMouseLocationInsideBounds()
        updateLayer(animated: false)
    }

}

extension NSTrackingArea {
    /// The second part of the fix for the mouse hover state stuck issue (see above)
    /// If the mouseExited event is dispatched before the mouseEntered event, the NSTrackingArea won‘t call the mouseExited method
    /// here we force the call of the mouseExited method and when we receive the delayed mouseEntered event later,
    /// we will detect that it‘s a delayed event by comparing the event timestamp and fix the mouse hover state
    /// see `checkLastEventTimestamp`
    /// https://app.asana.com/1/137249556945/project/1199230911884351/task/1208347387296425?focus=true
    @objc dynamic fileprivate func swizzled_mouseExited(_ event: NSEvent) {
        self.swizzled_mouseExited(event) // call original method
        if let hoverTrackingArea = self as? HoverTrackingArea,
            hoverTrackingArea.view?.isMouseOver == true {
            hoverTrackingArea.mouseExited(event)
        }
    }
}

@objc protocol HoverableProperties {

    @objc dynamic var backgroundColor: NSColor? { get }

    @objc dynamic var mouseOverColor: NSColor? { get }

    @objc dynamic var mouseDownColor: NSColor? { get }

    @objc dynamic var cornerRadius: CGFloat { get }

    @objc dynamic var backgroundInset: NSPoint { get }

    @objc dynamic var isMouseDown: Bool { get }

    @objc dynamic var isMouseOver: Bool { get set }

}

protocol Hoverable: NSView, HoverableProperties {

    func backgroundLayer(createIfNeeded: Bool) -> CALayer?

}
