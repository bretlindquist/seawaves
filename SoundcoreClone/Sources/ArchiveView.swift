import SwiftUI
import SwiftData
import AVFoundation

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranslationFolder.creationDate) private var folders: [TranslationFolder]
    
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: TranslationFolder?
    @State private var renameText = ""
    
    var body: some View {
        NavigationStack {
            List {
                if folders.isEmpty {
                    Text("No folders created yet.")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
                
                ForEach(folders) { folder in
                    NavigationLink(destination: FolderDetailView(folder: folder)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(folder.name, systemImage: "folder")
                                .font(.headline)
                            
                            Text("\(folder.sessions?.count ?? 0) recordings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button {
                                folderToRename = folder
                                renameText = folder.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                deleteSingleFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete(perform: deleteFolders)
            }
            .navigationTitle("Archive")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("New Folder", isPresented: $showingNewFolderAlert) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") {
                    let folder = TranslationFolder(name: newFolderName)
                    modelContext.insert(folder)
                    try? modelContext.save()
                    newFolderName = ""
                }
            }
            .alert("Rename Folder", isPresented: .constant(folderToRename != nil)) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { folderToRename = nil }
                Button("Save") {
                    if let folder = folderToRename {
                        folder.name = renameText
                        try? modelContext.save()
                    }
                    folderToRename = nil
                }
            }
        }
    }
    
    private func deleteSingleFolder(_ folder: TranslationFolder) {
        // SwiftData cascade rule will automatically handle deleting child sessions
        modelContext.delete(folder)
        try? modelContext.save()
    }
    
    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            let folder = folders[index]
            modelContext.delete(folder)
        }
        try? modelContext.save()
    }
}

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let folder: TranslationFolder
    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        List {
            if let sessions = folder.sessions, !sessions.isEmpty {
                // Sort sessions inside the folder newest-first
                ForEach(sessions.sorted(by: { $0.startTime > $1.startTime })) { session in
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
                                // Remove from folder (send back to Recent)
                                session.folder = nil
                                try? modelContext.save()
                            } label: {
                                Label("Remove from Folder", systemImage: "folder.badge.minus")
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    if var sessions = folder.sessions {
                        let sortedSessions = sessions.sorted(by: { $0.startTime > $1.startTime })
                        for index in offsets {
                            let session = sortedSessions[index]
                            if let url = session.audioFileURL {
                                try? FileManager.default.removeItem(at: url)
                            }
                            modelContext.delete(session)
                        }
                        try? modelContext.save()
                    }
                }
            } else {
                Text("Folder is empty.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(folder.name)
    }
}
