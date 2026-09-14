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
        MenuBarExtra("MeetingNotch", systemImage: "waveform.badge.mic") {
            Button("MeetingNotch'u Aç", systemImage: "macbook") {
                appDelegate.showDesktop()
            }

            Button("Notch’u Göster", systemImage: "rectangle.topthird.inset.filled") {
                appDelegate.showMeetingNotch()
            }

            Button("Kaydı Başlat", systemImage: "record.circle") {
                appDelegate.startManualRecording()
            }
            .keyboardShortcut("r")

            Button("Toplantı Mikrofonunu Aç/Kapat", systemImage: "mic.badge.plus") {
                appDelegate.toggleMeetingMicrophoneGate()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])

            Button("Takvimi Yenile", systemImage: "calendar.badge.clock") {
                appDelegate.refreshCalendar()
            }

            Divider()

            Button("Ayarlar…", systemImage: "gearshape") { appDelegate.showDesktop(section: .settings) }
            .keyboardShortcut(",")

            Divider()

            Button("Çıkış", systemImage: "power", role: .destructive) {
                appDelegate.quit()
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar…") { appDelegate.showDesktop(section: .settings) }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appSettings) {
                Button("MeetingNotch’u Aç") { appDelegate.showDesktop() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

    }
}
