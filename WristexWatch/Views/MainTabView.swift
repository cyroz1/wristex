import SwiftUI

struct CompactWatchHeader<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 2)
            content
        }
        .frame(height: 26)
        .padding(.horizontal, 3)
    }
}

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
        // The watch page indicator reserves a large footer on 40mm screens.
        // Keep swipe paging, but remove the dots and their extra bottom gutter.
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
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
