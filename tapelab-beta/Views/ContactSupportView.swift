//
//  ContactSupportView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showBugReportForm = false
    @State private var showContactForm = false

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Section header with dot
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.tapelabLight)
                                .frame(width: 3, height: 3)

                            Text("CONTACT SUPPORT")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                        // Support options
                        VStack(spacing: 16) {
                            // Report a Bug button
                            Button(action: {
                                showBugReportForm = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "ladybug")
                                        .font(.system(size: 20))
                                        .foregroundColor(.tapelabAccentFull)
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("REPORT A BUG")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)

                                        Text("Help us improve Tapelab")
                                            .font(.tapelabMonoTiny)
                                            .foregroundColor(.tapelabLight.opacity(0.6))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.tapelabLight.opacity(0.4))
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)
                            }

                            // Contact Us button
                            Button(action: {
                                showContactForm = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 20))
                                        .foregroundColor(.tapelabAccentFull)
                                        .frame(width: 32)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("CONTACT US")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)

                                        Text("Get in touch with our team")
                                            .font(.tapelabMonoTiny)
                                            .foregroundColor(.tapelabLight.opacity(0.6))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.tapelabLight.opacity(0.4))
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
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
            .sheet(isPresented: $showBugReportForm) {
                BugReportFormView()
            }
            .sheet(isPresented: $showContactForm) {
                ContactFormView()
            }
        }
    }
}

#Preview {
    ContactSupportView()
}
