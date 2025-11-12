//
//  SessionView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct SessionView: View {
    @ObservedObject var runtime: AudioRuntime
    @State private var armedTrack: Int = 1 // Track 1 is armed by default
    @State private var showMenu = false
    @State private var showInfoSheet = false
    @State private var editedTitle = ""
    @State private var sessionCoverImage: UIImage? = nil
    @State private var showExportAlert = false
    @State private var exportAlertMessage = ""
    @State private var exportProgress: Int = 0
    @State private var showFileImporter = false
    @State private var importFileItem: ImportFileItem?
    @Environment(\.dismiss) var dismiss

    // Import file item wrapper for atomic state management
    struct ImportFileItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            ZStack {
                // Session info (title + timestamp) - absolutely centered
                VStack(alignment: .center, spacing: 2) {
                    // Tappable title
                    Button(action: {
                        editedTitle = runtime.session.name
                        sessionCoverImage = FileStore.loadSessionCover(runtime.session.id)
                        showInfoSheet = true
                    }) {
                        Text(runtime.session.name)
                            .font(.tapelabMonoHeadline)
                            .lineLimit(1)
                            .foregroundColor(.tapelabLight)
                    }

                    // Observe timeline directly to get real-time playhead updates
                    PlayheadTimeText(timeline: runtime.timeline)
                }
                .frame(maxWidth: .infinity)

                // Buttons overlay on left and right
                HStack(spacing: 12) {
                    // Back button
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

                    // Menu button
                    Menu {
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Label("Import Audio", systemImage: "square.and.arrow.down")
                    }

                    Button(action: {
                        // TODO: Export track functionality
                    }) {
                        Label("Export Track", systemImage: "square.and.arrow.up")
                    }

                    Button(action: {
                        exportSession()
                    }) {
                        Label("Export Session", systemImage: "square.and.arrow.up.on.square")
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
            TransportView(runtime: runtime, armedTrack: armedTrack)
        }
        .background(Color.tapelabBackground)
        .navigationBarHidden(true)
        .disabled(runtime.isProcessing)
        .overlay {
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
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showFileImporter) {
            AudioFileImporter(
                onFileSelected: { url in
                    print("📱 SessionView: File selected: \(url.lastPathComponent)")
                    showFileImporter = false

                    // Small delay to ensure file importer dismisses cleanly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("📱 SessionView: Creating ImportFileItem")
                        importFileItem = ImportFileItem(url: url)
                    }
                },
                onCancel: {
                    print("📱 SessionView: File importer cancelled")
                    showFileImporter = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $importFileItem) { item in
            let _ = print("📱 SessionView: Presenting ImportAudioSheet with file: \(item.url.lastPathComponent)")

            ImportAudioSheet(
                session: $runtime.session,
                playheadPosition: runtime.timeline.playhead,
                runtime: runtime,
                sourceFileURL: item.url
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // Export session to stereo mix
    private func exportSession() {
        Task {
            // Show processing overlay
            await MainActor.run {
                runtime.isProcessing = true
                runtime.processingMessage = "Bouncing mix..."
                exportProgress = 0
            }

            do {
                // Generate output file URL
                let outputURL = FileStore.newMixURL(sessionName: runtime.session.name)

                // Create bouncer
                let bouncer = SessionBouncer(
                    session: runtime.session,
                    audioController: runtime.engine
                )

                // Bounce with progress updates
                let mix = try await bouncer.bounce(to: outputURL) { progress in
                    Task { @MainActor in
                        exportProgress = progress.percentage
                    }
                }

                // Save mix metadata
                try FileStore.saveMix(mix)

                // Copy session cover image to mix (if it exists)
                if let sessionCover = FileStore.loadSessionCover(runtime.session.id) {
                    try? FileStore.saveMixCover(sessionCover, for: mix.id)
                }

                // Success
                await MainActor.run {
                    runtime.isProcessing = false
                    runtime.processingMessage = ""
                    exportProgress = 0
                    exportAlertMessage = "Mix saved to Mixes folder"
                    showExportAlert = true
                    print("✅ Export complete: \(mix.name)")
                }

            } catch let error as SessionBouncer.BounceError {
                // Handle bounce-specific errors
                await MainActor.run {
                    runtime.isProcessing = false
                    runtime.processingMessage = ""
                    exportProgress = 0
                    exportAlertMessage = error.localizedDescription ?? "Export failed"
                    showExportAlert = true
                    print("⚠️ Export failed: \(error)")
                }
            } catch {
                // Handle other errors
                await MainActor.run {
                    runtime.isProcessing = false
                    runtime.processingMessage = ""
                    exportProgress = 0
                    exportAlertMessage = "Export failed: \(error.localizedDescription)"
                    showExportAlert = true
                    print("⚠️ Export failed: \(error)")
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
        print("💾 Session updated: \(trimmedTitle)")
    }

    // Save cover image to disk
    private func saveCoverImage(_ image: UIImage, for sessionID: UUID) {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            print("⚠️ Failed to convert image to JPEG")
            return
        }

        do {
            let coverURL = FileStore.sessionCoverURL(sessionID)
            try jpegData.write(to: coverURL)
            print("📷 Saved cover image: \(coverURL.lastPathComponent)")
        } catch {
            print("⚠️ Failed to save cover image: \(error)")
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
