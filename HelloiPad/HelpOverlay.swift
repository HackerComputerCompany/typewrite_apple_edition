import SwiftUI

struct HelpOverlay: View {
    let settings: SettingsStore
    let onDismiss: () -> Void
    let onAction: (HelpAction) -> Void

    enum HelpAction: String {
        case cycleFont = "cycleFont"
        case cycleCursor = "cycleCursor"
        case cycleTheme = "cycleTheme"
        case cycleGutter = "cycleGutter"
        case toggleMargins = "toggleMargins"
        case cycleCols = "cycleCols"
        case toggleTypewriter = "toggleTypewriter"
        case toggleWordWrap = "toggleWordWrap"
        case toggleInsert = "toggleInsert"
    }

    private let helpItems: [(String, String, String?)] = [
        ("F2", "Cycle Font", "cycleFont"),
        ("F3", "Cycle Cursor Mode", "cycleCursor"),
        ("F4", "Cycle Background", "cycleTheme"),
        ("F5", "Cycle Line Numbers", "cycleGutter"),
        ("F6", "Toggle Page Margins", "toggleMargins"),
        ("F7", "Cycle Columns (50\u{2013}65)", "cycleCols"),
        ("F8", "Toggle Typewriter View", "toggleTypewriter"),
        ("F10", "Toggle Word Wrap", "toggleWordWrap"),
        ("Ins", "Toggle Insert/Typeover", "toggleInsert"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 12) {
                Text("Typewrite")
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Keyboard Shortcuts")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)

                Divider().overlay(Color.gray.opacity(0.4))

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(helpItems, id: \.0) { item in
                            helpRow(key: item.0, description: item.1, action: item.2)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 360)

                Button("Dismiss") {
                    onDismiss()
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(.top, 8)
            }
            .padding(20)
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(12)
            .shadow(radius: 20)
        }
    }

    private func helpRow(key: String, description: String, action: String?) -> some View {
        Button {
            guard let action, let a = HelpAction(rawValue: action) else { return }
            onAction(a)
            onDismiss()
        } label: {
            HStack {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 60, alignment: .leading)
                Text(description)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }
}

