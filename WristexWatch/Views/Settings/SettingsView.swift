import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var sshManager = SSHManager.shared
    
    @State private var localHost: String = ""
    @State private var localUsername: String = ""
    @State private var localPortText: String = ""
    @State private var localWorkspacePath: String = ""
    @State private var localPassword: String = ""
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("SSH Remote Host").font(.system(.footnote, design: .rounded)).foregroundColor(.indigo)) {
                TextField("IP or Hostname", text: $localHost, prompt: Text("localhost"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                
                TextField("Username", text: $localUsername, prompt: Text("amir"))
                    .textContentType(.username)
                    .autocorrectionDisabled()
                
                TextField("Port", text: $localPortText, prompt: Text("22"))
                    .keyboardType(.numberPad)
                
                TextField("Workspace Path", text: $localWorkspacePath, prompt: Text("/path/to/project"))
                    .autocorrectionDisabled()
            }
            
            Section(header: Text("Security").font(.system(.footnote, design: .rounded)).foregroundColor(.orange)) {
                SecureField("Password / Key Phrase", text: $localPassword, prompt: Text("Enter password"))
                    .autocorrectionDisabled()
            }
            
            Section {
                Button(action: saveSettings) {
                    HStack {
                        Spacer()
                        Image(systemName: "bolt.horizontal.fill")
                        Text("Connect Remote")
                        Spacer()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                }
                .listRowBackground(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .navigationTitle("SSH Settings")
        .onAppear {
            localHost = sshManager.host
            localUsername = sshManager.username
            localPortText = String(sshManager.port)
            localWorkspacePath = sshManager.remoteWorkspacePath
            localPassword = sshManager.password
        }
    }
    
    private func saveSettings() {
        sshManager.host = localHost
        sshManager.username = localUsername
        sshManager.port = Int(localPortText) ?? 22
        sshManager.remoteWorkspacePath = localWorkspacePath
        sshManager.password = localPassword
        
        HapticManager.shared.playSuccess()
    }
}

struct SettingsView_Previews: PreviewProvider {
    public static var previews: some View {
        SettingsView()
    }
}
