//
//  HeadphoneDetector.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import AVFoundation

@MainActor
final class HeadphoneDetector {

    static func areHeadphonesConnected() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        for output in currentRoute.outputs {
            switch output.portType {
            case .headphones,
                 .bluetoothA2DP,
                 .bluetoothLE,
                 .bluetoothHFP,
                 .airPlay,
                 .HDMI,
                 .usbAudio:
                return true
            default:
                continue
            }
        }

        return false
    }

    static func getOutputDeviceName() -> String {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        if let output = currentRoute.outputs.first {
            return output.portName
        }

        return "Unknown"
    }
}
