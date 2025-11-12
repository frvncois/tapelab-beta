import SwiftUI

struct MixesListView: View {
    @State private var mixMetadata: [MixMetadata] = []
    @State private var selectedMix: Mix? = nil
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var sortOrder: SortOrder = .dateNewest
    @EnvironmentObject var runtime: AudioRuntime

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
        .sheet(item: $selectedMix) { mix in
            PlayerView(mix: mix, allMixes: mixMetadata)
                .environmentObject(runtime)
        }
        .onChange(of: selectedMix) { oldValue, newValue in
            if newValue != nil {
                // Suspend engine BEFORE presenting PlayerView
                print("🎵 MixesListView: Suspending engine for PlayerView")
                runtime.suspendForExternalPlayback()
            } else if oldValue != nil && newValue == nil {
                // Resume engine AFTER PlayerView dismisses
                print("🎵 MixesListView: Resuming engine after PlayerView")
                runtime.resumeAfterExternalPlayback()
            }
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
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteMixes)
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(TapelabTheme.Colors.background)
        .environment(\.editMode, .constant(.inactive))
        .accentColor(Color(red: 1.0, green: 0.231, blue: 0.188)) // iOS system red for delete
    }

    private func loadMixes() {
        do {
            mixMetadata = try FileStore.loadAllMixMetadata()
            sortMixes()
            print("📂 Loaded \(mixMetadata.count) mixes")
        } catch {
            print("⚠️ Failed to load mix metadata: \(error)")
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
        print("🔍 Opening mix with ID: \(mixID)")
        do {
            let mix = try FileStore.loadMix(mixID)
            print("✅ Loaded mix: \(mix.name)")
            print("🔍 Mix file URL: \(mix.fileURL)")
            selectedMix = mix  // This will trigger fullScreenCover
            print("🔍 selectedMix set, fullScreenCover should present")
        } catch {
            print("⚠️ Failed to load mix: \(error)")
        }
    }

    private func deleteMixes(at offsets: IndexSet) {
        for index in offsets {
            let metadata = mixMetadata[index]

            do {
                try FileStore.deleteMix(metadata.id)
                print("🗑️ Deleted mix: \(metadata.name)")
            } catch {
                print("⚠️ Failed to delete mix: \(error)")
            }
        }

        // Remove from local array
        mixMetadata.remove(atOffsets: offsets)
    }
}

struct MixMetadataRowView: View {
    let metadata: MixMetadata
    @State private var coverImage: UIImage? = nil

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
            .onAppear {
                loadCoverImage()
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
