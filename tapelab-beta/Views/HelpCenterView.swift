//
//  HelpCenterView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var expandedSection: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.tapelabAccentFull)
                            .font(.system(size: 16))

                        TextField("Search help articles...", text: $searchText)
                            .font(.tapelabMono)
                            .foregroundColor(.tapelabLight)
                            .textInputAutocapitalization(.never)

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.tapelabAccentFull)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.tapelabButtonBg)
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Content sections
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(filteredSections, id: \.title) { section in
                                HelpSectionButton(
                                    section: section,
                                    isExpanded: expandedSection == section.title,
                                    onTap: {
                                        withAnimation {
                                            expandedSection = expandedSection == section.title ? nil : section.title
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.tapelabLight)
                            .frame(width: 3, height: 3)

                        Text("HELP CENTER")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabLight)
                    }
                }

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

    private var filteredSections: [HelpSection] {
        if searchText.isEmpty {
            return HelpSection.allSections
        }

        let lowercasedSearch = searchText.lowercased()
        return HelpSection.allSections.filter { section in
            section.title.lowercased().contains(lowercasedSearch) ||
            section.articles.contains { article in
                article.title.lowercased().contains(lowercasedSearch) ||
                article.content.lowercased().contains(lowercasedSearch)
            }
        }
    }
}

