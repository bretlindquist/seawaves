import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TranslateView()
                .tabItem {
                    Label("Translate", systemImage: "mic.fill")
                }
                .tag(0)
            
            RecentHistoryView()
                .tabItem {
                    Label("Recent", systemImage: "clock.fill")
                }
                .tag(1)
            
            ArchiveView()
                .tabItem {
                    Label("Archive", systemImage: "folder.fill")
                }
                .tag(2)
        }
    }
}

// Temporary stubs so the project builds while we refactor the audio engine
struct TranslateView: View { var body: some View { Text("Translate") } }
struct RecentHistoryView: View { var body: some View { Text("Recent") } }
struct ArchiveView: View { var body: some View { Text("Archive") } }
