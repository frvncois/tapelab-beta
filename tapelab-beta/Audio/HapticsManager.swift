//
//  HapticsManager.swift
//  tapelab-beta
//
//  Centralized haptic feedback management for the app
//

import UIKit

/// Centralized haptics manager that provides semantic haptic feedback throughout the app.
/// Uses three types of feedback generators:
/// - UIImpactFeedbackGenerator: Tactile impacts (light/medium/heavy) for physical interactions
/// - UISelectionFeedbackGenerator: Discrete selection changes (e.g., switching tracks, toggling effects)
/// - UINotificationFeedbackGenerator: Success/warning/error states (e.g., recording start/stop, tuner in-tune)
public final class HapticsManager {

    // MARK: - Singleton

    public static let shared = HapticsManager()

    // MARK: - Feedback Generators

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    private init() {
        // Keep all generators prepared for low latency
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Transport Controls

    /// Called when play button is pressed
    public func playPressed() {
        impactMedium.impactOccurred(intensity: 0.7)
        impactMedium.prepare()
    }

    /// Called when stop button is pressed
    public func stopPressed() {
        impactMedium.impactOccurred(intensity: 0.5)
        impactMedium.prepare()
    }

    /// Called when recording starts
    public func recordStart() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Called when recording stops
    public func recordStop() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    // MARK: - Timeline/Playhead Interactions

    /// Called when a track is selected
    public func trackSelected() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Called when a region is moved
    public func regionMoved() {
        impactLight.impactOccurred(intensity: 0.3)
        impactLight.prepare()
    }

    /// Called when a region snaps to grid/beat
    public func regionSnapped() {
        impactMedium.impactOccurred(intensity: 0.6)
        impactMedium.prepare()
    }

    /// Called when playhead drag gesture starts
    public func playheadDragStart() {
        impactLight.impactOccurred(intensity: 0.4)
        impactLight.prepare()
    }

    /// Called periodically while dragging playhead (every ~100ms)
    public func playheadDragging() {
        impactLight.impactOccurred(intensity: 0.1)
        impactLight.prepare()
    }

    /// Called when playhead drag gesture ends
    public func playheadDragEnd() {
        impactMedium.impactOccurred(intensity: 0.5)
        impactMedium.prepare()
    }

    /// Called on each scrub tick during rewind/forward (rate-limited to ~50-100ms)
    public func scrubTick() {
        impactLight.impactOccurred(intensity: 0.15)
        impactLight.prepare()
    }

    // MARK: - Tuner

    /// Called when tuner reaches "in tune" state
    public func tunerInTune() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Called when tuner frequency is close to target
    public func tunerClose() {
        impactLight.impactOccurred(intensity: 0.4)
        impactLight.prepare()
    }

    // MARK: - Effects

    /// Called when an effect is toggled on/off
    public func effectToggled() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Called when an effect slider is adjusted
    public func sliderAdjusted() {
        impactLight.impactOccurred(intensity: 0.2)
        impactLight.prepare()
    }

    // MARK: - Errors

    /// Called when an error occurs
    public func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
