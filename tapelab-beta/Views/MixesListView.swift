import SwiftUI

struct MixesListView: View {
    @State private var mixMetadata: [MixMetadata] = []
    @State private var selectedMix: Mix? = nil
    @EnvironmentObject var runtime: AudioRuntime

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
        .fullScreenCover(item: $selectedMix) { mix in
            PlayerView(mix: mix)
                .environmentObject(runtime)
        }
    }

    private var listHeader: some View {
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

            // Delete all button (temporary - for cleaning old Float32 mixes)
            Button(action: {
                deleteAllMixes()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.tapelabButtonBg)
                    .cornerRadius(16)
            }

            // Refresh button
            Button(action: {
                loadMixes()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .foregroundColor(.tapelabLight)
                    .frame(width: 32, height: 32)
                    .background(Color.tapelabButtonBg)
                    .cornerRadius(16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
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

    private var mixesList: some View {
        List {
            ForEach(mixMetadata) { metadata in
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
        .accentColor(Color(red: 1.0, green: 0.231, blue: 0.188))
    }

    private func loadMixes() {
        do {
            mixMetadata = try FileStore.loadAllMixMetadata()
            print("📂 Loaded \(mixMetadata.count) mixes")
        } catch {
            print("⚠️ Failed to load mix metadata: \(error)")
            mixMetadata = []
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

        mixMetadata.remove(atOffsets: offsets)
    }

    private func deleteAllMixes() {
        print("🗑️ Deleting all mixes...")
        for metadata in mixMetadata {
            do {
                try FileStore.deleteMix(metadata.id)
                print("🗑️ Deleted mix: \(metadata.name)")
            } catch {
                print("⚠️ Failed to delete mix: \(error)")
            }
        }
        mixMetadata.removeAll()
        print("✅ All mixes deleted")
    }
}

struct MixMetadataRowView: View {
    let metadata: MixMetadata

    var body: some View {
        HStack(spacing: 12) {
            // Mix icon
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tapelabDark)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(TapelabTheme.Colors.accent)
                )

            // Mix info
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.name)
                    .font(.tapelabMono)
                    .foregroundColor(TapelabTheme.Colors.text)

                HStack(spacing: 8) {
                    Text(formatDuration(metadata.duration))
                        .font(.tapelabMonoSmall)
                        .foregroundColor(TapelabTheme.Colors.textSecondary)

                    Text("•")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(TapelabTheme.Colors.textSecondary)

                    Text(metadata.sessionName)
                        .font(.tapelabMonoSmall)
                        .foregroundColor(TapelabTheme.Colors.textSecondary)
                }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MixesListView()
}
