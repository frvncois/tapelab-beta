import SwiftUI
import AVFAudio
import Combine

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
            if let coverImage = coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 50)
                    .overlay(
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
                Color.tapelabBlack
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header

                VStack(spacing: 32) {
                    Spacer()

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
                                    navigateToPreviousMix()
                                } else if value.translation.width < -threshold {
                                    navigateToNextMix()
                                }
                                withAnimation(.spring()) {
                                    dragOffset = 0
                                }
                            }
                    )

                    Spacer()

                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 4)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white)
                                        .frame(width: geometry.size.width * CGFloat(player.progress), height: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 40)

                            HStack(spacing: 8) {
                                Text(formatTime(player.currentTime))
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                                    .monospacedDigit()
                                    .frame(width: 60, alignment: .leading)

                                Spacer()

                                Text(formatTime(currentMix.duration))
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.white.opacity(0.6))
                                    .monospacedDigit()
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 40)
                        }


                        HStack(spacing: 40) {
                            Button(action: {
                                player.seek(to: 0)
                            }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.title2)
                                    .foregroundColor(.tapelabLight)
                            }
                            .buttonStyle(.plain)

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
        .navigationBarHidden(true)
        .onAppear {
            loadCurrentMix()
        }
        .onDisappear {
            player.stop()
        }
        .onChange(of: currentMix.id) { _, _ in
            loadCurrentMix()
        }
    }

    private var header: some View {
        Text(currentMix.name)
            .font(.tapelabMonoHeadline)
            .lineLimit(1)
            .foregroundColor(.tapelabLight)
            .frame(maxWidth: .infinity)
            .padding()
    }

    private func loadCurrentMix() {
        coverImage = FileStore.loadMixCover(currentMix.id)
        player.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            player.load(url: currentMix.fileURL)
        }
    }

    private func navigateToNextMix() {
        guard !allMixes.isEmpty else { return }

        if let currentIndex = allMixes.firstIndex(where: { $0.id == currentMix.id }) {
            let nextIndex = (currentIndex + 1) % allMixes.count
            let nextMixMetadata = allMixes[nextIndex]
            if let fullMix = try? FileStore.loadMix(nextMixMetadata.id) {
                currentMix = fullMix
            }
        }
    }

    private func navigateToPreviousMix() {
        guard !allMixes.isEmpty else { return }

        if let currentIndex = allMixes.firstIndex(where: { $0.id == currentMix.id }) {
            let previousIndex = (currentIndex - 1 + allMixes.count) % allMixes.count
            let previousMixMetadata = allMixes[previousIndex]
            if let fullMix = try? FileStore.loadMix(previousMixMetadata.id) {
                currentMix = fullMix
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func shareAudioFile() {
        let activityVC = UIActivityViewController(
            activityItems: [currentMix.fileURL],
            applicationActivities: nil
        )

        if let popoverController = activityVC.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popoverController.sourceView = window
                popoverController.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topController = rootVC
            while let presentedVC = topController.presentedViewController {
                topController = presentedVC
            }
            topController.present(activityVC, animated: true)

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

        // Verify file before attempting to load
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0

            if fileSize == 0 {
                return
            }
        } catch {
            return
        }

        // Try to read file header to verify it's valid audio
        do {
            let data = try Data(contentsOf: url)

            // Check for WAV header (RIFF)
            if data.count >= 4 {
                let header = String(data: data.prefix(4), encoding: .ascii) ?? ""

                if header != "RIFF" {
                    return
                }
            }
        } catch {
            return
        }

        // DON'T configure audio session - it's already been suspended by MixesListView
        // and is in the correct state (.playback category, inactive)
        // AVAudioPlayer will activate it automatically when play() is called

        // Load the audio file
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)

            guard let player = audioPlayer else {
                return
            }

            player.prepareToPlay()


        } catch {

            // Try alternate approach with data
            do {
                let audioData = try Data(contentsOf: url)
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.prepareToPlay()
            } catch {
            }
        }
    }

    func play() {
        // AVAudioPlayer automatically activates the audio session when play() is called
        // No need to do it manually - this can cause conflicts
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
        progress = 0
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        updateProgress()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
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