struct HelpSectionButton: View {
    let section: HelpSection
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Section header button
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 18))
                        .foregroundColor(.tapelabAccentFull)
                        .frame(width: 24, height: 24)

                    Text(section.title.uppercased())
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(.tapelabAccentFull)
                }
                .padding(16)
                .background(Color.tapelabButtonBg)
                .cornerRadius(8)
            }

            // Expanded articles
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(section.articles, id: \.title) { article in
                        HelpArticleView(article: article)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct HelpArticleView: View {
    let article: HelpArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.title)
                .font(.tapelabMonoBold)
                .foregroundColor(.tapelabOrange)

            Text(article.content)
                .font(.tapelabMonoSmall)
                .foregroundColor(.tapelabLight)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.tapelabButtonBg.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Data Models

struct HelpArticle {
    let title: String
    let content: String
}

struct HelpSection {
    let title: String
    let icon: String
    let articles: [HelpArticle]

    static let allSections: [HelpSection] = [
        HelpSection(
            title: "Getting Started",
            icon: "play.circle",
            articles: [
                HelpArticle(
                    title: "What is TAPELAB?",
                    content: "TAPELAB is a 4-track tape recorder designed for musicians, songwriters, and creators who want a simple, focused recording experience. Inspired by classic cassette tape recorders, TAPELAB lets you layer up to four tracks of audio to create complete songs, demos, or ideas. Each session gives you a 6-minute timeline (8 minutes with Pro) where you can record instruments, vocals, or any audio source, then mix them together into a final stereo file."
                ),
                HelpArticle(
                    title: "Creating Your First Session",
                    content: "To create your first session, tap the \"+\" button on the dashboard. Give your session a name, set your preferred BPM (tempo) and time signature, and you're ready to record. TAPELAB automatically creates four empty tracks for you. By default, Track 1 is armed and ready to record - just tap the record button to start capturing audio. Your session is saved automatically as you work."
                )
            ]
        ),
        HelpSection(
            title: "Sessions",
            icon: "folder",
            articles: [
                HelpArticle(
                    title: "What is a Session?",
                    content: "A session is your recording project - think of it as a blank tape. Each session contains four parallel tracks that you can record on independently. Sessions have a maximum length of 6 minutes (8 minutes with Pro) and store your tempo (BPM), time signature, and all your recordings. All your sessions are stored locally on your device and appear on the dashboard for easy access."
                ),
                HelpArticle(
                    title: "Creating a Session",
                    content: "From the dashboard, tap the \"+\" button to create a new session. Enter a name that helps you remember what you're working on (like \"Song Idea 1\" or \"Guitar Riff\"). Choose your BPM (tempo) - this affects the metronome and helps you stay in time. Select a time signature (4/4, 3/4, or 6/8) based on the feel of your music. Once created, your session opens in the recording view with four empty tracks ready to go."
                ),
                HelpArticle(
                    title: "Session Settings",
                    content: "Tap the settings icon in your session to adjust BPM, time signature, or session name at any time. You can also configure metronome options here: enable \"Count-in Before Recording\" to hear a full measure of clicks before recording starts, or enable \"Metronome While Recording\" to keep the click playing throughout your take. These settings help you stay in time and get the perfect performance."
                ),
                HelpArticle(
                    title: "Managing Sessions",
                    content: "Your dashboard shows all your sessions with their creation date and duration. Tap any session to open it and continue working. Long-press a session to rename or delete it. Sessions are stored locally on your device, so make sure you have enough storage space. Pro users can create unlimited sessions, while free users are limited to a certain number of active projects."
                )
            ]
        ),
        HelpSection(
            title: "Recording",
            icon: "record.circle",
            articles: [
                HelpArticle(
                    title: "Recording Basics",
                    content: "Recording in TAPELAB is simple: arm a track (tap the track number to enable recording), position the playhead where you want to start, and press the record button. The track will capture audio from your device's microphone. While recording, you'll see a waveform appear in real-time showing your audio levels. When you're done, press stop - your recording appears as a region (audio clip) on the timeline."
                ),
                HelpArticle(
                    title: "Arming a Track ⚠️ CRITICAL",
                    content: "Before you can record on any track, you must arm it. Tap the track number (1, 2, 3, or 4) to toggle between armed (ready to record, indicated by a red highlight) and disarmed. Only one track can be armed at a time - this prevents accidental recording on multiple tracks. When you switch to a different track to record, remember to arm it first, or your recording won't capture any audio."
                ),
                HelpArticle(
                    title: "Count-In Metronome",
                    content: "When enabled in session settings, TAPELAB plays a count-in before recording starts. This gives you a full measure of metronome clicks (4 beats in 4/4, 3 beats in 3/4, etc.) to prepare before audio recording begins. The count-in helps you come in at exactly the right time. Recording starts automatically after the count-in completes, so be ready to play. You can toggle this feature on/off in the metronome settings sheet."
                ),
                HelpArticle(
                    title: "Overdubbing",
                    content: "Overdubbing means recording a new track while listening to tracks you've already recorded. To overdub, make sure your existing tracks have audio on them, arm a new track, and press record. You'll hear your previous recordings play back while the new track captures fresh audio. This is how you build up layers - record a rhythm guitar on track 1, then overdub vocals on track 2, bass on track 3, and so on."
                ),
                HelpArticle(
                    title: "Recording Requirements",
                    content: "TAPELAB requires microphone access to record audio. The first time you try to record, iOS will ask for microphone permission - tap \"Allow\" to continue. Make sure your device volume is turned up so you can hear playback during overdubs. For best results, record in a quiet space and keep your device stable. If you're using headphones with a built-in mic, those work great for recording vocals or acoustic instruments."
                )
            ]
        ),
        HelpSection(
            title: "Playback & Timeline",
            icon: "play.rectangle",
            articles: [
                HelpArticle(
                    title: "Playing Your Session",
                    content: "Press the play button to hear all your tracks play back together. The playhead (vertical line) moves across the timeline showing your current position. Use the stop button to pause playback and reset the playhead to zero. You can also drag the playhead to any position on the timeline to start playback from that point. All four tracks play simultaneously, giving you a preview of your mix."
                ),
                HelpArticle(
                    title: "Loop Mode",
                    content: "Loop mode lets you repeat a section of your session continuously - perfect for practicing parts or fine-tuning a section. Tap the loop button, then drag the loop markers to set your loop start and end points. When you press play in loop mode, playback jumps back to the loop start when it reaches the loop end. This is incredibly useful for overdubbing tricky parts or listening to specific sections repeatedly."
                ),
                HelpArticle(
                    title: "Moving Regions",
                    content: "After recording, you can reposition your audio clips (regions) on the timeline. Tap a region to select it, then drag it left or right to move it earlier or later in time. Regions snap to the grid for precise timing. Moving regions lets you fix timing issues, create space between parts, or experiment with different arrangements. You can move regions while playback is stopped."
                ),
                HelpArticle(
                    title: "Timeline Navigation",
                    content: "The timeline shows 6 minutes of recording space (8 minutes for Pro users) divided into a grid. Each vertical line represents a beat or measure depending on your zoom level. Pinch to zoom in for detailed editing or zoom out to see your entire session. The numbers at the top show time in seconds. Use two fingers to scroll the timeline left and right without moving the playhead."
                )
            ]
        ),
        HelpSection(
            title: "Editing Regions",
            icon: "scissors",
            articles: [
                HelpArticle(
                    title: "What is a Region?",
                    content: "A region is an audio clip on your timeline. Every time you record, TAPELAB creates a new region containing that recording. Regions appear as colored blocks with waveforms showing the audio shape. Each region has properties like start time (position on the timeline), duration (length), and volume. You can have multiple regions on the same track, though they can't overlap."
                ),
                HelpArticle(
                    title: "Selecting Regions",
                    content: "Tap any region on the timeline to select it - it will highlight with a border. Once selected, you can move it, trim it, delete it, or adjust its properties. Only one region can be selected at a time. Tap empty timeline space to deselect. The selected region shows its details at the top of the screen including its position and length."
                ),
                HelpArticle(
                    title: "Trimming",
                    content: "Trimming lets you shorten a region by cutting audio from the beginning or end. Select a region and tap the \"Trim\" button. Drag the left edge to trim the start (remove audio from the beginning) or drag the right edge to trim the end. This is useful for removing silence, counting, or mistakes from recordings. Trimming is non-destructive - the original audio file remains intact."
                ),
                HelpArticle(
                    title: "Moving Regions",
                    content: "Select a region and drag it horizontally to reposition it on the timeline. Regions snap to the grid based on your session's tempo, making it easy to line up recordings with the beat. You can move regions to any track position, but they can't overlap with other regions on the same track. Moving regions is perfect for adjusting timing or creating space between musical phrases."
                ),
                HelpArticle(
                    title: "Deleting Regions",
                    content: "To delete a region, select it and tap the trash/delete button. The region disappears from the timeline, though the original audio file remains on your device in case you need to undo later. Deleting regions helps you remove bad takes or clear space on cluttered tracks. You cannot undo deletions, so be sure before deleting."
                )
            ]
        ),
        HelpSection(
            title: "Track Effects",
            icon: "slider.horizontal.3",
            articles: [
                HelpArticle(
                    title: "Gain Control",
                    content: "Gain adjusts the volume level of an entire track. Tap the FX button on any track and adjust the gain slider to make that track louder or quieter in your mix. Unlike the main mix volume, gain affects only one track, making it perfect for balancing different instruments. Increase gain if a track is too quiet, or decrease it if a track is overpowering others."
                ),
                HelpArticle(
                    title: "Reverb",
                    content: "Reverb adds space and depth to your tracks, simulating the sound of playing in a room, hall, or cathedral. Adjust the reverb amount using the slider in the track FX panel. A little reverb can make vocals sound more polished, while heavy reverb creates an ambient, atmospheric effect. Each track can have different reverb settings, so you can add space only where needed."
                ),
                HelpArticle(
                    title: "Delay",
                    content: "Delay creates echoes by repeating your audio signal. Adjust the delay time (how long before the echo occurs) and feedback (how many echoes you hear) in the FX panel. Short delays create a doubling effect, while long delays produce distinct rhythmic echoes. Use delay on vocals, guitars, or synths to add movement and interest to your recordings."
                ),
                HelpArticle(
                    title: "EQ (Low/High)",
                    content: "EQ (equalization) adjusts the tone of your track by boosting or cutting bass and treble frequencies. The low EQ slider controls bass (warmth, rumble), while the high EQ slider controls treble (brightness, clarity). Use EQ to fix muddy recordings (cut low), make vocals clearer (boost high), or warm up thin-sounding tracks (boost low). Each track has independent EQ settings."
                ),
                HelpArticle(
                    title: "Managing Effects",
                    content: "Effects are applied per track and saved automatically with your session. Tap the FX button on any track to access that track's effect panel. Toggle effects on/off using the power button next to each effect name. When effects are active, you'll see a small indicator on the track. Effects process in real-time during playback, so you can hear changes immediately. Adjust effects to taste while listening."
                )
            ]
        ),
        HelpSection(
            title: "Tools",
            icon: "wrench.and.screwdriver",
            articles: [
                HelpArticle(
                    title: "Metronome",
                    content: "The metronome is a built-in click track that helps you stay in time. Tap the metronome button to access settings where you can adjust BPM (tempo) and time signature. The metronome can play a count-in before recording (a full measure of clicks to prepare you) and optionally continue playing during recording. Use the metronome when recording rhythmic parts to ensure everything stays locked to the beat."
                ),
                HelpArticle(
                    title: "Tuner",
                    content: "The built-in chromatic tuner helps you tune your instrument. Tap the tuner button and play a note - the tuner displays the detected frequency and shows visually whether you're sharp (too high), flat (too low), or perfectly in tune. The tuner works with guitars, basses, ukuleles, and other pitched instruments. Tune up before recording to ensure your tracks sound great together. (Pro feature)"
                )
            ]
        ),
        HelpSection(
            title: "Mixing & Export",
            icon: "waveform.circle",
            articles: [
                HelpArticle(
                    title: "Creating a Mix",
                    content: "When you're finished recording and arranging your session, create a mix to export your work as a single stereo audio file. Tap the mix/bounce button, and TAPELAB combines all four tracks (with their effects and gain settings) into one file. This process takes a few seconds. Once complete, your mix appears in the mixes list where you can play it back, share it, or export it."
                ),
                HelpArticle(
                    title: "Mix Settings",
                    content: "Mixes are exported as high-quality stereo audio files that contain all your tracks combined. TAPELAB automatically applies the gain and effects you set on each track during the mix bounce. The resulting file is stored locally on your device. Pro users can create unlimited mixes, while free users have a limit on how many mixes they can save."
                ),
                HelpArticle(
                    title: "Sharing Your Mix",
                    content: "Once you've created a mix, tap the share button to export it from TAPELAB. You can save the audio file to your device's Files app, send it via Messages or email, upload it to cloud storage (iCloud, Dropbox), or share it to social media. The mix exports as a standard audio file format compatible with other music apps and platforms."
                )
            ]
        ),
        HelpSection(
            title: "Account & Settings",
            icon: "gearshape",
            articles: [
                HelpArticle(
                    title: "Free vs Pro",
                    content: "TAPELAB Free gives you everything you need to get started: 4-track recording, basic editing, and the ability to create sessions and mixes (with some limitations on number). TAPELAB Pro ($4.99/month) unlocks unlimited sessions and mixes, extends session length to 8 minutes, and gives you access to premium tools like the tuner and metronome. Upgrade to Pro in the settings menu if you need more capacity or advanced features."
                ),
                HelpArticle(
                    title: "Audio Settings",
                    content: "TAPELAB uses your device's default audio settings for recording and playback. For best quality, record in a quiet environment and speak/play about 6-12 inches from the microphone. If you experience latency (delay between playing and hearing), try using wired headphones instead of Bluetooth. The app automatically handles sample rate and buffer settings for optimal performance on your device."
                ),
                HelpArticle(
                    title: "App Permissions",
                    content: "TAPELAB requires microphone access to record audio. When you first try to record, iOS will ask for permission - tap \"Allow\" to grant access. You can manage permissions later in iOS Settings > TAPELAB. Without microphone permission, you won't be able to record new audio, though you can still play back existing sessions and edit previously recorded regions."
                )
            ]
        ),
        HelpSection(
            title: "Troubleshooting",
            icon: "exclamationmark.triangle",
            articles: [
                HelpArticle(
                    title: "Recording Issues",
                    content: "If you tap record but no audio is captured, check these common issues: (1) Make sure the track is armed (tap the track number until it highlights), (2) Verify microphone permissions are enabled in iOS Settings > TAPELAB, (3) Check that your device volume is up and not muted, (4) Ensure your microphone isn't blocked or covered. If problems persist, try restarting the app or your device."
                ),
                HelpArticle(
                    title: "Playback Problems",
                    content: "If playback sounds choppy, cuts out, or won't start, try these solutions: (1) Close other audio apps that might be using the audio system, (2) Restart the TAPELAB app, (3) Check that your device has enough free storage space, (4) Disable Bluetooth audio devices and use wired headphones or device speakers. If sync issues occur between tracks, stop playback and press play again to reset timing."
                ),
                HelpArticle(
                    title: "App Performance",
                    content: "TAPELAB performs best when your device has sufficient free storage (at least 1GB recommended) and isn't running too many background apps. Each minute of recording takes approximately 10MB of storage. If the app becomes slow or unresponsive, close it completely and reopen it. Regularly export and delete old sessions you no longer need to free up space and keep the app running smoothly."
                )
            ]
        ),
        HelpSection(
            title: "Tips & Best Practices",
            icon: "lightbulb",
            articles: [
                HelpArticle(
                    title: "Recording Quality Tips",
                    content: "For best recording quality, position your device's microphone 6-12 inches from the sound source. Record in a quiet space to minimize background noise. Watch the input level meter while recording - peaks should stay in the green/yellow range without hitting red (clipping). If recording acoustic guitar, point the mic at the 12th fret. For vocals, sing slightly off-axis to the mic to reduce plosives (hard P and B sounds)."
                ),
                HelpArticle(
                    title: "Workflow Tips",
                    content: "Start by recording a rhythm instrument or click track on Track 1 as a foundation. Use loop mode when practicing or perfecting a part before recording it for real. Record multiple takes on different tracks, then delete the ones you don't like. Name your sessions descriptively so you can find them later. Save mixes with dates or version numbers (like \"Song v1\", \"Song v2\") to track your progress."
                ),
                HelpArticle(
                    title: "Creative Techniques",
                    content: "Layer multiple takes of the same instrument on different tracks for a fuller sound (try doubling vocals or guitars). Use different reverb settings on each track to create depth - put vocals upfront with less reverb and guitars farther back with more. Experiment with timing by moving regions slightly off the beat for a loose, human feel. Try recording the same part at different tempos and see what sounds best."
                )
            ]
        )
    ]
}

#Preview {
    HelpCenterView()
}
