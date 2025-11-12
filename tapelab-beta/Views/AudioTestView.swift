//
//  AudioTestView.swift
//  tapelab-beta
//
//  Created by Francois Lemieux on 5/11/25.
//

import SwiftUI
import Combine
import AVFAudio

struct AudioTestView: View {
    @StateObject private var runtime = AudioRuntime()
    @State private var selectedTrack: Int = 0
    @State private var expandedFXTrack: Int? = nil
    @State private var showSessionView = false
    @State private var selectedTab: DashboardView.Tab = .sessions

    var body: some View {
        NavigationStack {
            contentView
                .navigationDestination(isPresented: $showSessionView) {
                    SessionView(runtime: runtime, selectedTab: $selectedTab)
                }
        }
    }

    private var contentView: some View {
        ZStack {
            ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        Text("🎙️ TAPELAB AUDIO TEST")
                            .font(.title2)
                            .fontWeight(.bold)

                        Divider()

                        // Navigation to SessionView
                        Button(action: { showSessionView = true }) {
                            Label("Open Session View", systemImage: "waveform")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .padding(.horizontal)

                        Divider()

                        // Track Selector (for recording only)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Record on Track:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Track", selection: $selectedTrack) {
                                ForEach(0..<4) { track in
                                    Text("Track \(track + 1)").tag(track)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal)

                        // Transport Controls (Session-level)
                        VStack(spacing: 16) {
                            Text("SESSION TRANSPORT")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            // Playback Controls
                            HStack(spacing: 12) {
                                // Rewind
                                Button(action: { runtime.timeline.seek(to: 0) }) {
                                    Image(systemName: "backward.end.fill")
                                        .font(.title3)
                                        .frame(width: 50, height: 44)
                                }
                                .buttonStyle(.bordered)

                                // Play
                                Button(action: { Task { await runtime.startPlayback() } }) {
                                    Label("Play", systemImage: "play.circle.fill")
                                        .font(.title2)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(runtime.timeline.isPlaying || runtime.timeline.isRecording)

                                // Stop
                                Button(action: { runtime.stopPlayback(resetPlayhead: true) }) {
                                    Label("Stop", systemImage: "stop.circle.fill")
                                        .font(.title2)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!runtime.timeline.isPlaying)

                                // Forward (skip to end)
                                Button(action: {
                                    let maxDuration = runtime.session.tracks.flatMap { $0.regions }.map { $0.startTime + $0.duration }.max() ?? 0
                                    runtime.timeline.seek(to: maxDuration)
                                }) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.title3)
                                        .frame(width: 50, height: 44)
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()

                            // Recording Controls
                            HStack(spacing: 12) {
                                Button(action: { Task { await runtime.startRecording(onTrack: selectedTrack) } }) {
                                    Label("Record", systemImage: "circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(runtime.timeline.isRecording)

                                Button(action: { runtime.stopRecording(onTrack: selectedTrack) }) {
                                    Label("Stop Rec", systemImage: "stop.fill")
                                        .font(.title2)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .disabled(!runtime.timeline.isRecording)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        Divider()

                        // Recording Meter (only shown when recording)
                        if runtime.timeline.isRecording {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Input Level")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(String(format: "%.1f dB", 20 * log10(max(0.0001, runtime.recorder.inputLevel))))
                                        .font(.caption)
                                        .monospacedDigit()
                                }

                                // Level meter
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background
                                        Rectangle()
                                            .fill(Color(.systemGray5))
                                            .frame(height: 20)
                                            .cornerRadius(4)

                                        // Level bar
                                        Rectangle()
                                            .fill(
                                                runtime.recorder.inputLevel > 0.8 ? Color.red :
                                                runtime.recorder.inputLevel > 0.6 ? Color.orange :
                                                Color.green
                                            )
                                            .frame(width: geometry.size.width * CGFloat(min(1.0, runtime.recorder.inputLevel)), height: 20)
                                            .cornerRadius(4)
                                            .animation(.linear(duration: 0.05), value: runtime.recorder.inputLevel)
                                    }
                                }
                                .frame(height: 20)

                                HStack {
                                    Text("Duration:")
                                        .font(.caption)
                                    Spacer()
                                    Text(String(format: "%.1f s", runtime.recorder.recordingDuration))
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Session Info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Playhead:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(String(format: "%.2f s", runtime.timeline.playhead))
                                    .monospacedDigit()
                            }

                            HStack {
                                Text("Status:")
                                    .fontWeight(.semibold)
                                Spacer()
                                if runtime.timeline.isPlaying {
                                    Text("▶️ Playing")
                                        .foregroundColor(.green)
                                } else if runtime.timeline.isRecording {
                                    Text("⏺️ Recording Track \(selectedTrack + 1)")
                                        .foregroundColor(.red)
                                } else {
                                    Text("⏸️ Stopped")
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()

                            // Per-track region counts
                            ForEach(0..<4) { trackIndex in
                                HStack {
                                    Text("Track \(trackIndex + 1):")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(runtime.session.tracks[trackIndex].regions.count) region\(runtime.session.tracks[trackIndex].regions.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundColor(trackIndex == selectedTrack ? .blue : .secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

            // Loop Controls (Session-level)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Loop Mode (Session)", isOn: $runtime.timeline.isLoopMode)
                    .fontWeight(.semibold)

                if runtime.timeline.isLoopMode {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Loop Start (s)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0.0", value: $runtime.timeline.loopStart, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Loop End (s)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("10.0", value: $runtime.timeline.loopEnd, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                        }
                    }

                    Text("Loops entire session between start and end times")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Track FX Controls
            VStack(spacing: 12) {
                Text("TRACK FX")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(0..<4) { trackIndex in
                    TrackFXView(
                        track: $runtime.session.tracks[trackIndex],
                        isExpanded: Binding(
                            get: { expandedFXTrack == trackIndex },
                            set: { isExpanded in
                                expandedFXTrack = isExpanded ? trackIndex : nil
                            }
                        ),
                        onUpdate: {
                            // Apply FX changes in real-time if playing
                            if runtime.timeline.isPlaying {
                                runtime.engine.trackBuses[trackIndex].applyFX(runtime.session.tracks[trackIndex].fx)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)

            // Regions Debug Section
            VStack(spacing: 12) {
                Text("RECORDED REGIONS (DEBUG)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(0..<4) { trackIndex in
                    let track = runtime.session.tracks[trackIndex]
                    if !track.regions.isEmpty {
                        ForEach(track.regions.indices, id: \.self) { regionIndex in
                            RegionDebugView(
                                region: $runtime.session.tracks[trackIndex].regions[regionIndex],
                                trackNumber: track.number,
                                regionIndex: regionIndex,
                                onConfirm: {
                                    print("🔧 Region confirmed - refreshing playback")
                                    
                                    let wasPlaying = runtime.timeline.isPlaying
                                    print("   📊 State: wasPlaying=\(wasPlaying)")
                                    
                                    // Just stop the high-level player/timeline
                                    // Let SessionPlayer.play() handle the node reset
                                    if wasPlaying {
                                        runtime.player.stop()
                                        runtime.timeline.stopTimeline()
                                        print("   ⏸️ Stopped playback")
                                    }
                                    
                                    // Restart - SessionPlayer.play() will handle node reset properly
                                    if wasPlaying {
                                        Task { @MainActor in
                                            do {
                                                print("   🚀 Restarting playback...")
                                                try await runtime.player.play(
                                                    session: runtime.session,
                                                    timeline: runtime.timeline
                                                )
                                                print("   ✅ Playback restarted")
                                            } catch {
                                                print("   ⚠️ Failed: \(error)")
                                            }
                                        }
                                    } else {
                                        print("   ℹ️ Was not playing - changes will apply on next Play")
                                    }
                                    
                                    runtime.objectWillChange.send()
                                    print("   ✅ Region update complete")
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)

            // Debug Info
            VStack(alignment: .leading, spacing: 8) {
                Text("🔊 Session: \(runtime.session.name)")
                    .font(.caption)
                Text("🎚️ Sample Rate: \(Int(runtime.engine.sampleRate)) Hz")
                    .font(.caption)
                Text("📊 Tracks: \(runtime.session.tracks.count)")
                    .font(.caption)

                Divider()

                // Audio Diagnostics Button
                Button(action: {
                    runtime.engine.diagnoseAudioIssues()
                }) {
                    Label("Run Audio Diagnostics", systemImage: "waveform.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Text("Check console for diagnostic output")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
                    }
                }
                .disabled(runtime.isProcessing) // Disable all interactions when processing

                // Processing Overlay
                if runtime.isProcessing {
                ZStack {
                    // Semi-transparent black background
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()

                    // Processing indicator card
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        Text(runtime.processingMessage)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Please wait...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(40)
                    .background(Color(.systemGray).opacity(0.9))
                    .cornerRadius(20)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: runtime.isProcessing)
                }
            }
        }
    }
}

// MARK: - Track FX View
struct TrackFXView: View {
    @Binding var track: Track
    @Binding var isExpanded: Bool
    let onUpdate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("Track \(track.number)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(track.regions.count) region\(track.regions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            // FX Controls (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Volume & Pan
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MIX")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Volume")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.1f dB", track.fx.volumeDB))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { track.fx.volumeDB },
                            set: { newValue in
                                track.fx.volumeDB = newValue
                                onUpdate()
                            }
                        ), in: -40...12, step: 0.5)

                        HStack {
                            Text("Pan")
                                .font(.caption)
                            Spacer()
                            Text(track.fx.pan < 0 ? String(format: "L%.0f", abs(track.fx.pan) * 100) :
                                 track.fx.pan > 0 ? String(format: "R%.0f", track.fx.pan * 100) :
                                 "C")
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.pan) },
                            set: { newValue in
                                track.fx.pan = Float(newValue)
                                onUpdate()
                            }
                        ), in: -1...1, step: 0.1)
                    }

                    Divider()

                    // Reverb
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REVERB")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.reverb.wetMix))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.reverb.wetMix) },
                            set: { newValue in
                                track.fx.reverb.wetMix = Float(newValue)
                                onUpdate()
                            }
                        ), in: 0...100, step: 1)

                        Toggle("Large Hall", isOn: Binding(
                            get: { track.fx.reverb.roomSize },
                            set: { newValue in
                                track.fx.reverb.roomSize = newValue
                                onUpdate()
                            }
                        ))
                        .font(.caption)
                    }

                    Divider()

                    // Delay
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DELAY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.delay.wetMix))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.delay.wetMix) },
                            set: { newValue in
                                track.fx.delay.wetMix = Float(newValue)
                                onUpdate()
                            }
                        ), in: 0...100, step: 1)

                        HStack {
                            Text("Time")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.2f s", track.fx.delay.time))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { track.fx.delay.time },
                            set: { newValue in
                                track.fx.delay.time = newValue
                                onUpdate()
                            }
                        ), in: 0.01...2.0, step: 0.01)

                        HStack {
                            Text("Feedback")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.delay.feedback))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.delay.feedback) },
                            set: { newValue in
                                track.fx.delay.feedback = Float(newValue)
                                onUpdate()
                            }
                        ), in: 0...100, step: 1)
                    }

                    Divider()

                    // Saturation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SATURATION")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.saturation.wetMix))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.saturation.wetMix) },
                            set: { newValue in
                                track.fx.saturation.wetMix = Float(newValue)
                                onUpdate()
                            }
                        ), in: 0...100, step: 1)

                        HStack {
                            Text("Drive")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.1f dB", track.fx.saturation.preGain))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.saturation.preGain) },
                            set: { newValue in
                                track.fx.saturation.preGain = Float(newValue)
                                onUpdate()
                            }
                        ), in: -40...40, step: 0.5)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
        }
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }
}

