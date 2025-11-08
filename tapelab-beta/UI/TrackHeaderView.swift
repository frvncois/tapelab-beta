//
//  TrackHeaderView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TrackHeaderView: View {
    let trackNumber: Int
    @Binding var armedTrack: Int
    @Binding var track: Track
    let runtime: AudioRuntime
    @State private var showFXSheet = false
    @State private var showVOLSheet = false

    private var trackColor: Color {
        switch trackNumber {
        case 1: return Color.blue
        case 2: return Color.green
        case 3: return Color.orange
        case 4: return Color.purple
        default: return Color.gray
        }
    }

    private var isArmed: Bool {
        armedTrack == trackNumber
    }

    private var isEditMode: Bool {
        if let selected = runtime.timeline.selectedRegion {
            return selected.trackIndex == (trackNumber - 1)
        }
        return false
    }

    private var selectedRegionIndex: Int? {
        if let selected = runtime.timeline.selectedRegion, selected.trackIndex == (trackNumber - 1) {
            return selected.regionIndex
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top border - very light
            Rectangle()
                .fill(Color.tapelabLight.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 8) {
                // Armed indicator dot
                Circle()
                    .fill(isArmed ? Color.tapelabRed : Color.tapelabAccentFull)
                    .frame(width: 6, height: 6)

                // Track number label
                Text("Track \(trackNumber)")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)

                Spacer()

                // Action buttons - aligned to the right
                if isEditMode {
                    // Edit mode buttons
                    editModeButtons
                        .transition(.opacity.combined(with: .scale))
                } else {
                    // Normal mode buttons
                    normalModeButtons
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Bottom border - very light
            Rectangle()
                .fill(Color.tapelabLight.opacity(0.1))
                .frame(height: 1)
        }
        .background(Color.tapelabBackground)
        .animation(.easeInOut(duration: 0.2), value: isEditMode)
        .sheet(isPresented: $showFXSheet) {
            FXSheetView(track: $track, runtime: runtime)
        }
        .sheet(isPresented: $showVOLSheet) {
            VOLSheetView(track: $track, runtime: runtime)
        }
    }

    // MARK: - Button Groups

    private var normalModeButtons: some View {
        HStack(spacing: 8) {
            // FX Button
            Button(action: {
                showFXSheet = true
            }) {
                Text("FX")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // VOL Button
            Button(action: {
                showVOLSheet = true
            }) {
                Text("VOL")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // ARM Button (Record arm)
            Button(action: {
                HapticsManager.shared.trackSelected()
                armedTrack = trackNumber
            }) {
                Text("ARM")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle(isActive: isArmed, isArmButton: true))
        }
    }

    private var editModeButtons: some View {
        HStack(spacing: 8) {
            // TRIM Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                runtime.enterTrimMode(trackIndex: trackNumber - 1, regionIndex: regionIndex)
            }) {
                Text("TRIM")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // DUPLICATE Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                // Clear selection first, then duplicate
                runtime.timeline.selectedRegion = nil
                runtime.timeline.trimModeRegion = nil
                runtime.duplicateRegion(trackIndex: trackNumber - 1, regionIndex: regionIndex)
            }) {
                Text("DUP")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // REVERSE Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                runtime.toggleReverse(trackIndex: trackNumber - 1, regionIndex: regionIndex)
            }) {
                let isReversed = selectedRegionIndex.map { track.regions[$0].reversed } ?? false
                Text("REV")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // DELETE Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                // Clear selection FIRST to avoid index out of bounds when UI re-renders
                runtime.timeline.selectedRegion = nil
                runtime.timeline.trimModeRegion = nil
                // Then delete the region
                runtime.deleteRegion(trackIndex: trackNumber - 1, regionIndex: regionIndex)
            }) {
                Text("DEL")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())
        }
    }
}

// MARK: - Preview
struct TrackHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        let runtime = AudioRuntime()
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { trackNumber in
                TrackHeaderView(
                    trackNumber: trackNumber,
                    armedTrack: .constant(1),
                    track: .constant(runtime.session.tracks[trackNumber - 1]),
                    runtime: runtime
                )
            }
        }
        .previewLayout(.sizeThatFits)
    }
}
