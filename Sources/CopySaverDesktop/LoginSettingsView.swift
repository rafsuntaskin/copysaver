import ServiceManagement
import SwiftUI

struct LoginSettingsView: View {
    let preview: Bool
    let automaticallyOpensVault: Bool
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at login", isOn: Binding(get: { enabled }, set: { value in
                do {
                    if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    enabled = SMAppService.mainApp.status == .enabled
                    message = SMAppService.mainApp.status == .requiresApproval ? "Approve CopySaver in Login Items to finish enabling it." : nil
                } catch { enabled = SMAppService.mainApp.status == .enabled; message = "macOS could not change login launch. Check Login Items settings and try again." }
            })).disabled(preview)
            Text(automaticallyOpensVault ? "Opens in the menu bar and resumes your saved capture preference. Paused or disabled history stays that way." : "Starts locked in the menu bar. Unlock the library when you need it.").foregroundStyle(.secondary)
            if let message { Text(message).foregroundStyle(.secondary) }
            Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }.disabled(preview)
        }
    }
}
