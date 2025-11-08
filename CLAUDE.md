# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Tapelab** is a professional iOS 4-track audio recorder built with SwiftUI and AVFoundation. It's designed for quick idea capture with tape-inspired aesthetics, featuring real-time effects processing and sub-10ms latency.

**Platform:** iOS 15+
**Language:** Swift
**Target Device:** iPhone 12+ recommended
**Key Framework:** AVFAudio (no external dependencies)

## Building & Running

### Build the Project
```bash
# Open in Xcode
open tapelab-beta.xcodeproj

# Build from command line
xcodebuild -scheme tapelab-beta -configuration Debug build

# Build for device
xcodebuild -scheme tapelab-beta -configuration Debug -destination 'platform=iOS,name=YOUR_DEVICE_NAME' build
```

### Run Tests
```bash
# Run all tests
xcodebuild test -scheme tapelab-beta -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -scheme tapelab-beta -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:tapelab-betaTests/YourTestClass

# Run single test method
xcodebuild test -scheme tapelab-beta -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:tapelab-betaTests/YourTestClass/testMethod
```

### Critical: Device Testing Required
**⚠️ The iOS Simulator is unreliable for audio testing.** Always test audio features on a physical device. Audio latency, buffer handling, and AVAudioSession behavior differ significantly between simulator and device.

## Audio Engine Architecture

The audio engine uses a **centralized orchestration pattern** where `AudioRuntime` coordinates three specialized subsystems:

```
AudioRuntime (@MainActor)
    │
    ├── AudioEngineController    # AVAudioEngine setup & graph management
    │   └── TrackBus[4]          # Per-track signal chains
    │       └── Player → EQ → Delay → Reverb → Dist → Mixer → MainMixer → Limiter → Output
    │
    ├── SessionPlayer            # Playback scheduling engine
    │   ├── Sample-accurate scheduling with AVAudioTime
    │   ├── Loop mode detection & seamless transitions
    │   └── Real-time buffer processing (gain, fade, reverse)
    │
    ├── SessionRecorder          # Recording with input monitoring
    │   ├── AVAudioSession configuration
    │   ├── Input tap installation
    │   └── Monitor mixer for latency-free monitoring
    │
    └── TimelineState            # Transport & UI synchronization
        └── CADisplayLink for 60fps playhead updates
```

### Key Architectural Decisions

1. **Mono → Stereo Processing**
   Audio is processed internally in mono (1 channel) until the track mixer, then converted to stereo for output. This halves CPU usage while maintaining quality for music recording.

2. **Sample-Accurate Scheduling**
   `SessionPlayer.scheduleWindow()` uses `AVAudioTime` with sample positions tied to the engine clock, not wall-clock time. This ensures drift-free synchronization across all 4 tracks.

3. **Preload Strategy**
   All region buffers are loaded into memory at playback start (see `SessionPlayer.preloadRegions()`). This works because sessions are capped at 6 minutes. For longer sessions, you'd need streaming playback.

4. **CADisplayLink for UI**
   `TimelineState` uses `CADisplayLink` synced to the display refresh (60fps) for buttery-smooth playhead scrolling. This is critical for the tape-inspired UX.

5. **@MainActor Controllers**
   All audio controllers are `@MainActor` classes. AVAudioEngine's rendering happens on a real-time background thread automatically, but all setup/control operations are main-thread only.

## Signal Flow Deep Dive

### Per-Track Audio Graph
```
AVAudioPlayerNode (region playback)
    ↓ mono, 48kHz
AVAudioUnitEQ (4-band parametric)
    ↓ mono
AVAudioUnitDelay (with feedback & lowpass)
    ↓ mono
AVAudioUnitReverb (room simulation)
    ↓ mono
AVAudioUnitDistortion (saturation/warmth)
    ↓ mono
AVAudioMixerNode (volume & pan, converts to stereo)
    ↓ stereo
MainMixerNode (summing all 4 tracks)
    ↓ stereo
AVAudioUnitEffect (peak limiter)
    ↓ stereo
AVAudioEngine.outputNode
```

### Critical: Audio Graph Modification
**Never attach or detach nodes while the engine is running.** Either stop the engine first, or design your code to bypass nodes via `wetDryMix` parameters instead of removing them.

## Data Model Relationships

```
Session
    ├── id: UUID
    ├── name: String
    ├── maxDuration: 360s (6 minutes, constant)
    └── tracks: [Track; 4 items]
        ├── id: UUID
        ├── number: Int (1-4)
        ├── fx: TrackFX
        │   ├── volumeDB, pan
        │   ├── eqBands: [EQBand; 4 bands]
        │   ├── reverb: ReverbFX
        │   ├── delay: DelayFX
        │   └── saturation: SaturationFX
        └── regions: [Region; 0...n]
            ├── id: RegionID
            ├── sourceURL: URL (path to .caf file)
            ├── startTime: TimeInterval (position on timeline)
            ├── duration: TimeInterval (visible length)
            ├── fileStartOffset: TimeInterval (trim start)
            ├── reversed: Bool
            ├── fadeIn/fadeOut: TimeInterval?
            └── gainDB: Double?
```