// MARK: - Region Debug View

struct RegionDebugView: View {
    @Binding var region: Region
    let trackNumber: Int
    let regionIndex: Int
    let onConfirm: () -> Void
    
    @State private var isExpanded: Bool = false
    
    // Local editing state
    @State private var editingStartTime: Double
    @State private var editingDuration: Double
    @State private var editingFileStartOffset: Double
    @State private var hasUnsavedChanges: Bool = false
    
    init(region: Binding<Region>, trackNumber: Int, regionIndex: Int, onConfirm: @escaping () -> Void) {
        self._region = region
        self.trackNumber = trackNumber
        self.regionIndex = regionIndex
        self.onConfirm = onConfirm
        
        self._editingStartTime = State(initialValue: region.wrappedValue.startTime)
        self._editingDuration = State(initialValue: region.wrappedValue.duration)
        self._editingFileStartOffset = State(initialValue: region.wrappedValue.fileStartOffset)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("Track \(trackNumber) • Region \(regionIndex + 1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if hasUnsavedChanges {
                        Text("•")
                            .foregroundColor(.orange)
                        Text("Modified")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    Text(region.sourceURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(hasUnsavedChanges ? Color(.systemOrange).opacity(0.1) : Color(.systemGray5))
                .cornerRadius(8)
            }

            // Region Details (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // File Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FILE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Text(region.sourceURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }

                    Divider()

                    // Start Time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Start Time (timeline)")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.3f s", editingStartTime))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        TextField("Start Time", value: $editingStartTime, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .onChange(of: editingStartTime) { _, _ in
                                checkForChanges()
                            }
                    }

