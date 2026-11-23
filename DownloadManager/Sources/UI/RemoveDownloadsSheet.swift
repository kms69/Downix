//
//  RemoveDownloadsSheet.swift
//  Download Manager for Mac
//

import SwiftUI

struct RemovalRequest: Identifiable {
    let id = UUID()
    let taskIDs: Set<UUID>
}

struct RemoveDownloadsSheet: View {
    let count: Int
    let onCancel: () -> Void
    let onRemove: (_ deleteFile: Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var alsoDeleteFile = false

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "Remove download?" : "Remove \(count) downloads?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(count == 1
                         ? "The entry will be removed from the list."
                         : "The entries will be removed from the list.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Toggle(isOn: $alsoDeleteFile) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "Also delete file from disk" : "Also delete files from disk")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text("This permanently deletes the downloaded file.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    onRemove(alsoDeleteFile)
                } label: {
                    Text("Remove")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 410)
        .background(theme.windowBackground)
    }
}
