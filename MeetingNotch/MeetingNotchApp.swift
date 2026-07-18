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
                appDelegate.showMeetingNotch()
            }

            Button("Kaydı Başlat", systemImage: "record.circle") {
                appDelegate.startManualRecording()
            }
            .keyboardShortcut("r")

            Button("Takvimi Yenile", systemImage: "calendar.badge.clock") {
                appDelegate.refreshCalendar()
            }

            Divider()

            SettingsLink {
                Label("Ayarlar…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Çıkış", systemImage: "power", role: .destructive) {
                appDelegate.quit()
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                onRequestMicrophoneAccess: appDelegate.requestMicrophoneAccess,
                onRequestSystemAudioAccess: appDelegate.requestSystemAudioAccess,
                onOpenSystemSettings: appDelegate.openSystemSettings,
                onRelaunchApplication: appDelegate.relaunchApplication,
                onRefreshPermissions: appDelegate.refreshAudioPermissions,
                onLoadGeneralSettings: appDelegate.loadGeneralSettings,
                onSaveGeneralSettings: appDelegate.saveGeneralSettings,
                onLoadMicrophoneSettings: appDelegate.loadMicrophoneSettings,
                onSaveMicrophoneSelection: appDelegate.saveMicrophoneSelection,
                onOpenDataDirectory: appDelegate.openDataDirectory,
                onDeleteAllData: appDelegate.deleteAllData,
                onResetOnboarding: appDelegate.resetOnboarding,
                onLoadTranscriptionSettings: appDelegate.loadTranscriptionSettings,
                onSaveTranscriptionSettings: appDelegate.saveTranscriptionSettings
            )
            .environmentObject(appDelegate.appState)
        }
    }
}
