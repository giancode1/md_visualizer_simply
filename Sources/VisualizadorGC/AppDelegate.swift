import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedAtLaunch = false

    // sin esto, abrir un .md desde el Finder crea además una pestaña «Sin título» vacía
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !openedAtLaunch }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        urls.forEach { Workspace.shared.open($0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openQuick() { QuickOpen.shared.show() }
    @objc private func newWindow() {
        DocWindowController.newWindowNext = true
        NSDocumentController.shared.newDocument(nil)
    }
    @objc private func closeFolder() { Workspace.shared.folder = nil }
    @objc private func openFolder() { Workspace.shared.chooseFolder() }

    private static func buildMenu() -> NSMenu {
        let main = NSMenu()
        @discardableResult func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = sub
            return sub
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.tag = tag
            return i
        }

        add("VisualizadorGC", [item("Salir", #selector(NSApplication.terminate(_:)), "q")])
        add("Archivo", [
            item("Nuevo", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Nueva pestaña", #selector(NSDocumentController.newDocument(_:)), "t"),
            item("Nueva ventana", #selector(newWindow), "N", [.command, .shift]),
            item("Abrir…", #selector(NSDocumentController.openDocument(_:)), "o"),
            item("Abrir rápido…", #selector(openQuick), "p"),
            item("Abrir carpeta…", #selector(openFolder), "O", [.command, .shift]),
            item("Cerrar carpeta", #selector(closeFolder)),
            .separator(),
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
            item("Guardar", #selector(NSDocument.save(_:)), "s"),
            item("Guardar como…", #selector(NSDocument.saveAs(_:)), "S", [.command, .shift]),
            .separator(),
            item("Exportar a PDF…", #selector(DocWindowController.exportPDF(_:))),
            item("Exportar a HTML…", #selector(DocWindowController.exportHTML(_:))),
        ])
        add("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Rehacer", Selector(("redo:")), "Z", [.command, .shift]),
            .separator(),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Buscar…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
            item("Buscar siguiente", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue)),
            item("Buscar anterior", #selector(NSTextView.performFindPanelAction(_:)), "G", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue)),
        ])
        add("Vista", [
            item("Preview", #selector(DocWindowController.showRendered(_:)), "1"),
            item("Markdown", #selector(DocWindowController.showRaw(_:)), "2"),
            item("Split (Markdown + Preview)", #selector(DocWindowController.showSplit(_:)), "3"),
            .separator(),
            item("Panel lateral", #selector(DocWindowController.toggleSide(_:)), "b"),
        ])
        NSApp.windowsMenu = add("Ventana", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            .separator(),
            item("Pestaña siguiente", #selector(NSWindow.selectNextTab(_:)), "\t", .control),
            item("Pestaña anterior", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift]),
            item("Mostrar barra de pestañas", #selector(NSWindow.toggleTabBar(_:))),
        ])
        return main
    }
}
