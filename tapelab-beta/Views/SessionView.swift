//
//  SessionView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI
import Lottie

struct SessionView: View {
    @ObservedObject var runtime: AudioRuntime
    @Binding var selectedTab: DashboardView.Tab
    @State private var armedTrack: Int = 1
    @State private var showMenu = false
    @State private var showInfoSheet = false
    @State private var editedTitle = ""
    @State private var sessionCoverImage: UIImage? = nil
    @State private var showExportAlert = false
    @State private var exportAlertMessage = ""
    @State private var exportProgress: Int = 0
    @State private var showFileImporter = false
    @State private var importFileItem: ImportFileItem?
    @State private var isExporting = false
    @State private var showDeleteConfirmation = false
    @State private var showMixLimitAlert = false
    @State private var isProUser = false  // TODO: Connect to actual Pro subscription status
    @Environment(\.dismiss) var dismiss

    private let maxFreeMixes = 4

    // Import file item wrapper for atomic state management
    struct ImportFileItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(alignment: .center, spacing: 2) {
                    Button(action: {
                        editedTitle = runtime.session.name
                        sessionCoverImage = FileStore.loadSessionCover(runtime.session.id)
                        showInfoSheet = true
                    }) {
                        Text(String(runtime.session.name.prefix(16)))
                            .font(.tapelabMonoHeadline)
                            .lineLimit(1)
                            .foregroundColor(.tapelabLight)
                    }

                    PlayheadTimeText(timeline: runtime.timeline)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
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

