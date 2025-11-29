//
//  BugReportFormView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct BugReportFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 1
    @State private var showConfirmation = false

    // Form fields
    @State private var issuePersiststAfterClose = ""
    @State private var headphoneType = ""
    @State private var iphoneModel = ""
    @State private var iosVersion = ""
    @State private var issueCategory = ""
    @State private var issueDescription = ""
    @State private var name = ""
    @State private var email = ""
    @State private var moreDetails = ""

    let totalSteps = 7

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                if showConfirmation {
                    confirmationView
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Progress indicator
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("REPORT A BUG - STEP \(currentStep) OF \(totalSteps)")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(TapelabTheme.Colors.surface)
                                        .frame(height: 4)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.tapelabAccentFull)
                                        .frame(width: geometry.size.width * (CGFloat(currentStep) / CGFloat(totalSteps)), height: 4)
                                }
                            }
                            .frame(height: 4)

                            // Step content
                            VStack(alignment: .leading, spacing: 16) {
                                switch currentStep {
                                case 1:
                                    step1View
                                case 2:
                                    step2View
                                case 3:
                                    step3View
                                case 4:
                                    step4View
                                case 5:
                                    step5View
                                case 6:
                                    step6View
                                case 7:
                                    step7View
                                default:
                                    EmptyView()
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)

                            // Navigation buttons
                            HStack(spacing: 12) {
                                if currentStep > 1 {
                                    Button(action: {
                                        withAnimation {
                                            currentStep -= 1
                                        }
                                    }) {
                                        Text("BACK")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.tapelabButtonBg)
                                            .cornerRadius(8)
                                    }
                                }

                                Button(action: {
                                    if currentStep < totalSteps {
                                        withAnimation {
                                            currentStep += 1
                                        }
                                    } else {
                                        submitBugReport()
                                    }
                                }) {
                                    Text(currentStep < totalSteps ? "NEXT" : "SUBMIT")
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabLight)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.tapelabRed)
                                        .cornerRadius(8)
                                }
                                .disabled(!canProceed)
                                .opacity(canProceed ? 1.0 : 0.5)
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.tapelabAccentFull)
                    }
                }
            }
        }
    }

    // MARK: - Step Views

    private var step1View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Does the issue persist when you close the app?")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            VStack(spacing: 8) {
                optionButton("Yes", selection: $issuePersiststAfterClose)
                optionButton("No", selection: $issuePersiststAfterClose)
                optionButton("Not sure", selection: $issuePersiststAfterClose)
            }
        }
    }

    private var step2View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What type of headphone connection did you use?")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            VStack(spacing: 8) {
                optionButton("Wired (Lightning)", selection: $headphoneType)
                optionButton("Wired (USB-C)", selection: $headphoneType)
                optionButton("Bluetooth", selection: $headphoneType)
                optionButton("AirPods", selection: $headphoneType)
                optionButton("Built-in speaker", selection: $headphoneType)
                optionButton("Other", selection: $headphoneType)
            }
        }
    }

    private var step3View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is your iPhone model?")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            TextField("e.g., iPhone 15 Pro", text: $iphoneModel)
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)
                .padding(12)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)
        }
    }

    private var step4View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is your iOS version?")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            TextField("e.g., iOS 17.2", text: $iosVersion)
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)
                .padding(12)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)
        }
    }

    private var step5View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is the issue related to?")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            VStack(spacing: 8) {
                optionButton("Recording", selection: $issueCategory)
                optionButton("Playing", selection: $issueCategory)
                optionButton("Playback", selection: $issueCategory)
                optionButton("Effect", selection: $issueCategory)
                optionButton("Export", selection: $issueCategory)
                optionButton("Import", selection: $issueCategory)
                optionButton("Mix", selection: $issueCategory)
                optionButton("Sessions", selection: $issueCategory)
                optionButton("Other", selection: $issueCategory)
            }
        }
    }

    private var step6View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe the issue")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            TextEditor(text: $issueDescription)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)
                .scrollContentBackground(.hidden)

            Text("Your name & email")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)
                .padding(.top, 8)

            TextField("Full name", text: $name)
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)
                .padding(12)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)

            TextField("Email address", text: $email)
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)
                .padding(12)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        }
    }

    private var step7View: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More details (optional)")
                .font(.tapelabMono)
                .foregroundColor(.tapelabLight)

            Text("Any additional information that might help us understand and fix the issue")
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight.opacity(0.7))

            TextEditor(text: $moreDetails)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.tapelabButtonBg)
                .cornerRadius(6)
                .scrollContentBackground(.hidden)
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.tapelabGreen)

            VStack(spacing: 12) {
                Text("THANK YOU!")
                    .font(.tapelabMonoHeadline)
                    .foregroundColor(.tapelabLight)

                Text("We received your bug report and will review it. We might contact you to know more details about your report. We take these very seriously.")
                    .font(.tapelabMono)
                    .foregroundColor(.tapelabLight.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Button(action: {
                dismiss()
            }) {
                Text("CLOSE")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.tapelabAccentFull)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()
        }
    }

    // MARK: - Helper Views

    private func optionButton(_ title: String, selection: Binding<String>) -> some View {
        Button(action: {
            selection.wrappedValue = title
        }) {
            HStack {
                Text(title.uppercased())
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)

                Spacer()

                if selection.wrappedValue == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.tapelabAccentFull)
                }
            }
            .padding(12)
            .background(selection.wrappedValue == title ? Color.tapelabAccentFull.opacity(0.1) : Color.tapelabButtonBg)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selection.wrappedValue == title ? Color.tapelabAccentFull : Color.clear, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private var canProceed: Bool {
        switch currentStep {
        case 1:
            return !issuePersiststAfterClose.isEmpty
        case 2:
            return !headphoneType.isEmpty
        case 3:
            return !iphoneModel.trimmingCharacters(in: .whitespaces).isEmpty
        case 4:
            return !iosVersion.trimmingCharacters(in: .whitespaces).isEmpty
        case 5:
            return !issueCategory.isEmpty
        case 6:
            return !issueDescription.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !name.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !email.trimmingCharacters(in: .whitespaces).isEmpty
        case 7:
            return true // Optional step
        default:
            return false
        }
    }

    private func submitBugReport() {
        // Here you would send the bug report to your backend

        withAnimation {
            showConfirmation = true
        }
    }
}

#Preview {
    BugReportFormView()
}
