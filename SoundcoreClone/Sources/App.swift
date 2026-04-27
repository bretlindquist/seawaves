import SwiftUI
import SwiftData

@main
struct SoundcoreCloneApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        // Inject SwiftData container
        .modelContainer(for: [TranslationFolder.self, TranslationSessionModel.self, TranslationSegmentModel.self])
    }
}
