import AppKit
import SwiftUI

/// Surfaces a blocked global-settings file (e.g. an on-disk schema newer than this build
/// supports) so the user understands why settings will not save, with a one-click recovery
/// that backs up the offending file and restores fresh current-schema defaults. Shown only
/// while `GlobalSettingsStore.shared.persistenceBlockReason` is non-nil.
///
/// RepoPrompt never auto-recovers from a schema it did not write; this banner is the user
/// action that clears the block.
struct GlobalSettingsPersistenceBlockBanner: View {
    @ObservedObject private var store = GlobalSettingsStore.shared
    @State private var isPresentingResetConfirmation = false

    var body: some View {
        if let reason = store.persistenceBlockReason {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message(for: reason))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Reset global settings…") { isPresentingResetConfirmation = true }
                    Button("Show file") { revealGlobalSettingsFile() }
                        .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.12))
            )
            .padding(.horizontal)
            .padding(.top, 6)
            .confirmationDialog(
                "Reset global settings?",
                isPresented: $isPresentingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Back up file and reset", role: .destructive) {
                    _ = store.recoverBlockedPersistenceAfterBackup()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The current globalSettings.json will be moved to the Backups folder and replaced with fresh defaults. Your settings will then save normally. This cannot be undone."
                )
            }
        }
    }

    private func message(for reason: GlobalSettingsPersistenceBlockReason) -> String {
        switch reason {
        case let .unsupportedFutureSchema(onDiskVersion, supportedVersion):
            "Global settings can't be saved: the settings file is schema v\(onDiskVersion), which is newer than this version of RepoPrompt supports (v\(supportedVersion)). Changes won't persist until you recover."
        case .corruptUnrecoverable:
            "Global settings can't be saved: the settings file is unreadable and couldn't be backed up. Changes won't persist until you recover."
        }
    }

    private func revealGlobalSettingsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([GlobalSettingsFileStore.defaultFileURL()])
    }
}
