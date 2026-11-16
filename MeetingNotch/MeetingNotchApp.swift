//
//  MeetingNotchApp.swift
//  MeetingNotch
//
//  Created by Aykhan Gadirli on 14.07.26.
//

import SwiftUI

@main
struct MeetingNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Crenel", systemImage: "waveform.badge.mic") {
            Button("Open Crenel", systemImage: "macbook") {
                appDelegate.showDesktop()
            }

            Button("Show Notch", systemImage: "rectangle.topthird.inset.filled") {
                appDelegate.showMeetingNotch()
            }

            Button("Start Recording", systemImage: "record.circle") {
                appDelegate.startManualRecording()
            }
            .keyboardShortcut("r")

            Button("Toggle Meeting Mic", systemImage: "mic.badge.plus") {
                appDelegate.toggleMeetingMicrophoneGate()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])

            Button("Refresh Calendar", systemImage: "calendar.badge.clock") {
                appDelegate.refreshCalendar()
            }

            Divider()

            Button("Settings…", systemImage: "gearshape") { appDelegate.showDesktop(section: .settings) }
            .keyboardShortcut(",")

            Divider()

            Button("Quit", systemImage: "power", role: .destructive) {
                appDelegate.quit()
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showDesktop(section: .settings) }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appSettings) {
                Button("Open Crenel") { appDelegate.showDesktop() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

    }
}
