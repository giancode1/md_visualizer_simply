import AppKit

/// Carpeta de trabajo compartida por todas las ventanas.
final class Workspace {
    static let shared = Workspace()
    static let changed = Notification.Name("VisualizadorGCWorkspaceChanged")
    static let extensions: Set<String> = ["md", "markdown", "txt"]
    private static let ignored: Set<String> = ["node_modules", ".git", "vendor", ".build", "Pods", "dist", "build", ".next"]

    /// Carpeta de trabajo y estado del panel lateral: valen mientras la app esté abierta; cada arranque empieza limpio.
    var folder: URL? { didSet { NotificationCenter.default.post(name: Self.changed, object: nil) } }
    var sidebarVisible = false
    var sidebarFiles = false

    private init() {}

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Abrir carpeta"
        if panel.runModal() == .OK, let url = panel.url { open(folder: url) }
    }

    static func isDocument(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    func openFile(_ url: URL) { NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in } }

    /// Una carpeta pasa a ser la carpeta de trabajo; un archivo se abre como documento.
    func open(_ url: URL) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { open(folder: url) } else { openFile(url) }
    }

    /// Fija la carpeta de trabajo y muestra el panel de archivos (también si aún no hay ninguna ventana).
    func open(folder url: URL) {
        sidebarVisible = true
        sidebarFiles = true
        folder = url
        if NSDocumentController.shared.documents.isEmpty { NSDocumentController.shared.newDocument(nil) }
    }

    /// Hijos visibles de una carpeta: primero las subcarpetas, luego los .md/.txt.
    static func children(of dir: URL) -> [FileNode] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return items.compactMap { url -> FileNode? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { return ignored.contains(url.lastPathComponent) ? nil : FileNode(url: url, isDir: true) }
            return isDocument(url) ? FileNode(url: url, isDir: false) : nil
        }.sorted { ($0.isDir ? 0 : 1, $0.url.lastPathComponent.lowercased()) < ($1.isDir ? 0 : 1, $1.url.lastPathComponent.lowercased()) }
    }

    /// Todos los .md/.txt bajo la carpeta (para ⌘P). ponytail: tope de 5000 archivos.
    func scan() -> [URL] {
        guard let folder, let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if Self.ignored.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            if Self.isDocument(url) { found.append(url) }
            if found.count >= 5000 { break }
        }
        return found
    }
}

final class FileNode {
    let url: URL
    let isDir: Bool
    lazy var children: [FileNode] = Workspace.children(of: url)
    init(url: URL, isDir: Bool) { self.url = url; self.isDir = isDir }
}
