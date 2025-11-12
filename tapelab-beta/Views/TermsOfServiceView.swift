//
//  TermsOfServiceView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section header with dot
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.tapelabLight)
                                .frame(width: 3, height: 3)

                            Text("TERMS OF USE")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight)
                        }
                        .padding(.top, 8)

                        // Terms content
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Effective Date: [Insert Date]")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))

                            Text("Last Updated: [Insert Date]")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))

                            // Introduction
                            sectionHeader("1. Introduction")
                            sectionText("Welcome to Tapelab (\"App\"), a multitrack recording and editing application for iOS. These Terms of Use (\"Terms\") constitute a legal agreement between you (\"User,\" \"you,\" or \"your\") and FRVNCOIS, a business registered in Quebec, Canada (\"we,\" \"us,\" or \"our\").\n\nBy downloading, installing, or using Tapelab, you agree to be bound by these Terms. If you do not agree to these Terms, do not use the App.")

                            // Eligibility
                            sectionHeader("2. Eligibility")
                            sectionText("Tapelab is available to users of all ages. By using the App, you represent that you have the legal capacity to enter into these Terms. If you are under the age of majority in your jurisdiction, you confirm that you have obtained parental or guardian consent to use the App.")

                            // License Grant
                            sectionHeader("3. License Grant")
                            sectionText("Subject to your compliance with these Terms, we grant you a limited, non-exclusive, non-transferable, revocable license to download, install, and use Tapelab on iOS devices that you own or control, solely for your personal, non-commercial use.")

                            // Account and Authentication
                            sectionHeader("4. Account and Authentication")
                            sectionText("Tapelab does not require account creation or third-party login services. All user data is stored locally on your device.")

                            // Free and Pro Versions
                            sectionHeader("5. Free and Pro Versions")

                            subsectionHeader("5.1 Free Version")
                            sectionText("The free version of Tapelab includes:\n• Up to 4 recording sessions\n• Up to 4 mixes\n• Basic recording and editing features")

                            subsectionHeader("5.2 Pro Version")
                            sectionText("The Pro version unlocks:\n• Unlimited recording sessions\n• Unlimited mixes\n• In-app tuner\n• In-app metronome\n• Ability to share sessions with other users")

                            subsectionHeader("5.3 Purchase Terms")
                            sectionText("• Pro version is available as an in-app purchase through Apple's App Store\n• All purchases are processed through Apple Pay\n• No free trial is offered\n• All sales are final - no refunds will be provided\n• Pricing is displayed in the App Store and may vary by region\n• It is your responsibility to test the App thoroughly on the free version to ensure compatibility with your device before purchasing the Pro version")

                            // System Requirements
                            sectionHeader("6. System Requirements and Device Compatibility")

                            subsectionHeader("6.1 Minimum Requirements")
                            sectionText("To use Tapelab, you must have:\n• iPhone running iOS 17 or later\n• iPhone 15 or newer model (recommended for optimal performance)\n• Working microphone\n• Headphones or audio output device\n• Up-to-date iOS software")

                            subsectionHeader("6.2 Performance Notice")
                            sectionText("Tapelab is a resource-intensive application that requires significant processing power. Performance may vary depending on your device model and specifications. You are solely responsible for ensuring your device meets the necessary requirements and testing the App on the free version before purchasing Pro features.")

                            subsectionHeader("6.3 Technical Limitations")
                            sectionText("• The App does not support live monitoring due to physical hardware limitations of iOS devices\n• Audio latency and processing are subject to device capabilities\n• We are not responsible for performance issues related to your device's hardware or software configuration")

                            // User Data and Privacy
                            sectionHeader("7. User Data and Privacy")

                            subsectionHeader("7.1 Data Storage")
                            sectionText("All audio recordings, sessions, mixes, and user-generated content are stored locally on your device only. We do not collect, store, or have access to your recordings or project files.")

                            subsectionHeader("7.2 Data Backup")
                            sectionText("You are solely responsible for backing up your data. We cannot retrieve, recover, or restore any lost data. We strongly recommend regularly backing up your recordings through iCloud, iTunes, or other backup methods.")

                            subsectionHeader("7.3 Information Collection")
                            sectionText("We do not collect personal information except:\n• Email addresses, only if you voluntarily opt-in to receive marketing communications\n• Automatic crash reports and bug data through Sentry.io, which does not contain sensitive personal information")

                            subsectionHeader("7.4 Privacy Policy")
                            sectionText("A separate Privacy Policy is available and governs our data practices.")

                            // User Content and Ownership
                            sectionHeader("8. User Content and Ownership")

                            subsectionHeader("8.1 Your Ownership")
                            sectionText("You retain full ownership of all audio recordings, sessions, and content you create using Tapelab (\"User Content\").")

                            subsectionHeader("8.2 Your Responsibility")
                            sectionText("You are solely responsible for:\n• All User Content you create, record, edit, or share\n• Ensuring you have the necessary rights and permissions for any content you record or incorporate into your projects\n• Compliance with all applicable laws regarding your User Content\n• The distribution, sharing, or public performance of your recordings")

                            subsectionHeader("8.3 Export and Sharing")
                            sectionText("You may export and share your recordings. We provide the technical tools for recording and editing only. We assume no responsibility or liability for how you use, distribute, or share your content.")

                            // Prohibited Conduct
                            sectionHeader("9. Prohibited Conduct")
                            sectionText("You agree NOT to:")

                            subsectionHeader("9.1 Copyright Infringement")
                            sectionText("• Record, reproduce, or incorporate copyrighted material without proper authorization\n• Violate intellectual property rights of others\n• Use the App to create infringing derivative works")

                            subsectionHeader("9.2 Illegal Activity")
                            sectionText("• Use the App for any unlawful purpose\n• Record individuals without their consent where legally required\n• Violate any applicable local, provincial, federal, or international laws")

                            subsectionHeader("9.3 System Interference")
                            sectionText("• Attempt to reverse engineer, decompile, or disassemble the App\n• Circumvent any technical limitations or security measures\n• Use the App in any manner that could damage, disable, or impair our services\n• Introduce viruses, malware, or other malicious code")

                            subsectionHeader("9.4 Unauthorized Use")
                            sectionText("• Sell, rent, lease, or sublicense the App\n• Use the App for commercial purposes without authorization\n• Remove or alter any copyright, trademark, or proprietary notices")

                            // Contact Information
                            sectionHeader("19. Contact Information")
                            sectionText("For questions, concerns, or support regarding Tapelab or these Terms, please contact us:\n\nEmail: hello@tapelab.app\n\nDeveloper: FRVNCOIS\nLocation: Montreal, Quebec, Canada")

                            // Footer
                            Text("By using Tapelab, you acknowledge that you have read, understood, and agree to be bound by these Terms of Use.")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))
                                .padding(.top, 8)

                            Text("Last Updated: [Insert Date]\nVersion: 1.0")
                                .font(.tapelabMonoTiny)
                                .foregroundColor(.tapelabLight.opacity(0.5))
                                .padding(.top, 4)
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
        }
    }

    // Helper function for section headers
    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.tapelabMonoBold)
            .foregroundColor(.tapelabAccentFull)
            .padding(.top, 8)
    }

    // Helper function for subsection headers
    @ViewBuilder
    private func subsectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.tapelabMono)
            .foregroundColor(.tapelabAccentFull.opacity(0.8))
            .padding(.top, 4)
    }

    // Helper function for section text
    @ViewBuilder
    private func sectionText(_ text: String) -> some View {
        Text(text)
            .font(.tapelabMonoSmall)
            .foregroundColor(.tapelabLight)
            .lineSpacing(4)
    }
}

#Preview {
    TermsOfServiceView()
}