                    // Duration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duration")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.3f s", editingDuration))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        TextField("Duration", value: $editingDuration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .onChange(of: editingDuration) { _, _ in
                                checkForChanges()
                            }
                    }

                    // File Start Offset
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("File Start Offset")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.3f s", editingFileStartOffset))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        TextField("File Start Offset", value: $editingFileStartOffset, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .onChange(of: editingFileStartOffset) { _, _ in
                                checkForChanges()
                            }
                    }

                    Divider()

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            cancelChanges()
                        }) {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Cancel")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasUnsavedChanges)
                        
                        Button(action: {
                            applyChanges()
                        }) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("Apply")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUnsavedChanges)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
        }
    }
    
    private func checkForChanges() {
        hasUnsavedChanges = (
            editingStartTime != region.startTime ||
            editingDuration != region.duration ||
            editingFileStartOffset != region.fileStartOffset
        )
    }
    
    private func cancelChanges() {
        editingStartTime = region.startTime
        editingDuration = region.duration
        editingFileStartOffset = region.fileStartOffset
        hasUnsavedChanges = false
        print("🔄 Changes cancelled")
    }
    
    private func applyChanges() {
        let oldStartTime = region.startTime
        let oldDuration = region.duration
        let oldFileStartOffset = region.fileStartOffset
        
        region.startTime = editingStartTime
        region.duration = editingDuration
        region.fileStartOffset = editingFileStartOffset
        
        hasUnsavedChanges = false
        
        print("✅ Applied changes:")
        print("   StartTime: \(oldStartTime) → \(region.startTime)")
        print("   Duration: \(oldDuration) → \(region.duration)")
        print("   FileStartOffset: \(oldFileStartOffset) → \(region.fileStartOffset)")
        
        onConfirm()
    }
}
