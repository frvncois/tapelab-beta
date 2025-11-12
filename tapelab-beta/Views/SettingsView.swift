import SwiftUI
import Lottie

struct SettingsView: View {
    @State private var showAboutView = false
    @State private var showTermsView = false
    @State private var showPrivacyView = false
    @State private var showContactSupport = false
    @State private var showHelpCenter = false

    var body: some View {
        ZStack {
            TapelabTheme.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Pro Plan Card
                    ProPlanCard()

                    // Help & Support Box with Lottie
                    HelpSupportCard(showHelpCenter: $showHelpCenter)

                    // About Section
                    SettingsSectionView(title: "About") {
                        SettingsRowView(
                            icon: "info.circle",
                            title: "About Tapelab",
                            action: {
                                showAboutView = true
                            }
                        )
                        SettingsRowView(
                            icon: "doc.text",
                            title: "Terms of Service",
                            action: {
                                showTermsView = true
                            }
                        )
                        SettingsRowView(
                            icon: "hand.raised",
                            title: "Privacy Policy",
                            action: {
                                showPrivacyView = true
                            }
                        )
                        SettingsRowView(
                            icon: "envelope",
                            title: "Contact Support",
                            showSeparator: false,
                            action: {
                                showContactSupport = true
                            }
                        )
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showAboutView) {
            AboutView()
        }
        .sheet(isPresented: $showTermsView) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showPrivacyView) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showContactSupport) {
            ContactSupportView()
        }
        .sheet(isPresented: $showHelpCenter) {
            HelpCenterView()
        }
    }
}

struct HelpSupportCard: View {
    @Binding var showHelpCenter: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Square container with background image and Lottie
            ZStack {
                // Background image
                Image("background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)

                // Lottie animation overlay
                LottieView(animation: .named("loop"))
                    .playing(loopMode: .loop)
                    .resizable()
                    .frame(width: 200, height: 200)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .cornerRadius(12)

            // Help Center button
            Button(action: {
                showHelpCenter = true
            }) {
                Text("HELP CENTER")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.tapelabRed)
                    .cornerRadius(8)
            }
        }
    }
}

struct ProPlanCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.tapelabRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TAPELAB PRO")
                        .font(.tapelabMonoBold)
                        .foregroundColor(.tapelabLight)

                    Text("$4.99/month")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabAccentFull.opacity(0.7))
                }

                Spacer()
            }

            // Features List
            VStack(alignment: .leading, spacing: 12) {
                ProFeatureRow(icon: "infinity", label: "Sessions", value: "Unlimited")
                ProFeatureRow(icon: "clock", label: "Length", value: "8 minutes")
                ProFeatureRow(icon: "music.note", label: "Mixes", value: "Unlimited")
                ProFeatureRow(icon: "metronome", label: "Metronome", value: "Yes")
                ProFeatureRow(icon: "tuningfork", label: "Tuner", value: "Yes")
            }

            // Subscribe Button
            Button(action: {
                // TODO: Handle subscription
            }) {
                Text("SUBSCRIBE TO PRO")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.tapelabRed)
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .background(TapelabTheme.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tapelabRed.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ProFeatureRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.tapelabAccentFull)
                .frame(width: 24, height: 24)

            Text(label)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)

            Spacer()

            Text(value)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabAccentFull)
        }
    }
}

struct SettingsSectionView<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Badge-style section title with dot
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.tapelabLight)
                    .frame(width: 3, height: 3)

                Text(title.uppercased())
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.tapelabLight)
            }

            VStack(spacing: 0) {
                content
            }
            .background(TapelabTheme.Colors.surface)
            .cornerRadius(8)
        }
    }
}

struct SettingsRowView: View {
    let icon: String
    let title: String
    let action: () -> Void
    let showSeparator: Bool

    init(icon: String, title: String, showSeparator: Bool = true, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.showSeparator = showSeparator
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.tapelabLight)
                        .frame(width: 24, height: 24)

                    // Text content
                    Text(title.uppercased())
                        .font(.tapelabMonoSmall)
                        .foregroundColor(TapelabTheme.Colors.text)

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(TapelabTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(TapelabTheme.Colors.surface)
            }
        }
    }
}

#Preview {
    SettingsView()
}
