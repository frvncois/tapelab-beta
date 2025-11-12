//
//  PrivacyPolicyView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct PrivacyPolicyView: View {
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

                            Text("PRIVACY POLICY")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight)
                        }
                        .padding(.top, 8)

                        // Privacy Policy content
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Effective Date: [Insert Date]")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))

                            Text("Last Updated: [Insert Date]")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight.opacity(0.7))

                            // Introduction
                            sectionHeader("1. Introduction")
                            sectionText("FRVNCOIS (\"we,\" \"us,\" or \"our\") operates the Tapelab mobile application (\"App\"). This Privacy Policy explains how we collect, use, disclose, and protect your information when you use our App.\n\nWe are committed to protecting your privacy. Tapelab is designed with privacy as a core principle - we do not collect, store, or have access to your recordings or personal data.\n\nBy using Tapelab, you agree to the terms of this Privacy Policy. If you do not agree, please do not use the App.")

                            // Information We Do NOT Collect
                            sectionHeader("2. Information We Do NOT Collect")

                            subsectionHeader("2.1 Your Recordings and Projects")
                            sectionText("• All audio recordings, sessions, mixes, and projects are stored locally on your device only\n• We do not upload, transmit, or have access to any of your audio content\n• We cannot view, listen to, or retrieve your recordings\n• Your creative work remains entirely private and under your control")

                            subsectionHeader("2.2 Personal Information")
                            sectionText("• We do not require account creation\n• We do not collect names, phone numbers, addresses, or identification documents\n• We do not track your location\n• We do not access your contacts, photos, or other personal data on your device")

                            // Information We MAY Collect
                            sectionHeader("3. Information We MAY Collect")

                            subsectionHeader("3.1 Email Addresses (Optional)")
                            sectionText("• Collection: Only if you voluntarily opt-in to receive marketing communications\n• Purpose: To send updates, news, and promotional information about Tapelab\n• Opt-Out: You may unsubscribe at any time using the link in our emails or by contacting us at hello@tapelab.app\n• Storage: Email addresses are stored securely and are not shared with third parties for their marketing purposes")

                            subsectionHeader("3.2 Crash Reports and Technical Data")
                            sectionText("• Service Provider: We use Sentry.io for automatic crash reporting and bug tracking\n• Information Collected: Device model and iOS version, App version, Crash logs and error messages, Technical performance data\n• Purpose: To identify and fix bugs, improve app stability, and enhance user experience\n• What is NOT Collected: This data does not include your recordings, personal information, or any content you create\n• Third Party: Sentry.io's privacy practices are governed by their privacy policy")

                            subsectionHeader("3.3 App Store Data")
                            sectionText("• Purchase Information: When you purchase the Pro version, the transaction is processed entirely through Apple's App Store\n• Apple's Control: We do not have access to your payment information, credit card details, or full purchase history\n• What We May Receive: Apple may provide us with anonymous, aggregated statistics about downloads and purchases")

                            // How We Use Information
                            sectionHeader("4. How We Use Information")
                            sectionText("The limited information we collect is used solely for:\n\n• Email Communications: Sending promotional emails and updates (only if you opted in)\n• App Improvement: Analyzing crash reports to fix bugs and improve performance\n• Legal Compliance: Complying with applicable laws and regulations\n• Support: Responding to your inquiries when you contact us\n\nWe do NOT use your information for:\n• Selling or renting to third parties\n• Targeted advertising\n• Profiling or behavioral tracking\n• Any purpose other than those stated above")

                            // Data Storage and Security
                            sectionHeader("5. Data Storage and Security")

                            subsectionHeader("5.1 Local Storage")
                            sectionText("Your recordings and all creative content are stored exclusively on your device using iOS's secure file system. This data never leaves your device unless you explicitly choose to export or share it.")

                            subsectionHeader("5.2 Your Responsibility")
                            sectionText("You are responsible for:\n• Backing up your recordings through iCloud, iTunes, or other methods\n• Securing your device with a passcode or biometric lock\n• Protecting your data from loss or theft\n\nWe cannot:\n• Retrieve lost or deleted recordings\n• Access your data if your device is lost or damaged\n• Restore projects that were not backed up")

                            subsectionHeader("5.3 Email Security")
                            sectionText("Email addresses (if provided) are stored securely using industry-standard practices. However, no method of electronic storage is 100% secure, and we cannot guarantee absolute security.")

                            // Data Sharing and Disclosure
                            sectionHeader("6. Data Sharing and Disclosure")

                            subsectionHeader("6.1 We Do Not Sell Your Data")
                            sectionText("We do not sell, trade, or rent your personal information to third parties.")

                            subsectionHeader("6.2 Third-Party Service Providers")
                            sectionText("We may share limited technical data with:\n• Sentry.io: For crash reporting and bug tracking\n• Email Service Provider: To send marketing emails if you opted in\n\nThese service providers are contractually obligated to protect your information and use it only for the purposes we specify.")

                            subsectionHeader("6.3 Legal Requirements")
                            sectionText("We may disclose information if required to:\n• Comply with legal obligations, court orders, or government requests\n• Enforce our Terms of Use\n• Protect our rights, property, or safety, or that of our users or the public\n• Prevent fraud or illegal activity")

                            subsectionHeader("6.4 Business Transfers")
                            sectionText("If FRVNCOIS is acquired by or merged with another company, user information may be transferred as part of that transaction. You will be notified of any such change.")

                            // Your Rights and Choices
                            sectionHeader("7. Your Rights and Choices")

                            subsectionHeader("7.1 Access and Control")
                            sectionText("Since your recordings are stored locally on your device, you have complete control over:\n• Accessing your data at any time\n• Deleting recordings or projects\n• Exporting and backing up your content")

                            subsectionHeader("7.2 Email Opt-Out")
                            sectionText("If you opted in to marketing emails, you may:\n• Unsubscribe using the link in any email\n• Contact us at hello@tapelab.app to be removed from our mailing list")

                            subsectionHeader("7.3 Crash Reporting")
                            sectionText("Currently, crash reporting through Sentry.io is automatic to help us improve the App. If you wish to limit this data collection, please contact us.")

                            subsectionHeader("7.4 Data Deletion")
                            sectionText("To request deletion of your email address from our records, contact us at hello@tapelab.app. Note that we cannot delete recordings stored on your device - you must do this directly through the App or your device settings.")

                            // Children's Privacy
                            sectionHeader("8. Children's Privacy")
                            sectionText("Tapelab does not knowingly collect personal information from children under the age of 13 (or the applicable age of digital consent in your jurisdiction).\n\n• We do not require age verification since we do not collect personal data\n• Parents and guardians should supervise children's use of the App\n• If you believe we have inadvertently collected information from a child, please contact us immediately at hello@tapelab.app")

                            // International Users
                            sectionHeader("9. International Users")

                            subsectionHeader("9.1 Data Location")
                            sectionText("FRVNCOIS is based in Montreal, Quebec, Canada. Any data we collect (limited to optional email addresses and crash reports) is processed in Canada or by our service providers, which may be located in other countries.")

                            subsectionHeader("9.2 Data Transfers")
                            sectionText("By using Tapelab, you consent to the transfer of information to Canada and other countries where our service providers operate, which may have different data protection laws than your jurisdiction.")

                            subsectionHeader("9.3 European Users")
                            sectionText("If you are located in the European Economic Area (EEA), United Kingdom, or Switzerland, you may have additional rights under the General Data Protection Regulation (GDPR), including:\n• Right to access your data\n• Right to rectification\n• Right to erasure (\"right to be forgotten\")\n• Right to restrict processing\n• Right to data portability\n• Right to object to processing\n\nTo exercise these rights, contact us at hello@tapelab.app.")

                            // California Privacy Rights
                            sectionHeader("10. California Privacy Rights")
                            sectionText("If you are a California resident, the California Consumer Privacy Act (CCPA) provides you with specific rights regarding your personal information:\n\n• Right to Know: You can request information about the data we collect and how it's used\n• Right to Delete: You can request deletion of your personal information\n• Right to Opt-Out: We do not sell personal information, so no opt-out is necessary\n• Non-Discrimination: We will not discriminate against you for exercising your rights\n\nTo exercise these rights, contact us at hello@tapelab.app.")

                            // Contact Us
                            sectionHeader("14. Contact Us")
                            sectionText("If you have questions, concerns, or requests regarding this Privacy Policy or our privacy practices, please contact us:\n\nEmail: hello@tapelab.app\n\nDeveloper: FRVNCOIS\nLocation: Montreal, Quebec, Canada\n\nWe will respond to your inquiry within a reasonable timeframe.")

                            // Summary
                            sectionHeader("Summary")
                            sectionText("• We don't collect your recordings - they stay on your device\n• We only collect email addresses if you opt-in for marketing\n• We use Sentry.io for crash reports to improve the App\n• You have full control over your data\n• We don't sell or share your information for marketing")

                            // Footer
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
    PrivacyPolicyView()
}
