import SwiftUI
import PhotosUI

struct SessionInfoSheet: View {
    @Binding var sessionName: String
    @Binding var coverImage: UIImage?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var selectedItem: PhotosPickerItem? = nil
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            TapelabTheme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Title
                Text("SESSION INFO")
                    .font(.tapelabMonoBold)
                    .foregroundColor(.tapelabLight)
                    .padding(.top, 20)

                // Cover Photo Section
                VStack(spacing: 12) {
                    Text("COVER PHOTO")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabAccentFull.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            if let coverImage = coverImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TapelabTheme.Colors.surface)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 32))
                                                .foregroundColor(.tapelabAccentFull)

                                            Text("ADD PHOTO")
                                                .font(.tapelabMonoTiny)
                                                .foregroundColor(.tapelabLight)
                                        }
                                    )
                            }
                        }
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    coverImage = uiImage
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Session Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("SESSION NAME")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabAccentFull.opacity(0.7))

                    TextField("Session name", text: $sessionName)
                        .font(.tapelabMono)
                        .foregroundColor(.tapelabLight)
                        .padding(12)
                        .background(TapelabTheme.Colors.surface)
                        .cornerRadius(8)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)

                // Buttons
                HStack(spacing: 12) {
                    // Cancel Button
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabLight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.tapelabButtonBg)
                            .cornerRadius(8)
                    }

                    // Save Button
                    Button(action: onSave) {
                        Text("SAVE")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabLight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.tapelabRed)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onAppear {
            // Auto-focus the text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

#Preview {
    SessionInfoSheet(
        sessionName: .constant("My Session"),
        coverImage: .constant(nil),
        onSave: {},
        onCancel: {}
    )
}
