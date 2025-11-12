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
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredMixes) { metadata in
                    Button(action: {
                        openMix(metadata.id)
                    }) {
                        MixGridItemView(metadata: metadata)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteMix(metadata.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
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

    private func deleteMix(_ mixID: UUID) {
        guard let index = mixMetadata.firstIndex(where: { $0.id == mixID }) else { return }

        do {
            try FileStore.deleteMix(mixID)
            print("🗑️ Deleted mix: \(mixMetadata[index].name)")
            mixMetadata.remove(at: index)
        } catch {
            print("⚠️ Failed to delete mix: \(error)")
        }
    }
}

struct MixGridItemView: View {
    let metadata: MixMetadata
    @State private var coverImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Square audio file visual
            GeometryReader { geometry in
                let size = geometry.size.width

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tapelabButtonBg)

                    // Cover image (if available) or waveform visual
                    if let coverImage = coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // Waveform-like visual
                        VStack(spacing: 0) {
                            Spacer()

                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(0..<20, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.tapelabAccentFull.opacity(0.6))
                                        .frame(width: 3)
                                        .frame(height: waveformHeight(for: index))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)

                            Spacer()
                        }
                    }

                    // Play icon overlay
                    Circle()
                        .fill(Color.tapelabOrange.opacity(0.9))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .offset(x: 2, y: 0)
                        )
                }
                .frame(width: size, height: size)
            }
            .aspectRatio(1, contentMode: .fit)
            .onAppear {
                coverImage = FileStore.loadMixCover(metadata.id)
            }

            // Mix info below
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.name)
                    .font(.tapelabMonoSmall)
                    .foregroundColor(TapelabTheme.Colors.text)
                    .lineLimit(1)

                Text(formatDuration(metadata.duration))
                    .font(.tapelabMonoTiny)
                    .foregroundColor(TapelabTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        // Create a pseudo-random waveform pattern based on index
        let baseHeight: CGFloat = 30
        let variation: CGFloat = 40
        let normalized = sin(Double(index) * 0.8) * 0.5 + 0.5
        return baseHeight + (variation * CGFloat(normalized))
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
