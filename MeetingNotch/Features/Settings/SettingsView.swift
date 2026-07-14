import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Genel") {
                Text("MeetingNotch ayarları sonraki geliştirme adımlarında burada yer alacak.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 260)
    }
}
