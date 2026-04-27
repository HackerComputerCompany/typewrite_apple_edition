// TypewriteAppleEditionMacApp.swift — macOS entry. Document model and editor are shared with iPad.

import SwiftUI

private func postEditorMenuAction(_ action: EditorMenuAction) {
    NotificationCenter.default.post(
        name: .editorMenuAction,
        object: nil,
        userInfo: ["action": action.rawValue]
    )
}

@main
struct TypewriteAppleEditionMacApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { TypewriteDocument() }) { file in
            EditorView(document: file.document)
        }
        .commands {
            CommandMenu("View") {
                Toggle("Show Floating Toolbar", isOn: Binding(
                    get: { SettingsStore.shared.macShowFloatingToolbar },
                    set: { SettingsStore.shared.macShowFloatingToolbar = $0 }
                ))
                .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
                Button("Window Background…") {
                    postEditorMenuAction(.showWindowBackground)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
            CommandMenu("Typewrite") {
                Button("Keyboard Help…") {
                    postEditorMenuAction(.showHelp)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
                Divider()
                Button("Next Font") {
                    postEditorMenuAction(.cycleFont)
                }
                Button("Next Theme") {
                    postEditorMenuAction(.cycleTheme)
                }
                Button("Next Cursor Style") {
                    postEditorMenuAction(.cycleCursor)
                }
                Divider()
                Button("Toggle Typewriter View") {
                    postEditorMenuAction(.toggleTypewriter)
                }
                Button("Toggle Page Margins") {
                    postEditorMenuAction(.toggleMargins)
                }
                Button("Toggle Insert / Typeover") {
                    postEditorMenuAction(.toggleInsert)
                }
                Divider()
                Button("Next Line Number Mode") {
                    postEditorMenuAction(.cycleGutter)
                }
                Button("Cycle Column Width") {
                    postEditorMenuAction(.cycleCols)
                }
                Button("Toggle Word Wrap") {
                    postEditorMenuAction(.toggleWordWrap)
                }
                Button("Toggle Sounds") {
                    postEditorMenuAction(.toggleSounds)
                }
                Button("Cycle check-in interval") {
                    postEditorMenuAction(.cycleStatusPulse)
                }
                Divider()
                Button("Import Text…") {
                    postEditorMenuAction(.openDocument)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Export Text…") {
                    postEditorMenuAction(.exportDocument)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
