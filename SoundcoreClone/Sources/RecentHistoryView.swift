import SwiftUI
import SwiftData
import AVFoundation

struct RecentHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    // Fetch only sessions that are NOT assigned to a folder yet
    @Query(filter: #Predicate<TranslationSessionModel> { $0.folder == nil }, sort: \TranslationSessionModel.startTime, order: .reverse) 
    private var recentSessions: [TranslationSessionModel]
    
    // Fetch all folders so we can move sessions into them
    @Query(sort: \TranslationFolder.creationDate) private var folders: [TranslationFolder]
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @State private var sessionToRename: TranslationSessionModel?
    @State private var newName: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                if recentSessions.isEmpty {
                    Text("No recent unarchived recordings.")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
                
                ForEach(recentSessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session, synthesizer: synthesizer)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Text("\(session.sourceLanguageCode) → \(session.targetLanguageCode)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text(session.startTime, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(session.previewText)
                                .font(.body)
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button {
                                sessionToRename = session
                                newName = session.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            if !folders.isEmpty {
                                Menu {
                                    ForEach(folders) { folder in
                                        Button(folder.name) {
                                            moveToFolder(session: session, folder: folder)
                                        }
                                    }
                                } label: {
                                    Label("Move to Folder", systemImage: "folder")
                                }
                            }
                            
                            Button(role: .destructive) {
                                deleteSingleSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("Recent")
            .alert("Rename Recording", isPresented: .constant(sessionToRename != nil)) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { sessionToRename = nil }
                Button("Save") {
                    if let session = sessionToRename {
                        session.name = newName
                        try? modelContext.save()
                    }
                    sessionToRename = nil
                }
            }
        }
    }
    
    private func moveToFolder(session: TranslationSessionModel, folder: TranslationFolder) {
        // SwiftData automatically handles the relationship mapping
        session.folder = folder
        try? modelContext.save()
    }
    
    private func deleteSingleSession(_ session: TranslationSessionModel) {
        if let url = session.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = recentSessions[index]
            if let url = session.audioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}

// Ensure the SessionDetailView is identical to the one in ArchiveView
struct SessionDetailView: View {
    let session: TranslationSessionModel
    let synthesizer: AVSpeechSynthesizer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(session.segments) { segment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(segment.sourceText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(segment.translatedText)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Button(action: { speak(text: segment.translatedText) }) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
    
    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
