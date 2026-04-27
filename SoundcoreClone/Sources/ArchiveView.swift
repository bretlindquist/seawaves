import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranslationFolder.creationDate) private var folders: [TranslationFolder]
    
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    NavigationLink(destination: FolderDetailView(folder: folder)) {
                        Label(folder.name, systemImage: "folder")
                            .font(.body)
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
        }
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
    let folder: TranslationFolder
    
    var body: some View {
        List {
            if let sessions = folder.sessions, !sessions.isEmpty {
                ForEach(sessions) { session in
                    // In a full implementation, this routes to the SessionDetailView
                    Text(session.name)
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