                    Menu {
                            Button(action: {
                        showFileImporter = true
                    }) {
                        Label("Import Audio", systemImage: "square.and.arrow.down")
                    }

                    Button(action: {
                        exportSession()
                    }) {
                        Label("Bounce Session", systemImage: "square.and.arrow.up.on.square")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Session", systemImage: "trash")
                    }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.tapelabLight)
                            .frame(width: 32, height: 32)
                            .background(Color.tapelabButtonBg)
                            .cornerRadius(16)
                    }
                }
            }
            .padding()
            .background(Color.tapelabBlack)

            Divider()

            // Timeline visualization (main content)
            TimelineView(
                timeline: runtime.timeline,
                tracks: $runtime.session.tracks,
                armedTrack: $armedTrack,
                runtime: runtime,
                basePixelsPerSecond: 50.0,
                maxDuration: runtime.session.maxDuration
            )
            .frame(maxHeight: .infinity)
            .background(Color.tapelabBackground)

            Divider()

            // Transport controls at bottom
            TransportView(runtime: runtime, armedTrack: armedTrack, onBounce: exportSession)
        }
        .background(Color.tapelabBackground)
        .navigationBarHidden(true)
        .disabled(runtime.isProcessing || isExporting)
        .overlay {
            // Export bouncing overlay
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        LottieView(animation: .named("loading"))
                            .playing(loopMode: .loop)
                            .animationSpeed(-1.0) // Play backwards
                            .resizable()
                            .frame(width: 150, height: 150)

                        Text("Bouncing session")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(TapelabTheme.Colors.text)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isExporting)
            }

            // Processing overlay
            if runtime.isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        LoadingAnimationView()

                        Text(runtime.processingMessage)
                            .font(.tapelabMonoSmall)
                            .foregroundColor(TapelabTheme.Colors.text)

                        if exportProgress > 0 {
                            Text("\(exportProgress)%")
                                .font(.tapelabMono)
                                .foregroundColor(TapelabTheme.Colors.accent)
                        }
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: runtime.isProcessing)
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            SessionInfoSheet(
                sessionName: $editedTitle,
                coverImage: $sessionCoverImage,
                onSave: {
                    saveSessionInfo()
                },
                onCancel: {
                    showInfoSheet = false
                }
            )
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }
        .alert(isPresented: $showExportAlert) {
            Alert(
                title: Text("Export Complete"),
                message: Text(exportAlertMessage),
                primaryButton: .default(Text("Go to Mix")) {
                    selectedTab = .mixes
                    dismiss()
                },
                secondaryButton: .default(Text("OK"))
            )
        }
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            Text("Are you sure you want to delete this session? This cannot be undone.")
        }
        .alert(
            "Mix Limit Reached",
            isPresented: $showMixLimitAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free users are limited to \(maxFreeMixes) mixes. Upgrade to 4TRACK Pro for unlimited mixes.")
        }
        .alert(
            runtime.alertTitle,
            isPresented: $runtime.showAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(runtime.alertMessage)
        }
        .sheet(isPresented: $showFileImporter) {
            AudioFileImporter(
                onFileSelected: { url in
                    showFileImporter = false

                    // Small delay to ensure file importer dismisses cleanly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        importFileItem = ImportFileItem(url: url)
                    }
                },
                onCancel: {
                    showFileImporter = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $importFileItem) { item in

            ImportAudioSheet(
                session: $runtime.session,
                playheadPosition: runtime.timeline.playhead,
                runtime: runtime,
                sourceFileURL: item.url
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            // Stop recording or playback when leaving the session view
            if runtime.timeline.isRecording {
                runtime.stopRecording(onTrack: armedTrack - 1)
            } else if runtime.timeline.isPlaying {
                runtime.stopPlayback(resetPlayhead: false)
            }
        }
    }

    // Export session to stereo mix
    private func exportSession() {
        Task {
            do {
                // Check mix limit for free users
                if !isProUser {
                    let existingMixes = try FileStore.loadAllMixMetadata()
                    if existingMixes.count >= maxFreeMixes {
                        await MainActor.run {
                            showMixLimitAlert = true
                        }
                        return
                    }
                }

                // Show bouncing overlay immediately
                await MainActor.run {
                    isExporting = true
                }

                // Generate output file URL
                let outputURL = FileStore.newMixURL(sessionName: runtime.session.name)

                // Create bouncer
                let bouncer = SessionBouncer(
                    session: runtime.session,
                    audioController: runtime.engine
                )

                // Bounce (this is usually very fast with offline rendering)
                let mix = try await bouncer.bounce(to: outputURL) { progress in
                    // Progress updates happen silently during the 3-second animation
                }

                // Save mix metadata
                try FileStore.saveMix(mix)

                // Copy session cover image to mix (if it exists)
                if let sessionCover = FileStore.loadSessionCover(runtime.session.id) {
                    try? FileStore.saveMixCover(sessionCover, for: mix.id)
                }

                // Keep showing animation for 3 seconds total
                try await Task.sleep(nanoseconds: 3_000_000_000)

                // Success - hide animation and show alert
                await MainActor.run {
                    isExporting = false
                    exportAlertMessage = "Mix saved to Mixes folder"
                    showExportAlert = true
                }

            } catch let error as SessionBouncer.BounceError {
                // Handle bounce-specific errors
                await MainActor.run {
                    isExporting = false
                    exportAlertMessage = error.localizedDescription
                    showExportAlert = true
                }
            } catch {
                // Handle other errors
                await MainActor.run {
                    isExporting = false
                    exportAlertMessage = "Export failed: \(error.localizedDescription)"
                    showExportAlert = true
                }
            }
        }
    }

    // Save the edited title and cover image
    private func saveSessionInfo() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't allow empty titles
        guard !trimmedTitle.isEmpty else {
            showInfoSheet = false
            return
        }

        // Update session name
        runtime.session.name = trimmedTitle

        // Save cover image if provided
        if let coverImage = sessionCoverImage {
            saveCoverImage(coverImage, for: runtime.session.id)
        }

        showInfoSheet = false

        // Session will auto-save via AudioRuntime's didSet

        // Post notification to reload sessions list (for instant UI updates)
        NotificationCenter.default.post(name: NSNotification.Name("ReloadSessions"), object: nil)
    }

    // Save cover image to disk
    private func saveCoverImage(_ image: UIImage, for sessionID: UUID) {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        do {
            let coverURL = FileStore.sessionCoverURL(sessionID)
            try jpegData.write(to: coverURL)
        } catch {
        }
    }

    // Delete the current session
    private func deleteSession() {
        do {
            try FileStore.deleteSession(runtime.session.id)

            // Post notification to reload sessions list
            NotificationCenter.default.post(name: NSNotification.Name("ReloadSessions"), object: nil)

            // Dismiss back to dashboard
            dismiss()
        } catch {
            // TODO: Show error alert to user
        }
    }
}

// MARK: - Helper View for Real-Time Playhead Display
struct PlayheadTimeText: View {
    @ObservedObject var timeline: TimelineState

    private var statusColor: Color {
        if timeline.isRecording {
            return .tapelabRed
        } else if timeline.isPlaying {
            return .tapelabGreen
        } else {
            return .tapelabAccentFull
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 3, height: 3)

            Text(String(format: "%.2f s", timeline.playhead))
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)
        }
    }
}
