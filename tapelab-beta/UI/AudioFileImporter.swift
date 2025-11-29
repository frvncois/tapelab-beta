//
//  AudioFileImporter.swift
//  tapelab-beta
//
//  UIKit wrapper for document picker to import audio files
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioFileImporter: UIViewControllerRepresentable {
    let onFileSelected: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Create document picker for audio files
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                UTType.audio,
                UTType.mpeg4Audio,
                UTType.mp3,
                UTType.wav,
                UTType.aiff
            ],
            asCopy: true // Copy file to our app sandbox
        )

        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false

        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFileSelected: onFileSelected, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFileSelected: (URL) -> Void
        let onCancel: () -> Void

        init(onFileSelected: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onFileSelected = onFileSelected
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }

            // When asCopy: true, iOS already copied the file to app's tmp/Inbox
            // The URL is already accessible without security-scoped resource access

            // Verify file exists and is accessible
            guard FileManager.default.fileExists(atPath: url.path) else {
                onCancel()
                return
            }


            // Copy to a more permanent temp location (Inbox may be cleaned up by iOS)
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("import_\(UUID().uuidString).\(url.pathExtension)")

            do {
                // Simple copy - no security-scoped access needed for Inbox files
                try FileManager.default.copyItem(at: url, to: tempURL)

                // Clean up the Inbox file (optional but good practice)
                try? FileManager.default.removeItem(at: url)

                onFileSelected(tempURL)

            } catch {
                onCancel()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