### File Structure on Disk
```
Documents/Tapelab/Sessions/
    └── [SessionUUID]/
        ├── Track_1/
        │   ├── region_2025-01-15T10:30:00Z.caf
        │   └── region_2025-01-15T10:35:00Z.caf
        ├── Track_2/
        ├── Track_3/
        └── Track_4/
```

All audio files are stored as `.caf` (Core Audio Format) at 48kHz, 32-bit float, mono.

## Critical Code Sections

### 1. AudioEngineController.init() - Initialization Order Matters
```swift
// CRITICAL: Initialize ALL stored properties BEFORE calling any methods
init(trackCount: Int = 4) {
    // 1. Initialize properties first
    mainMixer = engine.mainMixerNode
    sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    processingFormat = AVAudioFormat(...)!
    stereoFormat = AVAudioFormat(...)!
    limiter = AVAudioUnitEffect(...)

    // 2. NOW you can call methods (after all properties initialized)
    Self.configureAudioSession()
    setupTracks(count: trackCount)
}
```

**Why:** Swift requires all stored properties to be initialized before `self` can be used. The compiler error "self used before all stored properties are initialized" is common when adding new properties.

### 2. SessionPlayer.scheduleWindow() - Sample-Accurate Scheduling
This method is the heart of playback. It:
- Calculates which regions overlap the current playback window
- Creates buffer slices with sample-accurate offsets
- Applies gain, fades, and reverse processing using vDSP
- Schedules buffers with `AVAudioTime` tied to engine clock

**Performance Critical:** Runs every loop iteration (every ~20ms). Must be lightweight.

### 3. TimelineState.updatePlayhead() - 60fps Display Updates
```swift
@objc private func updatePlayhead() {
    guard isPlaying else { return }

    let currentTime = CACurrentMediaTime()
    let elapsed = currentTime - playbackStartTime
    playhead = playbackStartPlayhead + elapsed

    // Handle loop mode wrapping...
}
```

Called by `CADisplayLink` at display refresh rate (~60fps). Must be extremely fast - no file I/O, no heavy calculations.

### 4. SessionRecorder.startRecording() - Input Monitoring Setup
Configures `AVAudioSession` for simultaneous recording and playback, installs an input tap for file writing, and creates a monitor mixer so the user hears themselves in real-time with adjustable volume.

**Gotcha:** If monitor volume is too high and you're not wearing headphones, you'll get feedback loops. Always test recording with headphones initially.

## Threading Model

```
Main Thread (@MainActor)
    ├── AudioRuntime
    ├── AudioEngineController
    ├── SessionPlayer (control methods)
    ├── SessionRecorder (control methods)
    └── TimelineState
        └── CADisplayLink callbacks (@objc updatePlayhead)

Real-Time Audio Thread (automatic, managed by AVAudioEngine)
    ├── AVAudioPlayerNode rendering
    ├── Effect processing (EQ, Delay, Reverb, etc.)
    └── Input tap callbacks (SessionRecorder)
        └── Must dispatch back to @MainActor for UI updates

Background Tasks
    └── SessionPlayer.loopObserverTask (async Task)
```

**Golden Rules:**
1. Never block the real-time audio thread (no file I/O, no allocations, no locks)
2. All AVAudioEngine graph modifications must happen on the main thread
3. Use `Task { @MainActor in ... }` to safely update UI from audio callbacks

## Performance Targets & Constraints

**Hard Limits:**
- Buffer Size: 5ms (~256 samples @ 48kHz)
- Round-trip Latency: 5-8ms
- CPU Usage: <30% during 4-track playback with all FX active
- Memory: <50MB total
- Max Session Duration: 6 minutes (360 seconds)
- Track Count: 4 (fixed)

**Why These Numbers:**
- 5ms buffer: Balance between latency and CPU overhead
- 6-minute max: Keeps all audio in memory (no streaming complexity)
- Mono processing: Halves CPU vs. stereo processing
- 4 tracks: UI simplicity, mobile CPU constraints

## Common Gotchas

### 1. Simulator Audio Testing
**Problem:** Simulator audio is unreliable for latency, interruptions, and buffer handling.
**Solution:** Always test on physical devices for audio features.

### 2. Buffer Pointer Operations
```swift
// ✅ Modern API
pointer.update(from: source, count: n)

// ❌ Deprecated (will cause warnings)
pointer.assign(from: source, count: n)
```

### 3. AVAudioSession Configuration
Must be set to `.playAndRecord` category before recording:
```swift
try AVAudioSession.sharedInstance().setCategory(
    .playAndRecord,
    mode: .videoRecording,
    options: [.allowBluetoothA2DP, .defaultToSpeaker]
)
```

