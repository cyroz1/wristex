import SwiftUI

public struct MainTabView: View {
    @StateObject private var approvalViewModel = ApprovalViewModel()
    @StateObject private var threadListViewModel = ThreadListViewModel()
    @StateObject private var gitViewModel = GitViewModel()
    
    public init() {}
    
    public var body: some View {
        TabView {
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }

            NavigationStack {
                ThreadListView()
                    .environmentObject(threadListViewModel)
            }
            .tabItem {
                Label("Threads", systemImage: "bubble.left.and.bubble.right.fill")
            }
            
            NavigationStack {
                ApprovalListView()
                    .environmentObject(approvalViewModel)
            }
            .tabItem {
                Label("Approvals", systemImage: "checkmark.shield.fill")
            }
            
            NavigationStack {
                GitStatusView()
                    .environmentObject(gitViewModel)
            }
            .tabItem {
                Label("Git", systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .onAppear {
            // Start background polling for approvals immediately to keep the badge up-to-date
            approvalViewModel.startPolling()
        }
        .onDisappear {
            approvalViewModel.stopPolling()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    public static var previews: some View {
        MainTabView()
    }
}
