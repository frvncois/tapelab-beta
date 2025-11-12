import SwiftUI

struct DashboardView: View {
    @StateObject private var runtime = AudioRuntime()
    @State private var selectedTab: Tab = .sessions
    @State private var showStudio = false
    @State private var isLoadingSession = false

    enum Tab {
        case sessions
        case mixes
        case settings
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                header

                // Content
                ZStack {
                    TapelabTheme.Colors.background
                        .ignoresSafeArea()

                    tabContent
                }

                // Tab Bar
                tabBar
            }
            .ignoresSafeArea(.keyboard)

            // Loading overlay
            if isLoadingSession {
                loadingOverlay
            }
        }
        .fullScreenCover(isPresented: $showStudio) {
            SessionView(runtime: runtime, selectedTab: $selectedTab)
                .onAppear {
                    // Dismiss loading screen once SessionView has appeared
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isLoadingSession = false
                    }
                }
                .onDisappear {
                    // Notify SessionsListView to reload when returning from Studio
                    NotificationCenter.default.post(name: NSNotification.Name("ReloadSessions"), object: nil)
                }
        }
    }

    private var header: some View {
        ZStack {
            // Background image
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(edges: .top)

            // Lottie Logo Animation
            LottieLogoView()
                .padding(.vertical, 10)
        }
        .frame(height: 60)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .sessions:
            SessionsListView(onCreateSession: { sessionID in
                loadAndOpenSession(sessionID)
            })
        case .mixes:
            MixesListView()
                .environmentObject(runtime)
        case .settings:
            SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            TabBarItem(
                icon: "waveform.circle.fill",
                title: "SESSIONS",
                isSelected: selectedTab == .sessions
            ) {
                selectedTab = .sessions
            }

            TabBarItem(
                icon: "music.note.list",
                title: "MIXES",
                isSelected: selectedTab == .mixes
            ) {
                selectedTab = .mixes
            }

            TabBarItem(
                icon: "gearshape.fill",
                title: "SETTINGS",
                isSelected: selectedTab == .settings
            ) {
                selectedTab = .settings
            }
        }
        .padding(.bottom, 0) // Remove padding to go to bottom
        .background(
            TapelabTheme.Colors.surface
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                LoadingAnimationView()

                Text("Loading Session")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(TapelabTheme.Colors.text)
            }
        }
    }

    private func loadAndOpenSession(_ sessionID: UUID) {
        Task {
            // Show loading screen
            let startTime = Date()

            await MainActor.run {
                isLoadingSession = true
            }

            do {
                // Load full session from disk
                let session = try FileStore.loadSession(sessionID)

                // Ensure minimum 2-second display time for animation
                let elapsed = Date().timeIntervalSince(startTime)
                let remainingTime = max(0, 2.0 - elapsed)
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))

                // Load session into runtime and show SessionView
                // Loading screen will be dismissed by SessionView.onAppear
                await MainActor.run {
                    runtime.session = session
                    runtime.timeline.playhead = 0.0  // Reset playhead to zero
                    showStudio = true
                }
            } catch {
                print("⚠️ Failed to load session: \(error)")

                // Still respect minimum time even on error
                let elapsed = Date().timeIntervalSince(startTime)
                let remainingTime = max(0, 2.0 - elapsed)
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))

                await MainActor.run {
                    isLoadingSession = false
                    // TODO: Show error alert to user
                }
            }
        }
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .tapelabRed : .tapelabLight)

                Text(title)
                    .font(.tapelabMonoTiny)
                    .foregroundColor(isSelected ? .tapelabRed : .tapelabLight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.bottom, 8) // Extra padding for safe area
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DashboardView()
}
