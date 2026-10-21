//
//  DaxCharacterView.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import ConcurrencyExtensions
import Lottie

/// Dax, alive: his eyes follow a target, he blinks, breathes, turns to face the cursor, hops, waves,
/// ponders with a wing at his chin, flaps for joy, takes the odd stroll, loves being petted and dozes off
/// when the Mac is left alone.
@MainActor
final class DaxCharacterView: NSView {

    enum Mood: Equatable {
        case idle
        /// Watching the prompt being typed.
        case listening
        /// Waiting for Duck.ai to take the prompt.
        case thinking
    }

    nonisolated static let bodyHeight: CGFloat = 120
    nonisolated static var preferredSize: NSSize {
        let scale = bodyHeight / DaxRig.bodyRect.height
        return NSSize(width: DaxRig.bodyRect.width * scale, height: bodyHeight)
    }

    /// How long the Mac sits untouched before Dax dozes off.
    nonisolated static let sleepDelay: TimeInterval = 180

    var mood: Mood = .idle {
        didSet {
            guard mood != oldValue else { return }
            lastTypingTime = nil
            if mood == .thinking {
                raiseWingToChin()
            } else if oldValue == .thinking {
                lowerWingFromChin()
            }
        }
    }

    /// Wing at his chin, mulling it over.
    private(set) var isPondering = false
    /// Flapping for joy.
    var isCelebrating: Bool { flapStartTime != nil }

    /// Off for a little walk, and back.
    var isStrolling: Bool { stroll != nil }
    /// A stroll ended, back where he started or wherever it was cut short.
    var onStrollEnded: (() -> Void)?

    private(set) var isAsleep = false {
        didSet { if isAsleep != oldValue { onSleepChange?(isAsleep) } }
    }
    var onSleepChange: ((Bool) -> Void)?

    /// Being stroked by the cursor going back and forth over him.
    private(set) var isBeingPetted = false
    /// A good, long pet.
    var onLovedPetting: (() -> Void)?

    private(set) var isBeingDragged = false
    /// How far he leans against the direction he's carried in, in radians.
    private(set) var dragTilt: CGFloat = 0

    /// How close he stands to the side of his screen: -1 hard against the left edge, 1 against the right.
    private(set) var wallProximity: CGFloat = 0

    /// Where Dax looks, in screen coordinates. `nil` lets the cursor lead.
    var lookTarget: NSPoint?

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDrop: ((NSPasteboard) -> Void)?

    /// Something Dax could take is being dragged over him.
    private(set) var isAnticipatingDrop = false
    var onDragEnded: (() -> Void)?

    private let rig: DaxRig?
    private let animationView: LottieAnimationView?
    /// Read by the Lottie value-provider blocks on every render.
    private let face = Face()
    private let reduceMotion: () -> Bool
    private let idleTime: () -> TimeInterval
    private let mouseLocation: () -> NSPoint

    private var tick: Timer?
    private var time: TimeInterval = 0
    private var nextBlinkTime: TimeInterval = 2
    private var blinkStartTime: TimeInterval?
    private var bounceStartTime: TimeInterval?
    private var facingLeft = false
    private var flip: CGFloat = 1
    private var lastMouseLocation = NSPoint.zero
    private var lastMouseMoveTime: TimeInterval = 0
    private var wanderTarget = CGPoint.zero
    private var nextWanderTime: TimeInterval = 0
    private var isPlayingGesture = false
    private var lastWaveTime: TimeInterval = -.infinity
    /// 0 wide awake, 1 fast asleep.
    private var drowsiness: CGFloat = 0
    private var wideEyesStartTime: TimeInterval?
    private var wideEyesDuration: TimeInterval = 0.5
    private var blinkDuration: TimeInterval = 0.2
    private var nodStartTime: TimeInterval?
    private var lastTypingTime: TimeInterval?
    private var breathPhase: CGFloat = 0
    /// Builds up with each stroke and fades when the cursor rests or leaves.
    private var petting: CGFloat = 0
    private var pettingStartTime: TimeInterval?
    private var lastLovedPettingTime: TimeInterval = -.infinity
    private var lastPettingMouseLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var lastDragOrigin: NSPoint?
    private var landingStartTime: TimeInterval?
    private var flapStartTime: TimeInterval?
    private var stroll: Stroll?
    private var nextStrollTime: TimeInterval = .random(in: DaxCharacterView.strollInterval)
    private var stepPhase: CGFloat = 0

