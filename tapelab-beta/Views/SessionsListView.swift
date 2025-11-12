import SwiftUI

struct SessionsListView: View {
    @State private var sessionMetadata: [SessionMetadata] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var sortOrder: SortOrder = .dateNewest

    let onCreateSession: (UUID) -> Void  // Pass session ID instead of full session

    enum SortOrder: String, CaseIterable {
        case dateNewest = "Date (Newest)"
        case dateOldest = "Date (Oldest)"
        case nameAZ = "Name (A-Z)"
        case nameZA = "Name (Z-A)"
    }

    var body: some View {
        ZStack {
            TapelabTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with title, sort, and search (only show if there are sessions)
                if !sessionMetadata.isEmpty {
                    listHeader
                        .padding(.bottom, 20)
                }

                if sessionMetadata.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }

            // Floating Create Session Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: createNewSession) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("CREATE SESSION")
                                .font(.tapelabMonoSmall)
                        }
                        .foregroundColor(.tapelabLight)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.tapelabRed)
                        .cornerRadius(25)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            loadSessions()
        }
        .onDisappear {
            // Reset search when leaving view
            searchText = ""
            isSearching = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadSessions"))) { _ in
            // Reload sessions when returning from Studio (to catch name changes, etc.)
            loadSessions()
        }
    }

    private var listHeader: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                // Title Badge with dot
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.tapelabLight)
                        .frame(width: 3, height: 3)

                    Text("SESSIONS")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                }

                Spacer()

                // Sort Menu (rounded)
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button(action: {
                            sortOrder = order
                            sortSessions()
                        }) {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14))
                        Text("SORT")
                            .font(.tapelabMonoTiny)
                    }
                    .foregroundColor(.tapelabLight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.tapelabButtonBg)
                    .cornerRadius(16)
                }

                // Search Toggle (rounded)
                Button(action: {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                    }
                }) {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.tapelabLight)
                        .frame(width: 32, height: 32)
                        .background(Color.tapelabButtonBg)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Search Bar (when active)
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.tapelabAccentFull)
                        .font(.system(size: 14))

                    TextField("Search sessions...", text: $searchText)
                        .font(.tapelabMono)
                        .foregroundColor(.tapelabLight)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TapelabTheme.Colors.surface)
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundColor(TapelabTheme.Colors.text.opacity(0.25))

            Text("NO SESSIONS YET")
                .font(.tapelabMonoSmall)
                .foregroundColor(TapelabTheme.Colors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionsList: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredSessions) { metadata in
                    Button(action: {
                        openSession(metadata.id)
                    }) {
                        SessionGridItemView(metadata: metadata)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100) // Space for floating button
        }
        .background(TapelabTheme.Colors.background)
    }

    private var filteredSessions: [SessionMetadata] {
        if searchText.isEmpty {
            return sessionMetadata
        } else {
            return sessionMetadata.filter { metadata in
                metadata.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func loadSessions() {
        do {
            // Load only metadata from FileStore (lightweight, fast)
            sessionMetadata = try FileStore.loadAllSessionMetadata()
            sortSessions()
        } catch {
            print("⚠️ Failed to load session metadata: \(error)")
            sessionMetadata = []
        }
    }

    private func sortSessions() {
        switch sortOrder {
        case .dateNewest:
            sessionMetadata.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            sessionMetadata.sort { $0.createdAt < $1.createdAt }
        case .nameAZ:
            sessionMetadata.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameZA:
            sessionMetadata.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }

    private func createNewSession() {
        // Create a new session with auto-generated ID and default name
        let sessionID = UUID()

        // Generate session number (based on existing sessions count + 1)
        let sessionNumber = sessionMetadata.count + 1
        let formattedNumber = String(format: "%04d", sessionNumber)

        let newSession = Session(
            id: sessionID,
            name: "Session #\(formattedNumber)"
        )

        // Save session to FileStore immediately
        do {
            try FileStore.saveSession(newSession)

            // Add metadata to local array
            let metadata = SessionMetadata(from: newSession)
            sessionMetadata.insert(metadata, at: 0) // Insert at top (newest first)

            // Trigger navigation to Studio with the session ID
            onCreateSession(sessionID)
        } catch {
            print("⚠️ Failed to create session: \(error)")
            // TODO: Show error alert to user
        }
    }

    private func openSession(_ sessionID: UUID) {
        // Open existing session in Studio - DashboardView will load full session
        onCreateSession(sessionID)
    }

}

struct SessionGridItemView: View {
    let metadata: SessionMetadata
    @State private var coverImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Square session cover or icon
            ZStack {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(TapelabTheme.Colors.background)
                        .frame(height: 150)
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.system(size: 40))
                                .foregroundColor(TapelabTheme.Colors.accent)
                        )
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .onAppear {
                loadCoverImage()
            }

            // Session title
            Text(metadata.name)
                .font(.tapelabMono)
                .foregroundColor(TapelabTheme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadCoverImage() {
        coverImage = FileStore.loadSessionCover(metadata.id)
    }
}

#Preview {
    SessionsListView(onCreateSession: { _ in })
}
