//
//  ContactFormView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct ContactFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var fullName = ""
    @State private var email = ""
    @State private var subject = ""
    @State private var message = ""
    @State private var showConfirmation = false

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
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("CONTACT US")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                            // Email info
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Contact us directly by email at")
                                    .font(.tapelabMono)
                                    .foregroundColor(.tapelabLight)

                                Button(action: {
                                    if let url = URL(string: "mailto:hello@tapelab.app") {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("hello@tapelab.app")
                                            .font(.tapelabMonoBold)
                                            .foregroundColor(.tapelabAccentFull)

                                        Spacer()

                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 14))
                                            .foregroundColor(.tapelabAccentFull)
                                    }
                                    .padding(12)
                                    .background(Color.tapelabAccentFull.opacity(0.1))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.tapelabAccentFull, lineWidth: 1)
                                    )
                                }

                                Text("Or by filling this form:")
                                    .font(.tapelabMono)
                                    .foregroundColor(.tapelabLight)
                                    .padding(.top, 8)
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)

                            // Contact form
                            VStack(alignment: .leading, spacing: 16) {
                                // Full Name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("FULL NAME")
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabAccentFull)

                                    TextField("Enter your full name", text: $fullName)
                                        .font(.tapelabMono)
                                        .foregroundColor(.tapelabLight)
                                        .padding(12)
                                        .background(Color.tapelabButtonBg)
                                        .cornerRadius(6)
                                }

                                // Email
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("EMAIL")
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabAccentFull)

                                    TextField("Enter your email address", text: $email)
                                        .font(.tapelabMono)
                                        .foregroundColor(.tapelabLight)
                                        .padding(12)
                                        .background(Color.tapelabButtonBg)
                                        .cornerRadius(6)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                }

                                // Subject
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SUBJECT")
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabAccentFull)

                                    TextField("What is this about?", text: $subject)
                                        .font(.tapelabMono)
                                        .foregroundColor(.tapelabLight)
                                        .padding(12)
                                        .background(Color.tapelabButtonBg)
                                        .cornerRadius(6)
                                }

                                // Message
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("MESSAGE")
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabAccentFull)

                                    TextEditor(text: $message)
                                        .font(.tapelabMonoSmall)
                                        .foregroundColor(.tapelabLight)
                                        .frame(minHeight: 150)
                                        .padding(8)
                                        .background(Color.tapelabButtonBg)
                                        .cornerRadius(6)
                                        .scrollContentBackground(.hidden)
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)

                            // Submit button
                            Button(action: {
                                submitContactForm()
                            }) {
                                Text("SEND MESSAGE")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.tapelabRed)
                                    .cornerRadius(8)
                            }
                            .disabled(!canSubmit)
                            .opacity(canSubmit ? 1.0 : 0.5)

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

    private var confirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.tapelabGreen)

            VStack(spacing: 12) {
                Text("MESSAGE SENT!")
                    .font(.tapelabMonoHeadline)
                    .foregroundColor(.tapelabLight)

                Text("Thank you for reaching out. We'll get back to you as soon as possible.")
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

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitContactForm() {
        // Here you would send the contact form to your backend
        print("📧 Contact Form Submitted:")
        print("Name: \(fullName)")
        print("Email: \(email)")
        print("Subject: \(subject)")
        print("Message: \(message)")

        withAnimation {
            showConfirmation = true
        }
    }
}

#Preview {
    ContactFormView()
}
