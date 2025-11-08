//
//  WaveformView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let color: Color
    let backgroundColor: Color

    var body: some View {
        Canvas { context, size in
            // Draw background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(backgroundColor)
            )

            // Handle empty samples
            guard !samples.isEmpty else { return }

            let barWidth = size.width / CGFloat(samples.count)
            let barSpacing: CGFloat = max(0.5, barWidth * 0.1) // 10% spacing, minimum 0.5pt
            let effectiveBarWidth = max(1.0, barWidth - barSpacing)
            let midY = size.height / 2

            // Draw waveform bars
            for (index, amplitude) in samples.enumerated() {
                let x = CGFloat(index) * barWidth

                // Calculate bar height (symmetric around center)
                let barHeight = CGFloat(amplitude) * (size.height / 2) * 0.9 // 90% of available height

                // Create bar rect centered vertically
                let barRect = CGRect(
                    x: x,
                    y: midY - barHeight,
                    width: effectiveBarWidth,
                    height: barHeight * 2
                )

                // Draw the bar
                context.fill(
                    Path(roundedRect: barRect, cornerRadius: effectiveBarWidth / 2),
                    with: .color(color)
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Waveform - Normal") {
    // Generate sample data
    let sampleData: [Float] = (0..<100).map { i in
        let normalized = Float(i) / 100.0
        return sin(normalized * .pi * 4) * 0.5 + 0.5
    }

    return WaveformView(
        samples: sampleData,
        color: .blue,
        backgroundColor: .blue.opacity(0.1)
    )
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - Recording") {
    // Generate sample data with varying amplitude
    let sampleData: [Float] = (0..<200).map { i in
        let normalized = Float(i) / 200.0
        return abs(sin(normalized * .pi * 8)) * normalized
    }

    return WaveformView(
        samples: sampleData,
        color: .red,
        backgroundColor: .red.opacity(0.1)
    )
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - Empty") {
    WaveformView(
        samples: [],
        color: .green,
        backgroundColor: .green.opacity(0.1)
    )
    .frame(height: 60)
    .padding()
}
