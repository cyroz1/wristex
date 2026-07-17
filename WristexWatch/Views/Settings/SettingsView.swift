import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var network = NetworkManager.shared
    
    @State private var localBaseURL: String = ""
    @State private var localAuthToken: String = ""
    @State private var showSavedAlert = false
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("Agent Backend").font(.system(.footnote, design: .rounded)).foregroundColor(.indigo)) {
                TextField("Server URL", text: $localBaseURL, prompt: Text("http://192.168.1..."))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                
                TextField("Bearer Token", text: $localAuthToken, prompt: Text("Optional Token"))
                    .autocorrectionDisabled()
            }
            
            Section {
                Button(action: saveSettings) {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Configuration")
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
            
            Section(header: Text("Info").font(.system(.footnote, design: .rounded))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wristex watchOS v1.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Connect to your agent host to manage workspace tasks, dictate instructions, approve tools, and execute git commands.")
                        .font(.system(size: 10, weight: .light, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            localBaseURL = network.baseURL
            localAuthToken = network.authToken
        }
    }
    
    private func saveSettings() {
        // Save to Shared Network Manager
        network.baseURL = localBaseURL
        network.authToken = localAuthToken
        
        HapticManager.shared.playSuccess()
        
        // Show short visual feedback
        showSavedAlert = true
    }
}

struct SettingsView_Previews: PreviewProvider {
    public static var previews: some View {
        SettingsView()
    }
}
