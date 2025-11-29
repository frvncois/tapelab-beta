import SwiftUI

struct SessionsListView: View {
    @State private var sessionMetadata: [SessionMetadata] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var sortOrder: SortOrder = .dateNewest
    @State private var showSessionLimitAlert = false
    @State private var isProUser = false  // TODO: Connect to actual Pro subscription status

    // Edit session state
    @State private var showEditSheet = false
    @State private var editingSessionID: UUID?
    @State private var editingSessionName: String = ""
    @State private var editingSessionCover: UIImage?

    // Delete confirmation state
    @State private var showDeleteConfirmation = false
    @State private var deletingSessionID: UUID?

    let onCreateSession: (UUID) -> Void

    private let maxFreeSessions = 4

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
            searchText = ""
            isSearching = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadSessions"))) { _ in
            loadSessions()
        }
        .alert(
            "Session Limit Reached",
            isPresented: $showSessionLimitAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free users are limited to \(maxFreeSessions) sessions. Upgrade to 4TRACK Pro for unlimited sessions.")
        }
        .alert(
            "Delete Session",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                deletingSessionID = nil
            }
            Button("Delete", role: .destructive) {
                if let sessionID = deletingSessionID {
                    deleteSession(sessionID)
                }
                deletingSessionID = nil
            }
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            SessionInfoSheet(
                sessionName: $editingSessionName,
                coverImage: $editingSessionCover,
                onSave: {
                    saveEditedSession()
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
    }

    private var listHeader: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.tapelabLight)
                        .frame(width: 3, height: 3)

                    Text("SESSIONS")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                }

                Spacer()

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
                        .font(.tapelabMonoSmall)
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
                    .contextMenu {
                        Button(action: {
                            openSession(metadata.id)
                        }) {
                            Label("Open Session", systemImage: "play.circle")
                        }

                        Button(action: {
                            editSession(metadata)
                        }) {
                            Label("Edit Session", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            deletingSessionID = metadata.id
                            showDeleteConfirmation = true
                        }) {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
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
        // Check session limit for free users
        if !isProUser && sessionMetadata.count >= maxFreeSessions {
            showSessionLimitAlert = true
            return
        }

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
            // TODO: Show error alert to user
        }
    }

    private func openSession(_ sessionID: UUID) {
        // Open existing session in Studio - DashboardView will load full session
        onCreateSession(sessionID)
    }

    private func editSession(_ metadata: SessionMetadata) {
        editingSessionID = metadata.id
        editingSessionName = metadata.name
        editingSessionCover = FileStore.loadSessionCover(metadata.id)
        showEditSheet = true
    }

    private func saveEditedSession() {
        guard let sessionID = editingSessionID else { return }

        do {
            // Load the full session
            var session = try FileStore.loadSession(sessionID)
            // Update the name
            session.name = editingSessionName
            try FileStore.saveSession(session)

            // Save cover image if changed
            if let cover = editingSessionCover,
               let jpegData = cover.jpegData(compressionQuality: 0.8) {
                let coverURL = FileStore.sessionCoverURL(sessionID)
                try? jpegData.write(to: coverURL)
            }

            // Reload sessions list
            loadSessions()

            // Notify other views
            NotificationCenter.default.post(name: NSNotification.Name("ReloadSessions"), object: nil)
        } catch {
            // Handle error silently for now
        }

        editingSessionID = nil
    }

    private func deleteSession(_ sessionID: UUID) {
        do {
            try FileStore.deleteSession(sessionID)
            loadSessions()
        } catch {
            // Handle error silently for now
        }
    }

}

struct SessionGridItemView: View {
    let metadata: SessionMetadata
    @State private var coverImage: UIImage? = nil
    @State private var refreshID = UUID()

    var body: some View {
        VStack(spacing: 8) {
            // Square session cover or icon
            GeometryReader { geometry in
                ZStack {
                    if let coverImage = coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.tapelabButtonBg)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.system(size: 20))
                                    .foregroundColor(.tapelabLight)
                            )
                    }
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .id(refreshID)
            .onAppear {
                loadCoverImage()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadSessions"))) { _ in
                loadCoverImage()
                refreshID = UUID()
            }

            // Session title (max 16 characters)
            Text(String(metadata.name.prefix(16)))
                .font(.tapelabMono)
                .foregroundColor(TapelabTheme.Colors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
    }

    private func loadCoverImage() {
        coverImage = FileStore.loadSessionCover(metadata.id)
    }
}

#Preview {
    SessionsListView(onCreateSession: { _ in })
}
