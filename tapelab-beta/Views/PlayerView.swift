import SwiftUI
import AVFAudio
import Combine

/// Simple audio player for playing back bounced mixes
struct PlayerView: View {
    let mix: Mix
    let allMixes: [MixMetadata]

    @StateObject private var player = MixPlayer()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var runtime: AudioRuntime
    @State private var coverImage: UIImage? = nil
    @State private var currentMix: Mix
    @State private var dragOffset: CGFloat = 0

    init(mix: Mix, allMixes: [MixMetadata] = []) {
        self.mix = mix
        self.allMixes = allMixes
        _currentMix = State(initialValue: mix)
    }

    var body: some View {
        ZStack {
            // Blurred background image
            if let coverImage = coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 50)
                    .overlay(
                        // Gradient overlay for darker bottom
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.3), location: 0.0),
                                .init(color: Color.black.opacity(0.5), location: 0.5),
                                .init(color: Color.black.opacity(0.9), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    )
                    .allowsHitTesting(false)
            } else {
                // Fallback solid background if no cover
                Color.tapelabBlack
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Header
                header

                // Player content
                VStack(spacing: 32) {
                    Spacer()

                    // Square cover image centered with swipe gesture
                    ZStack {
                        if let coverImage = coverImage {
                            Image(uiImage: coverImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 280, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(TapelabTheme.Colors.surface)
                                .frame(width: 280, height: 280)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .font(.system(size: 80))
                                        .foregroundColor(TapelabTheme.Colors.accent.opacity(0.3))
                                )
                                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        }
                    }
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 100
                                if value.translation.width > threshold {
                                    // Swipe right - previous mix
                                    navigateToPreviousMix()
                                } else if value.translation.width < -threshold {
                                    // Swipe left - next mix
                                    navigateToNextMix()
                                }
                                withAnimation(.spring()) {
                                    dragOffset = 0
                                }
                            }
                    )

                    Spacer()

                    // Controls section (on dark background)
                    VStack(spacing: 24) {
                        // Time display
                        VStack(spacing: 12) {
                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 4)

                                    // Progress
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: geometry.size.width * CGFloat(player.progress), height: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 40)

                            // Time labels
                            HStack {
                                Text(formatTime(player.currentTime))
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.white)

                                Spacer()

                                Text(formatTime(currentMix.duration))
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 40)
                        }

                        // Transport controls
                        HStack(spacing: 40) {
                            // Rewind button - matching TransportView style
                            Button(action: {
                                player.seek(to: 0)
                            }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title2)
                                    .foregroundColor(.tapelabAccentFull)
                            }
                            .buttonStyle(.plain)

                            // Play/Pause button - matching TransportView style
                            Button(action: {
                                if player.isPlaying {
                                    player.pause()
                                } else {
                                    player.play()
                                }
                            }) {
                                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(player.isPlaying ? .tapelabRed : .tapelabGreen)
                            }
                            .buttonStyle(.plain)

                            // Share button - matching TransportView style
                            Button(action: {
                                shareAudioFile()
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                    .foregroundColor(.tapelabAccentFull)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                dismiss()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                        )

                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
            .shadow(color: .black, radius: 20)
        }
        .navigationBarHidden(true)
        .onAppear {
            loadCurrentMix()

            // CRITICAL: Stop main engine first to free audio session
            runtime.suspendForExternalPlayback()
        }
        .onDisappear {
            print("🎵 PlayerView disappeared")
            player.stop()

            // CRITICAL: Resume main engine
            runtime.resumeAfterExternalPlayback()
        }
        .onChange(of: currentMix.id) { _, _ in
            loadCurrentMix()
        }
    }

    private var header: some View {
        // Title centered
        VStack(spacing: 4) {
            Text(currentMix.name)
                .font(.tapelabMonoHeadline)
                .lineLimit(1)
                .foregroundColor(.white)

            Text(currentMix.sessionName)
                .font(.tapelabMonoSmall)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func loadCurrentMix() {
        // Load cover image
        coverImage = FileStore.loadMixCover(currentMix.id)

        print("🎵 PlayerView loading mix: \(currentMix.name)")
        print("🎵 Mix file URL: \(currentMix.fileURL)")
        print("🎵 Mix duration: \(currentMix.duration)s")

        // Stop current playback
        player.stop()

        // Small delay to ensure player is stopped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            player.load(url: currentMix.fileURL)
        }
    }

    private func navigateToNextMix() {
        guard !allMixes.isEmpty else { return }

        if let currentIndex = allMixes.firstIndex(where: { $0.id == currentMix.id }) {
            let nextIndex = (currentIndex + 1) % allMixes.count
            let nextMixMetadata = allMixes[nextIndex]

            // Load full mix from metadata
            if let fullMix = try? FileStore.loadMix(nextMixMetadata.id) {
                currentMix = fullMix
                print("📱 Swiped to next mix: \(fullMix.name)")
            }
        }
    }

    private func navigateToPreviousMix() {
        guard !allMixes.isEmpty else { return }

        if let currentIndex = allMixes.firstIndex(where: { $0.id == currentMix.id }) {
            let previousIndex = (currentIndex - 1 + allMixes.count) % allMixes.count
            let previousMixMetadata = allMixes[previousIndex]

            // Load full mix from metadata
            if let fullMix = try? FileStore.loadMix(previousMixMetadata.id) {
                currentMix = fullMix
                print("📱 Swiped to previous mix: \(fullMix.name)")
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func shareAudioFile() {
        // Create activity view controller with the audio file
        let activityVC = UIActivityViewController(
            activityItems: [currentMix.fileURL],
            applicationActivities: nil
        )

        // Configure for iPad (required for popover presentation)
        if let popoverController = activityVC.popoverPresentationController {
            // Find the share button view to anchor the popover
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popoverController.sourceView = window
                popoverController.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }

        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost view controller
            var topController = rootVC
            while let presentedVC = topController.presentedViewController {
                topController = presentedVC
            }
            topController.present(activityVC, animated: true)

            print("📤 Presenting share sheet for: \(currentMix.name)")
            print("📤 File URL: \(currentMix.fileURL.path)")
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
