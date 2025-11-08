import SwiftUI
import AVFAudio
import Combine

/// Simple audio player for playing back bounced mixes
struct PlayerView: View {
    let mix: Mix
    @StateObject private var player = MixPlayer()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var runtime: AudioRuntime

    var body: some View {
        ZStack {
            // Background - use explicit color to debug
            Color(hex: "1D1613")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .background(Color(hex: "17120F"))

                Divider()
                    .background(Color.gray)

                // Player content
                VStack(spacing: 40) {
                Spacer()

                // Waveform placeholder / artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(TapelabTheme.Colors.surface)
                        .frame(height: 200)

                    Image(systemName: "waveform")
                        .font(.system(size: 80))
                        .foregroundColor(TapelabTheme.Colors.accent.opacity(0.3))
                }
                .padding(.horizontal, 40)

                // Time display
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(TapelabTheme.Colors.surface)
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(TapelabTheme.Colors.accent)
                                .frame(width: geometry.size.width * CGFloat(player.progress), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 40)

                    // Time labels
                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.tapelabMonoSmall)
                            .foregroundColor(TapelabTheme.Colors.text)

                        Spacer()

                        Text(formatTime(mix.duration))
                            .font(.tapelabMonoSmall)
                            .foregroundColor(TapelabTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 40)
                }

                // Transport controls
                HStack(spacing: 40) {
                    // Rewind button
                    Button(action: {
                        player.seek(to: 0)
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 28))
                            .foregroundColor(TapelabTheme.Colors.text)
                    }

                    // Play/Pause button
                    Button(action: {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(TapelabTheme.Colors.accent)
                                .frame(width: 70, height: 70)

                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.tapelabLight)
                                .offset(x: player.isPlaying ? 0 : 2) // Optical centering for play icon
                        }
                    }

                    // Share button
                    Button(action: {
                        shareAudioFile()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 28))
                            .foregroundColor(TapelabTheme.Colors.text)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 40)
        }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🎵 PlayerView appeared for mix: \(mix.name)")
            print("🎵 Mix file URL: \(mix.fileURL)")
            print("🎵 Mix duration: \(mix.duration)s")

            // CRITICAL: Stop main engine first to free audio session
            runtime.suspendForExternalPlayback()

            // Small delay to ensure engine is stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                player.load(url: mix.fileURL)
            }
        }
        .onDisappear {
            print("🎵 PlayerView disappeared")
            player.stop()

            // CRITICAL: Resume main engine
            runtime.resumeAfterExternalPlayback()
        }
    }

    private var header: some View {
        ZStack {
            // Back button on left
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                        Text("BACK")
                            .font(.tapelabMonoTiny)
                    }
                    .foregroundColor(.tapelabLight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.tapelabButtonBg)
                    .cornerRadius(16)
                }

                Spacer()
            }

            // Title centered
            VStack(spacing: 4) {
                Text(mix.name)
                    .font(.tapelabMonoHeadline)
                    .lineLimit(1)
                    .foregroundColor(.tapelabLight)

                Text(mix.sessionName)
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight.opacity(0.6))
            }
        }
        .padding()
        .background(Color.tapelabBlack)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func shareAudioFile() {
        let activityVC = UIActivityViewController(
            activityItems: [mix.fileURL],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Mix Player Controller

@MainActor
class MixPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var progress: Double = 0

    func load(url: URL) {
        print("🎵 Loading mix from: \(url)")
        print("🎵 File exists: \(FileManager.default.fileExists(atPath: url.path))")

        // Verify file before attempting to load
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0
            print("🎵 File size: \(fileSize) bytes")

            if fileSize == 0 {
                print("⚠️ File is empty!")
                return
            }
        } catch {
            print("⚠️ Cannot access file: \(error)")
            return
        }

        // Try to read file header to verify it's valid audio
        do {
            let data = try Data(contentsOf: url)
            print("🎵 Read \(data.count) bytes from file")

            // Check for WAV header (RIFF)
            if data.count >= 4 {
                let header = String(data: data.prefix(4), encoding: .ascii) ?? ""
                print("🎵 File header: '\(header)' (should be 'RIFF')")

                if header != "RIFF" {
                    print("⚠️ Invalid WAV file - header is '\(header)' not 'RIFF'")
                    return
                }
            }
        } catch {
            print("⚠️ Cannot read file data: \(error)")
            return
        }

        // Configure audio session for playback FIRST
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // Ensure session is inactive first
            try audioSession.setActive(false)

            // Set to playback with Bluetooth support
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay, .duckOthers]
            )

            // Activate
            try audioSession.setActive(true)

            print("✅ Audio session configured for playback")
            print("   Category: \(audioSession.category.rawValue)")
            print("   Sample rate: \(audioSession.sampleRate)Hz")
            print("   Output route: \(audioSession.currentRoute.outputs.first?.portName ?? "unknown")")
            print("   Output port type: \(audioSession.currentRoute.outputs.first?.portType.rawValue ?? "unknown")")

            // Verify we have Bluetooth output
            let hasBluetoothOutput = audioSession.currentRoute.outputs.contains { output in
                output.portType == .bluetoothA2DP || output.portType == .bluetoothLE
            }
            print("   Has Bluetooth output: \(hasBluetoothOutput)")

        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
            return
        }

        // Now try to load the audio file
        do {
            print("🎵 Creating AVAudioPlayer...")
            audioPlayer = try AVAudioPlayer(contentsOf: url)

            guard let player = audioPlayer else {
                print("⚠️ AVAudioPlayer is nil after creation")
                return
            }

            player.prepareToPlay()

            print("✅ Successfully loaded audio file")
            print("   Duration: \(player.duration)s")
            print("   Channels: \(player.numberOfChannels)")
            print("   Format: \(player.format.sampleRate)Hz")

        } catch let error as NSError {
            print("⚠️ AVAudioPlayer creation failed:")
            print("   Error domain: \(error.domain)")
            print("   Error code: \(error.code)")
            print("   Error description: \(error.localizedDescription)")
            print("   User info: \(error.userInfo)")

            // Try alternate approach with data
            print("🔄 Trying alternate approach with Data...")
            do {
                let audioData = try Data(contentsOf: url)
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.prepareToPlay()
                print("✅ Loaded via Data approach")
            } catch {
                print("⚠️ Data approach also failed: \(error)")
            }
        }
    }

    func play() {
        do {
            // Ensure audio session is active before playing
            let audioSession = AVAudioSession.sharedInstance()
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }

            audioPlayer?.play()
            isPlaying = true
            startTimer()
            print("▶️ Playing mix")
            print("🎵 Player isPlaying: \(audioPlayer?.isPlaying ?? false)")
            print("🎵 Player duration: \(audioPlayer?.duration ?? 0)s")
        } catch {
            print("⚠️ Failed to activate audio session: \(error)")
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
        print("⏸️ Paused mix")
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
        progress = 0
        print("⏹️ Stopped mix")
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        updateProgress()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }

        currentTime = player.currentTime
        let duration = player.duration

        if duration > 0 {
            progress = currentTime / duration
        }

        // Auto-stop at end
        if !player.isPlaying && isPlaying {
            isPlaying = false
            stopTimer()
        }
    }
}

#Preview {
    PlayerView(mix: Mix(
        name: "My Song",
        sessionId: UUID(),
        sessionName: "Session #0001",
        duration: 180,
        fileURL: URL(fileURLWithPath: "/tmp/test.wav")
    ))
}
