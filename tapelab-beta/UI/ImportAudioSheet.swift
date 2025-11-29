//
//  ImportAudioSheet.swift
//  tapelab-beta
//
//  Audio import sheet with crop, preview, and track selection
//

import SwiftUI
@preconcurrency import AVFAudio
import UniformTypeIdentifiers
import Combine

struct ImportAudioSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: Session
    let playheadPosition: TimeInterval
    let runtime: AudioRuntime

    let sourceFileURL: URL

    @State private var audioFile: AVAudioFile?
    @State private var audioBuffer: AVAudioPCMBuffer?
    @State private var fileDuration: TimeInterval = 0
    @State private var waveformSamples: [Float] = []

    // Crop controls - enabled by default
    @State private var cropEnabled: Bool = true
    @State private var cropStartTime: TimeInterval = 0
    @State private var cropEndTime: TimeInterval = 0
    @State private var cropDuration: TimeInterval = 0

    // Track selection
    @State private var selectedTrackIndex: Int = 0

    // Preview playback
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?
    @State private var currentPlaybackTime: TimeInterval = 0

    // Loading state
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private let maxImportDuration: TimeInterval = 360.0 // 6 minutes

    init(session: Binding<Session>, playheadPosition: TimeInterval, runtime: AudioRuntime, sourceFileURL: URL) {
        self._session = session
        self.playheadPosition = playheadPosition
        self.runtime = runtime
        self.sourceFileURL = sourceFileURL

    }

    var body: some View {
        ZStack {
            TapelabTheme.Colors.background
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else {
                mainContentView
            }
        }
        .onAppear {
            loadAudioFile()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            LoadingAnimationView()
            Text("Loading audio file...")
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.tapelabRed)

            Text("Error Loading Audio")
                .font(.tapelabMonoBold)
                .foregroundColor(.tapelabLight)

            Text(message)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(TapelabPrimaryButtonStyle())
        }
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Waveform display with integrated crop controls
                        waveformView

                        // Track selection
                        trackSelectionView

                        Spacer()

                        // Action buttons
                        actionButtonsView
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Import Audio")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.tapelabAccentFull)
                    }
                }
            }
        }
    }

    // MARK: - File Info

    private var fileInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FILE INFO")
                .font(.tapelabMonoTiny)
                .foregroundColor(.tapelabAccentFull.opacity(0.7))

            HStack {
                Text("Duration:")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight.opacity(0.7))
                Spacer()
                Text(formatTime(fileDuration))
                    .font(.tapelabMono)
                    .foregroundColor(.tapelabLight)
                    .monospacedDigit()
            }

            if fileDuration > maxImportDuration {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.tapelabRed)
                    Text("File exceeds 6 minute limit. Please crop the audio.")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabRed)
                }
                .padding(8)
                .background(Color.tapelabRed.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(TapelabTheme.Colors.surface)
        .cornerRadius(8)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Waveform with toggleable crop handles
            ZStack(alignment: .leading) {
                // Full waveform
                WaveformView(
                    samples: waveformSamples,
                    color: Color.tapelabLight.opacity(0.7),
                    backgroundColor: Color.tapelabButtonBg.opacity(0.4)
                )
                .frame(height: 120)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.tapelabLight.opacity(0.2), lineWidth: 1)
                )

                // Crop region overlay
                if cropEnabled {
                    let startPercent = cropStartTime / fileDuration
                    let durationPercent = cropDuration / fileDuration

                    GeometryReader { geo in
                        // Dimmed out regions
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: geo.size.width * startPercent)

                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: geo.size.width * (1 - startPercent - durationPercent))
                            .offset(x: geo.size.width * (startPercent + durationPercent))

                        // Active region border
                        Rectangle()
                            .stroke(Color.tapelabOrange, lineWidth: 2)
                            .frame(width: geo.size.width * durationPercent)
                            .offset(x: geo.size.width * startPercent)

                        // Start handle (toggle)
                        Circle()
                            .fill(Color.tapelabOrange)
                            .frame(width: 20, height: 20)
                            .offset(x: (geo.size.width * startPercent) - 10, y: 50)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newStart = max(0, min(cropEndTime - 0.1, (value.location.x / geo.size.width) * fileDuration))
                                        cropStartTime = newStart
                                        updateCropDuration()
                                    }
                            )

                        // End handle (toggle)
                        Circle()
                            .fill(Color.tapelabOrange)
                            .frame(width: 20, height: 20)
                            .offset(x: (geo.size.width * (startPercent + durationPercent)) - 10, y: 50)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newEnd = max(cropStartTime + 0.1, min(fileDuration, (value.location.x / geo.size.width) * fileDuration))
                                        cropEndTime = newEnd
                                        updateCropDuration()
                                    }
                            )
                    }
                }

                // Playback position indicator
                if isPlaying, fileDuration > 0 {
                    GeometryReader { geo in
                        let playbackPercent: Double = {
                            if cropEnabled {
                                let relativeTime = currentPlaybackTime - cropStartTime
                                return (cropStartTime / fileDuration) + (relativeTime / fileDuration)
                            } else {
                                return currentPlaybackTime / fileDuration
                            }
                        }()

                        Rectangle()
                            .fill(Color.tapelabRed)
                            .frame(width: 2)
                            .offset(x: geo.size.width * playbackPercent)
                    }
                }
            }
            .frame(height: 120)

            // Crop controls in a box
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: togglePlayback) {
                        HStack(spacing: 6) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 14))
                            Text(isPlaying ? "STOP PREVIEW" : "PLAY PREVIEW")
                                .font(.tapelabMonoSmall)
                        }
                        .foregroundColor(.tapelabLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.tapelabButtonBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DURATION")
                            .font(.tapelabMonoTiny)
                            .foregroundColor(.tapelabLight.opacity(0.5))
                        Text(formatTime(cropDuration))
                            .font(.tapelabMono)
                            .foregroundColor(cropDuration > maxImportDuration ? .tapelabRed : .tapelabLight)
                            .monospacedDigit()
                    }
                }

                if cropDuration > maxImportDuration {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.tapelabRed)
                        Text("Duration exceeds 6 minute maximum")
                            .font(.tapelabMonoTiny)
                            .foregroundColor(.tapelabRed)
                    }
                    .padding(8)
                    .background(Color.tapelabRed.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(12)
            .background(TapelabTheme.Colors.surface)
            .cornerRadius(8)
        }
    }

    // MARK: - Crop Controls

    private var cropControlsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $cropEnabled) {
                Text("ENABLE CROP")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
            }
            .toggleStyle(SwitchToggleStyle(tint: .tapelabAccentFull))
            .onChange(of: cropEnabled) { _, newValue in
                if newValue {
                    // Initialize crop to full duration (or max 6 minutes)
                    cropStartTime = 0
                    let initialDuration = min(fileDuration, maxImportDuration)
                    cropEndTime = initialDuration
                    cropDuration = initialDuration
                } else {
                    stopPlayback()
                }
            }

            if cropEnabled {
                VStack(spacing: 16) {
                    // Crop start time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crop Start")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))
                            Spacer()
                            Text(formatTime(cropStartTime))
                                .font(.tapelabMono)
                                .foregroundColor(.tapelabLight)
                                .monospacedDigit()
                        }

                        Slider(value: $cropStartTime, in: 0...max(0, cropEndTime - 0.1))
                            .accentColor(.tapelabAccentFull)
                            .onChange(of: cropStartTime) { _, _ in
                                updateCropDuration()
                            }
                    }

                    // Crop end time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crop End")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))
                            Spacer()
                            Text(formatTime(cropEndTime))
                                .font(.tapelabMono)
                                .foregroundColor(.tapelabLight)
                                .monospacedDigit()
                        }

                        Slider(value: $cropEndTime, in: min(fileDuration, cropStartTime + 0.1)...fileDuration)
                            .accentColor(.tapelabAccentFull)
                            .onChange(of: cropEndTime) { _, _ in
                                updateCropDuration()
                            }
                    }

                    // Duration display
                    HStack {
                        Text("Crop Duration:")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabLight.opacity(0.7))
                        Spacer()
                        Text(formatTime(cropDuration))
                            .font(.tapelabMono)
                            .foregroundColor(cropDuration > maxImportDuration ? .tapelabRed : .tapelabLight)
                            .monospacedDigit()
                    }

                    if cropDuration > maxImportDuration {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.tapelabRed)
                            Text("Crop duration exceeds 6 minute maximum")
                                .font(.tapelabMonoTiny)
                                .foregroundColor(.tapelabRed)
                        }
                        .padding(8)
                        .background(Color.tapelabRed.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding()
                .background(TapelabTheme.Colors.surface)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Track Selection

    private var trackSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.tapelabLight)
                    .frame(width: 3, height: 3)

                Text("ADD TO TRACK")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
            }

            // Track selector buttons (LOOP/TEMP style)
            HStack(spacing: 8) {
                ForEach(0..<session.tracks.count, id: \.self) { index in
                    Button(action: {
                        selectedTrackIndex = index
                    }) {
                        Text("Track \(index + 1)")
                            .font(.tapelabMonoTiny)
                            .lineLimit(1)
                            .foregroundColor(selectedTrackIndex == index ? .tapelabBlack : .tapelabLight)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedTrackIndex == index ? Color.tapelabOrange : Color.tapelabButtonBg)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button("CANCEL") {
                dismiss()
            }
            .buttonStyle(TapelabSecondaryButtonStyle())

            Button("IMPORT") {
                importAudio()
            }
            .buttonStyle(TapelabPrimaryButtonStyle())
            .disabled(cropEnabled && cropDuration > maxImportDuration)
        }
    }

    // MARK: - Audio Loading

    private func loadAudioFile() {

        Task.detached(priority: .userInitiated) {
            do {
                // Load audio file
                let file = try AVAudioFile(forReading: sourceFileURL)
                let duration = Double(file.length) / file.processingFormat.sampleRate

                // Read entire file into buffer
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: frameCount
                ) else {
                    await MainActor.run {
                        errorMessage = "Failed to create audio buffer"
                        isLoading = false
                    }
                    return
                }

                try file.read(into: buffer, frameCount: frameCount)
                buffer.frameLength = frameCount

                // Generate waveform
                let waveform = WaveformGenerator.generateWaveformData(from: buffer, targetPoints: 500)

                // Update UI on main thread
                await MainActor.run {
                    audioFile = file
                    audioBuffer = buffer
                    fileDuration = duration
                    waveformSamples = waveform

                    // Always enable crop by default and initialize crop region
                    cropEnabled = true
                    cropStartTime = 0
                    let initialDuration = min(duration, maxImportDuration)
                    cropEndTime = initialDuration
                    cropDuration = initialDuration

                    if duration > maxImportDuration {
                    } else {
                    }

                    isLoading = false
                }

            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load audio file: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard audioFile != nil else { return }

        do {

            // DON'T reconfigure audio session - use the existing playAndRecord session
            // The app's AudioRuntime has already configured it properly
            // Trying to change it causes: Error Domain=NSOSStatusErrorDomain Code=561017449 ('!pri')

            // Create player directly without changing session
            audioPlayer = try AVAudioPlayer(contentsOf: sourceFileURL)
            guard let player = audioPlayer else {
                return
            }


            player.prepareToPlay()

            // Set playback position
            if cropEnabled {
                player.currentTime = cropStartTime
                currentPlaybackTime = cropStartTime
            } else {
                player.currentTime = 0
                currentPlaybackTime = 0
            }

            let success = player.play()
            if !success {
                errorMessage = "Failed to start playback"
                return
            }

            isPlaying = true

            // Start timer to update playback position and stop at crop end
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak player] _ in
                guard let player = player else { return }
                currentPlaybackTime = player.currentTime

                // Stop at crop end if enabled
                if cropEnabled && player.currentTime >= cropEndTime {
                    stopPlayback()
                }

                // Stop at natural end
                if !player.isPlaying {
                    stopPlayback()
                }
            }

        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        currentPlaybackTime = 0
    }

    // MARK: - Import Action

    private func importAudio() {
        guard audioFile != nil else { return }

        stopPlayback()

        Task {
            do {
                // Copy file to session directory
                let targetURL = FileStore.trackDirectory(
                    session: session,
                    track: selectedTrackIndex
                ).appendingPathComponent(
                    "imported_\(UUID().uuidString).caf"
                )

                // If crop is enabled, we need to export the cropped portion
                if cropEnabled {
                    try await exportCroppedAudio(to: targetURL)
                } else {
                    // Convert and copy the full file
                    try await convertAndExportAudio(to: targetURL)
                }

                // Create region
                let actualDuration = cropEnabled ? cropDuration : fileDuration

                let newRegion = Region(
                    sourceURL: targetURL,
                    startTime: playheadPosition,
                    duration: actualDuration,
                    fileStartOffset: 0, // We exported from the start
                    fileDuration: actualDuration
                )

                // Add region to session
                await MainActor.run {
                    session.tracks[selectedTrackIndex].regions.append(newRegion)

                    // Save session
                    do {
                        try FileStore.saveSession(session)

                        // Notify runtime to reload
                        runtime.objectWillChange.send()

                        dismiss()
                    } catch {
                        errorMessage = "Failed to save session: \(error.localizedDescription)"
                    }
                }

            } catch {
                await MainActor.run {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func convertAndExportAudio(to targetURL: URL) async throws {
        guard let file = audioFile else { return }

        // Create output format (mono, 48kHz, Float32)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "ImportAudio",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"]
            )
        }

        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: targetURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Create converter
        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw NSError(
                domain: "ImportAudio",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
            )
        }

        // Read and convert in chunks
        let bufferSize: AVAudioFrameCount = 4096
        file.framePosition = 0

        while file.framePosition < file.length {
            // Read input buffer
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: bufferSize
            ) else { break }

            try file.read(into: inputBuffer)

            // Convert to output format
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(Double(inputBuffer.frameLength) * outputFormat.sampleRate / file.processingFormat.sampleRate) + 1
            ) else { break }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let error = error {
                throw error
            }

            // Write to output file
            try outputFile.write(from: outputBuffer)
        }

    }

    private func exportCroppedAudio(to targetURL: URL) async throws {
        guard let file = audioFile else { return }

        let format = file.processingFormat
        let sampleRate = format.sampleRate

        // Calculate frame positions
        let startFrame = AVAudioFramePosition(cropStartTime * sampleRate)
        let frameCount = AVAudioFrameCount(cropDuration * sampleRate)

        // Create output format (mono, 48kHz, Float32)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "ImportAudio",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"]
            )
        }

        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: targetURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Create converter if needed
        let needsConversion = format.sampleRate != outputFormat.sampleRate || format.channelCount != outputFormat.channelCount

        // Set read position
        file.framePosition = startFrame

        // Read and write in chunks
        let bufferSize: AVAudioFrameCount = 4096
        var framesRemaining = Int64(frameCount)

        if needsConversion {
            guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                throw NSError(
                    domain: "ImportAudio",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
                )
            }

            while framesRemaining > 0 {
                let framesToRead = min(AVAudioFrameCount(framesRemaining), bufferSize)

                // Read input buffer
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: framesToRead
                ) else { break }

                try file.read(into: inputBuffer, frameCount: framesToRead)

                // Convert to output format
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(Double(inputBuffer.frameLength) * outputFormat.sampleRate / format.sampleRate) + 1
                ) else { break }

                var error: NSError?
                converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                if let error = error {
                    throw error
                }

                // Write to output file
                try outputFile.write(from: outputBuffer)
                framesRemaining -= Int64(inputBuffer.frameLength)
            }
        } else {
            // No conversion needed, direct copy
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: bufferSize
            ) else {
                throw NSError(
                    domain: "ImportAudio",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"]
                )
            }

            while framesRemaining > 0 {
                let framesToRead = min(AVAudioFrameCount(framesRemaining), bufferSize)
                try file.read(into: buffer, frameCount: framesToRead)
                try outputFile.write(from: buffer)
                framesRemaining -= Int64(buffer.frameLength)
            }
        }

    }

    // MARK: - Helpers

    private func updateCropDuration() {
        cropDuration = cropEndTime - cropStartTime

        // Enforce max duration
        if cropDuration > maxImportDuration {
            cropEndTime = cropStartTime + maxImportDuration
            cropDuration = maxImportDuration
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, secs, ms)
    }
}

// MARK: - Button Styles

struct TapelabPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tapelabMonoSmall)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.tapelabRed)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct TapelabSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tapelabMonoSmall)
            .foregroundColor(.tapelabLight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.tapelabButtonBg)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
