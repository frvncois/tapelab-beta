//
//  TapelabTheme.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

// MARK: - Tapelab Color System
extension Color {
    // Brand Colors
    static let tapelabDark = Color(hex: "1D1613")
    static let tapelabBlack = Color(hex: "17120F")
    static let tapelabAccentFull = Color(hex: "#FFCBB4") // Full opacity version for buttons
    static let tapelabAccent = Color(hex: "C3B9A1", opacity: 0.1) // 10% opacity version
    static let tapelabRed = Color(hex: "EB3933")
    static let tapelabGreen = Color(hex: "4A9147")
    static let tapelabOrange = Color(hex: "D08024")
    static let tapelabLight = Color(hex: "F0DBA4")

    // Button specific colors
    static let tapelabButtonBg = Color(hex: "29221F") // FX & VOL button background
    static let tapelabButtonBorder = Color(hex: "3E362F") // Button border
    static let tapelabArmButtonBg = Color(hex: "3E362F") // ARM button background (inactive)

    // Semantic Colors
    static let tapelabBackground = tapelabDark
    static let tapelabArmActive = tapelabRed

    // Helper to create Color from hex string
    init(hex: String, opacity: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Tapelab Fonts
extension Font {
    static let tapelabMono = Font.system(.body, design: .monospaced)
    static let tapelabMonoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let tapelabMonoTiny = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let tapelabMonoBold = Font.system(.body, design: .monospaced).weight(.bold)
    static let tapelabMonoHeadline = Font.system(.headline, design: .monospaced).weight(.bold)
}

// MARK: - Tapelab Theme Structure
struct TapelabTheme {
    struct Colors {
        static let background = Color.tapelabDark
        static let surface = Color.tapelabBlack
        static let accent = Color.tapelabAccentFull
        static let accentSubtle = Color.tapelabAccent
        static let error = Color.tapelabRed
        static let success = Color.tapelabGreen
        static let warning = Color.tapelabOrange
        static let text = Color.tapelabLight
        static let textSecondary = Color.tapelabAccentFull.opacity(0.6)
    }

    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, design: .rounded)
        static let caption = Font.system(size: 12, design: .rounded)
        static let mono = Font.tapelabMono
        static let monoSmall = Font.tapelabMonoSmall
        static let monoTiny = Font.tapelabMonoTiny
        static let monoBold = Font.tapelabMonoBold
        static let monoHeadline = Font.tapelabMonoHeadline
    }
}

// MARK: - Tapelab Button Style
struct TapelabButtonStyle: ButtonStyle {
    let isActive: Bool
    let isArmButton: Bool

    init(isActive: Bool = false, isArmButton: Bool = false) {
        self.isActive = isActive
        self.isArmButton = isArmButton
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.tapelabLight)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        if isArmButton {
            return isActive ? Color.tapelabRed : Color.tapelabArmButtonBg
        } else {
            return isActive ? Color.tapelabOrange.opacity(0.1) : Color.tapelabButtonBg
        }
    }

    private var borderColor: Color {
        if isActive {
            return isArmButton ? Color.tapelabRed : Color.tapelabOrange
        } else {
            return Color.tapelabButtonBorder
        }
    }
}
