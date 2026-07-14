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
        Settings {
            SettingsView()
        }
    }
}
