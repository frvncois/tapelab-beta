import SwiftUI

struct MixesListView: View {
    @State private var mixMetadata: [MixMetadata] = []
    @State private var selectedMix: Mix? = nil
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var sortOrder: SortOrder = .dateNewest
    @EnvironmentObject var runtime: AudioRuntime

    // Edit mix state
    @State private var showEditSheet = false
    @State private var editingMixID: UUID?
    @State private var editingMixName: String = ""
    @State private var editingMixCover: UIImage?

    // Delete confirmation state
    @State private var showDeleteConfirmation = false
    @State private var deletingMixID: UUID?

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
                // Header (only show if there are mixes)
                if !mixMetadata.isEmpty {
                    listHeader
                        .padding(.bottom, 20)
                }

                if mixMetadata.isEmpty {
                    emptyStateView
                } else {
                    mixesList
                }
            }
        }
        .onAppear {
            loadMixes()
        }
        .onDisappear {
            // Reset search when leaving view
            searchText = ""
            isSearching = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadMixes"))) { _ in
            loadMixes()
        }
        .sheet(item: $selectedMix) { mix in
            PlayerView(mix: mix, allMixes: mixMetadata)
                .environmentObject(runtime)
        }
        .onChange(of: selectedMix) { oldValue, newValue in
            if newValue != nil {
                // Suspend engine BEFORE presenting PlayerView
                runtime.suspendForExternalPlayback()
            } else if oldValue != nil && newValue == nil {
                // Resume engine AFTER PlayerView dismisses
                runtime.resumeAfterExternalPlayback()
            }
        }
        .alert(
            "Delete Mix",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                deletingMixID = nil
            }
            Button("Delete", role: .destructive) {
                if let mixID = deletingMixID {
                    deleteMix(mixID)
                }
                deletingMixID = nil
            }
        } message: {
            Text("Are you sure you want to delete this mix? This action cannot be undone.")
        }
        .sheet(isPresented: $showEditSheet) {
            MixInfoSheet(
                mixName: $editingMixName,
                coverImage: $editingMixCover,
                onSave: {
                    saveEditedMix()
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
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

                    Text("MIXES")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                }

                Spacer()

                // Sort Menu (rounded)
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button(action: {
                            sortOrder = order
                            sortMixes()
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

                    TextField("Search mixes...", text: $searchText)
                        .font(.tapelabMono)
                        .foregroundColor(.tapelabLight)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(Color.tapelabButtonBg)
                .cornerRadius(8)
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(TapelabTheme.Colors.text.opacity(0.25))

            Text("NO MIXES YET")
                .font(.tapelabMonoSmall)
                .foregroundColor(TapelabTheme.Colors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredMixes: [MixMetadata] {
        if searchText.isEmpty {
            return mixMetadata
        } else {
            return mixMetadata.filter { mix in
                mix.name.localizedCaseInsensitiveContains(searchText) ||
                mix.sessionName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var mixesList: some View {
        List {
            ForEach(filteredMixes) { metadata in
                Button(action: {
                    openMix(metadata.id)
                }) {
                    MixMetadataRowView(metadata: metadata)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowBackground(TapelabTheme.Colors.background)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button(action: {
                        shareMix(metadata.id)
                    }) {
                        Label("Share Mix", systemImage: "square.and.arrow.up")
                    }

                    Button(action: {
                        editMix(metadata)
                    }) {
                        Label("Edit Mix", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        deletingMixID = metadata.id
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Mix", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(TapelabTheme.Colors.background)
        .environment(\.editMode, .constant(.inactive))
    }

    private func loadMixes() {
        do {
            mixMetadata = try FileStore.loadAllMixMetadata()
            sortMixes()
        } catch {
            mixMetadata = []
        }
    }

    private func sortMixes() {
        switch sortOrder {
        case .dateNewest:
            mixMetadata.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            mixMetadata.sort { $0.createdAt < $1.createdAt }
        case .nameAZ:
            mixMetadata.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameZA:
            mixMetadata.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }

    private func openMix(_ mixID: UUID) {
        do {
            let mix = try FileStore.loadMix(mixID)
            selectedMix = mix  // This will trigger fullScreenCover
        } catch {
        }
    }

    private func shareMix(_ mixID: UUID) {
        do {
            let mix = try FileStore.loadMix(mixID)

            // Create activity view controller with the audio file
            let activityVC = UIActivityViewController(
                activityItems: [mix.fileURL],
                applicationActivities: nil
            )

            // Configure for iPad (required for popover presentation)
            if let popoverController = activityVC.popoverPresentationController {
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
                var topController = rootVC
                while let presentedVC = topController.presentedViewController {
                    topController = presentedVC
                }
                topController.present(activityVC, animated: true)
            }
        } catch {
            // Handle error silently
        }
    }

    private func editMix(_ metadata: MixMetadata) {
        editingMixID = metadata.id
        editingMixName = metadata.name
        editingMixCover = FileStore.loadMixCover(metadata.id)
        showEditSheet = true
    }

    private func saveEditedMix() {
        guard let mixID = editingMixID else { return }

        do {
            // Load the full mix
            var mix = try FileStore.loadMix(mixID)
            // Update the name
            mix.name = editingMixName
            try FileStore.saveMix(mix)

            // Save cover image if changed
            if let cover = editingMixCover {
                try? FileStore.saveMixCover(cover, for: mixID)
            }

            // Reload mixes list
            loadMixes()

            // Notify to reload cover images
            NotificationCenter.default.post(name: NSNotification.Name("ReloadMixes"), object: nil)
        } catch {
            // Handle error silently
        }

        editingMixID = nil
    }

    private func deleteMix(_ mixID: UUID) {
        do {
            try FileStore.deleteMix(mixID)
            loadMixes()
        } catch {
            // Handle error silently
        }
    }
}

struct MixMetadataRowView: View {
    let metadata: MixMetadata
    @State private var coverImage: UIImage? = nil
    @State private var refreshID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            // Mix cover or icon
            ZStack {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tapelabDark)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(TapelabTheme.Colors.accent)
                        )
                }
            }
            .id(refreshID)
            .onAppear {
                loadCoverImage()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReloadMixes"))) { _ in
                loadCoverImage()
                refreshID = UUID()
            }

            // Mix info
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.name)
                    .font(.tapelabMono)
                    .foregroundColor(TapelabTheme.Colors.text)

                Text(formatDuration(metadata.duration))
                    .font(.tapelabMonoTiny)
                    .foregroundColor(TapelabTheme.Colors.textSecondary)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(TapelabTheme.Colors.textSecondary)
        }
        .padding(12)
        .background(Color.tapelabButtonBg)
        .cornerRadius(8)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
    }

    private func loadCoverImage() {
        coverImage = FileStore.loadMixCover(metadata.id)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MixesListView()
}
