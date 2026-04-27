import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0
    @Environment(\.modelContext) private var modelContext
    
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
        .onAppear {
            migratePreviewText()
        }
    }
    
    private func migratePreviewText() {
        Task.detached {
            // Give the app a moment to load UI before doing heavy DB work
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                do {
                    let descriptor = FetchDescriptor<TranslationSessionModel>()
                    let sessions = try modelContext.fetch(descriptor)
                    var migratedCount = 0
                    for session in sessions {
                        if session.cachedPreviewText == nil {
                            session.cachedPreviewText = session.segments.first?.sourceText ?? "Empty Session"
                            migratedCount += 1
                        }
                    }
                    if migratedCount > 0 {
                        try? modelContext.save()
                        print("Migrated \(migratedCount) sessions with cachedPreviewText")
                    }
                } catch {
                    print("Failed to migrate preview text: \(error)")
                }
            }
        }
    }
}