    private struct Stroll {
        enum Leg { case out, pause, back }
        let start: NSPoint
        let distance: CGFloat
        var leg = Leg.out
        var travelled: CGFloat = 0
        var pauseStartTime: TimeInterval?
    }

    init(rig: DaxRig? = DaxRig(),
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         idleTime: @escaping () -> TimeInterval = DaxCharacterView.systemIdleTime,
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.rig = rig
        self.reduceMotion = reduceMotion
        self.idleTime = idleTime
        self.mouseLocation = mouseLocation
        self.animationView = rig.map {
            LottieAnimationView(animation: $0.animation,
                                configuration: LottieConfiguration(renderingEngine: .mainThread))
        }
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        setUpAnimationView()
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.preferredSize }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            tick?.invalidate()
            tick = nil
        } else if tick == nil {
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeMainThread { self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)
            tick = timer
        }
    }

    override func layout() {
        super.layout()
        layoutAnimationView()
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Dragging Dax moves his window; a plain click is his.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
            return
        }
        beginDrag()
        window?.dragOrClick { [weak self] in self?.onClick?() }
        endDrag()
        onDragEnded?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    // MARK: - Drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !DaxPetDroppedItem.items(from: sender.draggingPasteboard).isEmpty else { return [] }
        anticipateDrop()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isAnticipatingDrop ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isAnticipatingDrop = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isAnticipatingDrop = false
        onDrop?(sender.draggingPasteboard)
        return true
    }

    /// Ooh, what's that?
    func anticipateDrop() {
        isAnticipatingDrop = true
        bounce()
    }

    /// He's picked up: from here on, his window moving means he's being carried.
    func beginDrag() {
        isBeingDragged = true
        dragStartOrigin = window?.frame.origin
        lastDragOrigin = dragStartOrigin
    }

    /// Put down: only a real move ends in a landing.
    func endDrag() {
        defer {
            isBeingDragged = false
            dragStartOrigin = nil
            lastDragOrigin = nil
        }
        guard isBeingDragged, let start = dragStartOrigin, let origin = window?.frame.origin, origin != start else { return }
        guard !reduceMotion() else { return }
        landingStartTime = time
        hop()
    }

    // MARK: - Gestures

    func hop() {
        guard !reduceMotion() else { return }
        play(DaxRig.Frames.hop.lowerBound, to: DaxRig.Frames.hop.upperBound, speed: 1.2)
    }

    func wave() {
        guard !reduceMotion(), !isPlayingGesture, !isPondering, time - lastWaveTime > 4 else { return }
        lastWaveTime = time
        isPlayingGesture = true
        animationView?.animationSpeed = 1
        animationView?.play(fromFrame: DaxRig.Frames.wave.lowerBound, toFrame: DaxRig.Frames.wave.upperBound, loopMode: .playOnce) { [weak self] finished in
            // Interrupted by another gesture, which now owns the playback.
            guard finished else { return }
            self?.play(DaxRig.Frames.wave.upperBound, to: DaxRig.Frames.wave.lowerBound, speed: 1.6)
        }
    }

    // MARK: - Poses

    /// A joyful flap of the wings, with a hop.
    func celebrate() {
        hop()
        flapWings()
    }

    private func flapWings() {
        guard !reduceMotion() else { return }
        flapStartTime = time
    }

    /// Hand to chin: the wave is played as far as the raised wing, and held there.
    private func raiseWingToChin() {
        guard !reduceMotion(), let animationView else { return }
        isPondering = true
        isPlayingGesture = true
        animationView.animationSpeed = 1
        animationView.play(fromFrame: DaxRig.Frames.idle, toFrame: DaxRig.Frames.wingUp, loopMode: .playOnce) { [weak self] finished in
            guard finished else { return }
            self?.isPlayingGesture = false
        }
    }

    private func lowerWingFromChin() {
        guard isPondering else { return }
        isPondering = false
        play(DaxRig.Frames.wingUp, to: DaxRig.Frames.idle, speed: 1.6)
    }

    // MARK: - Strolls

    /// How long he stands around between strolls.
    nonisolated static let strollInterval: ClosedRange<TimeInterval> = 45...120
    nonisolated static let strollSpeed: CGFloat = 28

    /// Walks `distance` points along the floor (negative is left), looks around, and walks back.
    func stroll(by distance: CGFloat) {
        guard !reduceMotion(), let origin = window?.frame.origin, distance != 0 else { return }
        stroll = Stroll(start: origin, distance: distance)
        turn(left: distance < 0)
    }

    private var canStroll: Bool {
        mood == .idle && !isAsleep && drowsiness < 0.1 && !isBeingDragged && !isBeingPetted && !isAnticipatingDrop
    }

    private func updateStroll() {
        guard var current = stroll else {
            if time >= nextStrollTime {
                nextStrollTime = time + .random(in: Self.strollInterval)
                if canStroll, let distance = strollDistance() { stroll(by: distance) }
            }
            stepPhase = 0
            return
        }
        guard canStroll, let window else {
            endStroll()
            return
        }

        switch current.leg {
        case .out, .back:
            current.travelled = min(current.travelled + Self.strollSpeed / 30, abs(current.distance))
            stepPhase += 2 * .pi * 2.2 / 30
            // Placed from the start each time: windows snap to pixels, and the rounding would add up.
            let offset = current.leg == .out ? current.travelled : abs(current.distance) - current.travelled
            window.setFrameOrigin(NSPoint(x: current.start.x + offset * (current.distance > 0 ? 1 : -1), y: current.start.y))
            if current.leg == .back, current.travelled >= abs(current.distance) {
                stroll = current
                endStroll()
                return
            }
            if current.travelled >= abs(current.distance) {
                current.leg = .pause
                current.pauseStartTime = time
                stepPhase = 0
            }
        case .pause:
            if let start = current.pauseStartTime, time - start >= 1.5 {
                current.leg = .back
                current.travelled = 0
                turn(left: current.distance > 0)
            }
        }
        stroll = current
    }

    private func endStroll() {
        stroll = nil
        stepPhase = 0
        onStrollEnded?()
    }

    /// A few steps towards the roomier side, if there's room for them on his screen.
    private func strollDistance() -> CGFloat? {
        guard let window, let screen = window.screen?.visibleFrame else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        let roomLeft = frame.minX - screen.minX - Self.wallDistance
        let roomRight = screen.maxX - frame.maxX - Self.wallDistance
        let room = max(roomLeft, roomRight)
        guard room >= 30 else { return nil }
        let distance = min(room, .random(in: 40...90))
        return roomRight >= roomLeft ? distance : -distance
    }

    // MARK: - Typing

    var isNodding: Bool { nodStartTime != nil }
    var isSlowBlinking: Bool { blinkStartTime != nil && blinkDuration > 0.2 }
    var isMarveling: Bool { wideEyesStartTime != nil }

    /// Pause this long mid-prompt and he gives a slow, patient blink.
    nonisolated static let typingPause: TimeInterval = 1.5

    /// Something was typed for him to read.
    func noticeTyping() {
        lastTypingTime = time
    }

    /// A word went by: a little nod of understanding.
    func nod() {
        guard !reduceMotion() else { return }
        nodStartTime = time
    }

    /// That's a lot to take in.
    func marvel() {
        widenEyes(for: 0.9)
    }

    private func widenEyes(for duration: TimeInterval) {
        wideEyesDuration = duration
        wideEyesStartTime = time
    }

    /// A small bounce.
    func bounce() {
        guard !reduceMotion() else { return }
        bounceStartTime = time
    }

    private func play(_ from: AnimationFrameTime, to: AnimationFrameTime, speed: CGFloat) {
        isPlayingGesture = true
        animationView?.animationSpeed = speed
        animationView?.play(fromFrame: from, toFrame: to, loopMode: .playOnce) { [weak self] finished in
            guard finished else { return }
            self?.isPlayingGesture = false
            self?.animationView?.currentFrame = DaxRig.Frames.idle
        }
    }

    // MARK: - Setup

    private func setUpAnimationView() {
        guard let rig, let animationView else { return }
        animationView.contentMode = .scaleToFill
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.currentFrame = DaxRig.Frames.idle
        addSubview(animationView)

        let face = self.face
        animationView.setValueProvider(FloatValueProvider { frame in
            rig.raisedWingRotation(at: frame) + face.raisedWingTilt
        }, keypath: DaxRig.raisedWingRotationKeypath)
        animationView.setValueProvider(PointValueProvider(DaxRig.backWingShoulder), keypath: DaxRig.backWingAnchorKeypath)
        animationView.setValueProvider(PointValueProvider(CGPoint(x: rig.backWingPosition.x + DaxRig.backWingShoulder.x,
                                                                  y: rig.backWingPosition.y + DaxRig.backWingShoulder.y)),
                                       keypath: DaxRig.backWingPositionKeypath)
        animationView.setValueProvider(FloatValueProvider { _ in face.backWingLift }, keypath: DaxRig.backWingRotationKeypath)
        animationView.setValueProvider(FloatValueProvider { frame in
            rig.hairRotation(at: frame) + face.hairDroop
        }, keypath: DaxRig.hairRotationKeypath)
        for (layers, isLeft) in [(DaxRig.leftFootLayers, true), (DaxRig.rightFootLayers, false)] {
            for name in layers {
                guard let base = rig.footPositions[name] else { continue }
                animationView.setValueProvider(PointValueProvider { _ in
                    CGPoint(x: base.x, y: base.y - (isLeft ? face.leftFootLift : face.rightFootLift))
                }, keypath: AnimationKeypath(keypath: "\(name).Transform.Position"))
            }
        }

        animationView.setValueProvider(PointValueProvider(DaxRig.eyesPivot), keypath: DaxRig.eyesAnchorKeypath)
        animationView.setValueProvider(PointValueProvider { frame in
            let base = rig.eyesPosition(at: frame)
            return CGPoint(x: base.x + DaxRig.eyesPivot.x + face.eyeOffset.x,
                           y: base.y + DaxRig.eyesPivot.y + face.eyeOffset.y)
        }, keypath: DaxRig.eyesKeypath)
        animationView.setValueProvider(SizeValueProvider { _ in
            CGSize(width: 100, height: 100 - 90 * face.eyelids)
        }, keypath: DaxRig.eyesScaleKeypath)
    }

    /// The canvas is larger than Dax, so it's scaled and offset for `DaxRig.bodyRect` to fill the view.
    private func layoutAnimationView() {
        guard let rig, let animationView else { return }
        let scale = bounds.height / DaxRig.bodyRect.height
        animationView.frame = NSRect(x: -DaxRig.bodyRect.minX * scale,
                                     y: -(rig.canvasSize.height - DaxRig.bodyRect.maxY) * scale,
                                     width: rig.canvasSize.width * scale,
                                     height: rig.canvasSize.height * scale)
    }

    // MARK: - Frame loop

    /// Advances Dax by one frame; driven by a 30 fps timer while he's on screen.
    func step() {
        time += 1 / 30
        let previousFace = face.snapshot

        updateSleep()
        updatePetting()
        updateDrag()
        updateWallProximity()
        updateStroll()
        updateEyes()
        updateEyelids()
        updatePose()
        updateBody()

        if face.snapshot != previousFace, animationView?.isAnimationPlaying == false {
            animationView?.forceDisplayUpdate()
        }
    }

    private func updateEyes() {
        let mouse = mouseLocation()
        if mouse != lastMouseLocation {
            lastMouseLocation = mouse
            lastMouseMoveTime = time
        }

        let target: CGPoint
        switch mood {
        case _ where isAsleep:
            target = CGPoint(x: 0, y: -0.4)
        case _ where isBeingDragged:
            // Peering down at the drop.
            target = CGPoint(x: 0, y: -0.7)
        case _ where isBeingPetted:
            // Blissfully up.
            target = CGPoint(x: 0, y: 0.5)
        case .thinking:
            // Up and away, pondering.
            target = CGPoint(x: -0.6, y: 0.9)
        case _ where stroll != nil && mood == .idle:
            // Where he's headed, or a look around at the far end.
            if stroll?.leg == .pause {
                target = wander()
            } else {
                target = CGPoint(x: facingLeft ? -0.6 : 0.6, y: -0.1)
            }
        case .listening, .idle:
            if let point = lookTarget ?? cursorTargetIfRecent() {
                target = direction(towards: point)
            } else if abs(wallProximity) > 0.5 {
                // Nothing to look at but the wall, so he turns his back to it.
                target = CGPoint(x: wallProximity > 0 ? -0.8 : 0.8, y: wander().y)
            } else {
                target = wander()
            }
        }

        // Face whichever side the action is on, with some hysteresis so he doesn't flicker.
        if mood != .thinking, !isAsleep, !isBeingPetted, !isBeingDragged {
            if target.x < -0.55, !facingLeft { turn(left: true) }
            if target.x > 0.55, facingLeft { turn(left: false) }
        }

        var nodDip: CGFloat = 0
        if let start = nodStartTime {
            let progress = (time - start) / 0.3
            if progress >= 1 { nodStartTime = nil } else { nodDip = sin(progress * .pi) * 6 }
        }

        let maxOffset = CGSize(width: 13, height: 15)
        let desired = CGPoint(x: target.x * flip * maxOffset.width, y: -target.y * maxOffset.height + nodDip)
        face.eyeOffset.x += (desired.x - face.eyeOffset.x) * 0.3
        face.eyeOffset.y += (desired.y - face.eyeOffset.y) * 0.3
    }

    /// Unit-ish vector from Dax's eyes to `point`, saturating ~250pt away.
    private func direction(towards point: NSPoint) -> CGPoint {
        guard let window else { return .zero }
        let scale = bounds.height / DaxRig.bodyRect.height
        var eyes = NSPoint(x: (DaxRig.eyesCenter.x - DaxRig.bodyRect.minX) * scale,
                           y: bounds.height - (DaxRig.eyesCenter.y - DaxRig.bodyRect.minY) * scale)
        if facingLeft { eyes.x = bounds.width - eyes.x }
        let eyesOnScreen = window.convertPoint(toScreen: convert(eyes, to: nil))
        let delta = CGPoint(x: point.x - eyesOnScreen.x, y: point.y - eyesOnScreen.y)
        let distance = hypot(delta.x, delta.y)
        guard distance > 1 else { return .zero }
        let strength = min(distance / 250, 1)
        return CGPoint(x: delta.x / distance * strength, y: delta.y / distance * strength)
    }

    private func cursorTargetIfRecent() -> NSPoint? {
        time - lastMouseMoveTime < 6 ? lastMouseLocation : nil
    }

    /// With the cursor resting, Dax glances around on his own.
    private func wander() -> CGPoint {
        if time >= nextWanderTime {
            wanderTarget = Bool.random() ? .zero : CGPoint(x: .random(in: -0.8...0.8), y: .random(in: -0.6...0.6))
            nextWanderTime = time + .random(in: 1.5...4)
        }
        return wanderTarget
    }

    // MARK: - Sleep

    /// Seconds since the last keyboard, mouse or trackpad input anywhere on the Mac.
    nonisolated static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
    }

    private func updateSleep() {
        let idle = idleTime()
        if isAsleep, idle < 1 || mood != .idle {
            wakeUp()
        } else if !isAsleep, mood == .idle, idle >= Self.sleepDelay {
            isAsleep = true
        }

        // His eyes grow heavy in the last half minute, then he slowly nods off; waking is instant.
        let target: CGFloat = isAsleep ? 1 : (mood == .idle && idle >= Self.sleepDelay - 30 ? 0.5 : 0)
        drowsiness += (target - drowsiness) * (target > drowsiness ? 0.03 : 1)
    }

    private func wakeUp() {
        isAsleep = false
        drowsiness = 0
        blinkStartTime = nil
        guard !reduceMotion() else { return }
        widenEyes(for: 0.5)
        hop()
    }

    // MARK: - Petting

    nonisolated static let lovedPettingDuration: TimeInterval = 2

    private func updatePetting() {
        let mouse = mouseLocation()
        defer { lastPettingMouseLocation = mouse }
        // While he's carried, the cursor moves with him.
        if let window, let last = lastPettingMouseLocation, !isBeingDragged {
            let frameOnScreen = window.convertToScreen(convert(bounds, to: nil))
            if frameOnScreen.contains(mouse) {
                petting = min(petting + abs(mouse.x - last.x) / 150, 2)
            }
        }
        petting = max(petting - 0.6 / 30, 0)

        // Hysteresis, so a pause between strokes doesn't break the spell.
        if !isBeingPetted, petting > 0.6 {
            isBeingPetted = true
            pettingStartTime = time
        } else if isBeingPetted, petting < 0.2 {
            isBeingPetted = false
            pettingStartTime = nil
        }

        if let start = pettingStartTime, time - start >= Self.lovedPettingDuration, time - lastLovedPettingTime > 3 {
            lastLovedPettingTime = time
            flapWings()
            onLovedPetting?()
        }
    }

    // MARK: - Dragging

    private func updateDrag() {
        var desiredTilt: CGFloat = 0
        if isBeingDragged, let origin = window?.frame.origin, let last = lastDragOrigin {
            // Points per frame; his top trails behind as he's swung around.
            desiredTilt = max(-0.3, min(0.3, (origin.x - last.x) / 60))
            lastDragOrigin = origin
        }
        dragTilt += (desiredTilt - dragTilt) * (isBeingDragged ? 0.25 : 0.15)
    }

    // MARK: - Screen edges

    nonisolated static let wallDistance: CGFloat = 40

    private func updateWallProximity() {
        guard let window, let screen = window.screen?.visibleFrame else {
            wallProximity = 0
            return
        }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        let left = max(0, 1 - (frame.minX - screen.minX) / Self.wallDistance)
        let right = max(0, 1 - (screen.maxX - frame.maxX) / Self.wallDistance)
        wallProximity = min(right, 1) - min(left, 1)
    }

    private func updateEyelids() {
        if let start = wideEyesStartTime {
            // Eyes wide with surprise.
            let progress = (time - start) / wideEyesDuration
            if progress >= 1 {
                wideEyesStartTime = nil
            } else {
                face.eyelids = -0.25 * sin(progress * .pi)
                return
            }
        }
        if isBeingDragged || isAnticipatingDrop {
            // Whoa!
            face.eyelids = -0.25
            return
        }
        if isBeingPetted {
            // A happy squint.
            face.eyelids = 0.6
            return
        }
        let droop = drowsiness * 0.95
        if isAsleep || droop > 0.4 {
            face.eyelids = droop
            return
        }
        if blinkStartTime == nil, mood == .listening, let typed = lastTypingTime, time - typed >= Self.typingPause {
            // Waiting patiently for the rest of the prompt; once per pause.
            lastTypingTime = nil
            blinkDuration = 0.7
            blinkStartTime = time
            nextBlinkTime = time + .random(in: 2.5...6)
        }
        if blinkStartTime == nil, time >= nextBlinkTime {
            blinkDuration = 0.2
            blinkStartTime = time
            // Now and then, a double blink.
            nextBlinkTime = time + (Int.random(in: 0..<5) == 0 ? 0.35 : .random(in: 2.5...6))
        }
        guard let start = blinkStartTime else {
            face.eyelids = max(mood == .thinking ? 0.35 : 0, droop)
            return
        }
        let progress = (time - start) / blinkDuration
        if progress >= 1 {
            blinkStartTime = nil
            face.eyelids = droop
        } else {
            face.eyelids = max(sin(progress * .pi), droop)
        }
    }

    private func updatePose() {
        // Wing to chin once it's up beside his face.
        let wingUp = isPondering && !isPlayingGesture
        face.raisedWingTilt += ((wingUp ? -30 : 0) - face.raisedWingTilt) * 0.2

        var lift: CGFloat = 0
        if let start = flapStartTime {
            let progress = (time - start) / 1.2
            if progress >= 1 {
                flapStartTime = nil
            } else {
                lift = sin(progress * .pi) * (25 + 20 * sin(progress * 2 * .pi * 6))
            }
        }
        face.backWingLift = lift

        // His tuft flops over as he dozes.
        face.hairDroop = -35 * drowsiness

        let stride = max(0, sin(stepPhase)), otherStride = max(0, -sin(stepPhase))
        face.leftFootLift = stride * 30
        face.rightFootLift = otherStride * 30
    }

    private func updateBody() {
        guard let layer else { return }
        let motion = !reduceMotion()

        // Breaths slow and deepen as he falls asleep.
        breathPhase += 2 * .pi / (3.2 + 2 * drowsiness) / 30
        let breathing = motion ? sin(breathPhase) * (0.012 + 0.01 * drowsiness) : 0
        var bounceHeight: CGFloat = 0
        if let start = bounceStartTime {
            let progress = (time - start) / 0.25
            if progress >= 1 { bounceStartTime = nil } else { bounceHeight = sin(progress * .pi) * 4 }
        }
        var sway = motion && mood == .thinking ? sin(time * 2 * .pi / 1.6) * (isPondering ? 0.03 : 0.06) : 0
        // A waddle: rocking from foot to foot, bobbing with each step.
        if stepPhase != 0 {
            sway += sin(stepPhase) * 0.05
            bounceHeight += abs(sin(stepPhase)) * 2
        }
        if motion, isBeingPetted {
            sway += sin(time * 2 * .pi / 0.45) * 0.05 * min(petting, 1)
        }

        flip += ((facingLeft ? -1 : 1) - flip) * 0.35

        // Pivot at Dax's feet, centred.
        // Squashed flat on landing, springing back up.
        var squash: CGFloat = 0
        if let start = landingStartTime {
            let progress = (time - start) / 0.3
            if progress >= 1 { landingStartTime = nil } else { squash = sin(progress * .pi) * 0.14 }
        }
        // Leaning away from a nearby wall.
        let tilt = motion ? dragTilt + wallProximity * 0.06 : 0

        let pivot = CGPoint(x: bounds.midX, y: 0)
        var transform = CATransform3DMakeTranslation(pivot.x, pivot.y + bounceHeight, 0)
        transform = CATransform3DRotate(transform, sway + tilt, 0, 0, 1)
        transform = CATransform3DScale(transform, flip * (1 + squash * 0.6), 1 + breathing - squash, 1)
        transform = CATransform3DTranslate(transform, -pivot.x, -pivot.y, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = transform
        CATransaction.commit()
    }

    private func turn(left: Bool) {
        facingLeft = left
        // While listening he only turns his head to the text, without fuss.
        if mood == .idle { bounce() }
    }
}

/// Mutable state shared with Lottie's value-provider blocks.
private final class Face {
    var eyeOffset = CGPoint.zero
    /// 0 open, 1 shut.
    var eyelids: CGFloat = 0
    /// Degrees added to the raised front wing, bringing it to his chin.
    var raisedWingTilt: CGFloat = 0
    /// Degrees the back wing is lifted from the shoulder.
    var backWingLift: CGFloat = 0
    /// Degrees the hair tuft flops over.
    var hairDroop: CGFloat = 0
    /// How far each foot is off the floor.
    var leftFootLift: CGFloat = 0
    var rightFootLift: CGFloat = 0

    var snapshot: [CGFloat] {
        [(eyeOffset.x * 4).rounded(), (eyeOffset.y * 4).rounded(), (eyelids * 20).rounded(),
         raisedWingTilt.rounded(), backWingLift.rounded(), hairDroop.rounded(), leftFootLift.rounded(), rightFootLift.rounded()]
    }
}