### 4. Codable with Constants
```swift
struct Session: Codable {
    let id: UUID
    var name: String
    let maxDuration: TimeInterval = 6 * 60  // Constant, not stored in JSON

    // Exclude maxDuration from encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, name  // Only these are coded
    }
}
```

### 5. CADisplayLink Retain Cycles
```swift
// CADisplayLink strongly retains its target
displayLink = CADisplayLink(target: self, selector: #selector(updatePlayhead))

// Must invalidate in stopTimeline() or you'll leak memory
func stopTimeline() {
    displayLink?.invalidate()
    displayLink = nil
}
```

## Required Imports for Audio Files

```swift
import Foundation        // Basic types, URL, UUID
import AVFAudio         // AVAudioEngine, AVAudioPlayerNode, etc.
import Combine          // @Published, ObservableObject
import QuartzCore       // CADisplayLink, CACurrentMediaTime
import Accelerate       // vDSP functions for DSP operations
```

## File Organization

```
tapelab-beta/
    └── Audio/
        ├── AudioRuntime.swift            # Main orchestrator
        ├── AudioEngineController.swift   # AVAudioEngine setup & graph
        ├── SessionPlayer.swift           # Playback scheduling engine
        ├── SessionRecorder.swift         # Recording with monitoring
        ├── TrackBus.swift                # Per-track signal chain
        ├── TrackFX.swift                 # FX data models (EQ, reverb, etc.)
        ├── SessionModels.swift           # Session, Track, Region, TimelineState
        ├── FileStore.swift               # File management utilities
        └── AudioExtensions.swift         # Helper extensions (buffer utils, etc.)
```

**Convention:** Each file contains tightly related functionality. Effects models are separate from signal processing, data models are separate from runtime state.

## Key Concepts

### Sample-Accurate Timing
```swift
// ❌ Wrong: Wall-clock time drifts from audio clock
let wrongTime = Date()

// ✅ Correct: Sample positions tied to audio engine clock
let playerTime = AVAudioTime(sampleTime: samplePosition, atRate: sampleRate)
```

### vDSP Operations (Accelerate Framework)
Used in `SessionPlayer.makeSegment()` for gain application:
```swift
// Apply gain in dB using vectorized operations
let linearGain = powf(10, Float(gainDB) / 20)
vDSP_vsmul(buffer, 1, [linearGain], buffer, 1, vDSP_Length(frameCount))
```

This is 10-100x faster than a for-loop for large buffers.

### Mono → Stereo Conversion
```swift
// TrackBus connects mono processing to stereo mixer
engine.connect(bus.dist, to: bus.mixer, format: processingFormat)  // mono
engine.connect(bus.mixer, to: mainMixer, format: stereoFormat)     // stereo
```

The `AVAudioMixerNode` automatically upmixes mono to stereo using its `pan` parameter.

## Development Workflow

1. **Make changes to audio code** (Audio/ directory)
2. **Build in Xcode** (`Cmd+B` or `xcodebuild`)
3. **Deploy to physical device** (not simulator)
4. **Test with headphones** (avoid feedback during recording)
5. **Check performance** (Activity Monitor or Instruments)
6. **Verify no audio dropouts** (listen for clicks/pops)

## Important Notes

- **No undo/redo yet:** Destructive edits (region deletion, etc.) are permanent
- **No background audio:** App pauses when backgrounded
- **Bluetooth latency:** AirPods add ~200ms latency, use wired for recording
- **Phone call interruptions:** Not fully handled, playback may stall

## Audio Engine State Management

```swift
engine.start()  // Start audio processing (connects to hardware)
engine.stop()   // Stop and disconnect from hardware

// Individual players
player.play()   // Start player node (must call before scheduling buffers)
player.stop()   // Stop player node
```

**Critical:** Always call `player.play()` before scheduling buffers, even if the engine is already running. Each `AVAudioPlayerNode` must be explicitly started.

## When Adding New Features

### Adding a New Effect
1. Define FX model in `TrackFX.swift` (e.g., `CompressorFX`)
2. Add audio unit property to `TrackBus.swift` (e.g., `let compressor = AVAudioUnitEffect(...)`)
3. Insert in signal chain in `TrackBus.init()` or `AudioEngineController.setupTracks()`
4. Update `TrackBus.applyFX()` to map model parameters to audio unit properties

### Changing Buffer Size
```swift
// In AudioEngineController.configureAudioSession()
try session.setPreferredIOBufferDuration(0.010)  // 10ms instead of 5ms
```
Lower = less latency but higher CPU. Higher = more latency but lower CPU.

### Debugging Audio Issues
1. Check console for emoji-prefixed logs (`🎧`, `🎙️`, `⚠️`, `🎛️`)
2. Use **Instruments → Audio Performance** for CPU profiling
3. Verify buffer sizes and sample rates match across the graph
4. Test with headphones to eliminate speaker feedback
5. Check `AVAudioSession` category and options

---

**Last Updated:** January 2025
**Audio Engine Version:** 1.2
**Status:** Production-ready core, UI in development
