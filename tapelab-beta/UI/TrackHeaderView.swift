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
    @State private var showDeleteConfirmation = false
    @State private var showCutAlert = false
    @State private var cutAlertMessage = ""

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
                // Armed indicator dot + Track number label (tappable to arm)
                HStack(spacing: 8) {
                    Circle()
                        .fill(isArmed ? Color.tapelabRed : Color.tapelabAccentFull)
                        .frame(width: 6, height: 6)

                    Text("Track \(trackNumber)")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticsManager.shared.trackSelected()
                    armedTrack = trackNumber
                }

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
        .alert(
            "Delete Region",
            isPresented: $showDeleteConfirmation,
            presenting: selectedRegionIndex
        ) { regionIndex in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // Clear selection FIRST to avoid index out of bounds when UI re-renders
                runtime.timeline.selectedRegion = nil
                // Then delete the region
                runtime.deleteRegion(trackIndex: trackNumber - 1, regionIndex: regionIndex)
            }
        } message: { regionIndex in
            Text("Are you sure you want to delete \"Region \(regionIndex + 1)\"? This action cannot be undone.")
        }
        .alert(
            "Cannot Cut Region",
            isPresented: $showCutAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cutAlertMessage)
        }
    }

    // MARK: - Button Groups

    private var normalModeButtons: some View {
        HStack(spacing: 8) {
            // FX Button with indicator dot
            Button(action: {
                showFXSheet = true
            }) {
                HStack(spacing: 4) {
                    if track.fx.hasFXModified() {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                    }
                    Text("FX")
                        .font(.tapelabMonoTiny)
                }
                .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // VOL Button with indicator dot
            Button(action: {
                showVOLSheet = true
            }) {
                HStack(spacing: 4) {
                    if track.fx.hasVolumeModified() {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                    }
                    Text("VOL")
                        .font(.tapelabMonoTiny)
                }
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
            // CUT Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                let result = runtime.cutRegion(trackIndex: trackNumber - 1, regionIndex: regionIndex)
                if !result.success, let errorMessage = result.errorMessage {
                    cutAlertMessage = errorMessage
                    showCutAlert = true
                }
            }) {
                Text("CUT")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle())

            // DUPLICATE Button
            Button(action: {
                guard let regionIndex = selectedRegionIndex else { return }
                // Clear selection first, then duplicate
                runtime.timeline.selectedRegion = nil
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
                let _ = selectedRegionIndex.map { track.regions[$0].reversed } ?? false
                Text("REV")
                    .font(.tapelabMonoTiny)
                    .frame(width: 40, height: 20)
            }
            .buttonStyle(TapelabButtonStyle(isActive: selectedRegionIndex.map { track.regions[$0].reversed } ?? false))

            // DELETE Button
            Button(action: {
                guard selectedRegionIndex != nil else { return }
                showDeleteConfirmation = true
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
