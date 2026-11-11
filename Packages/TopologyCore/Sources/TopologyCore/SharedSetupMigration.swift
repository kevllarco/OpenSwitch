import Foundation

public enum SharedSetupMigration {
    public enum MigrationError: Error { case ambiguous, shortcutConflict }

    /// A unique paired peer on the same display can be updated from reviewed values.
    /// Entries without a peer identity require an exact configuration match.
    public static func merging(_ bindings: [InputSwitchBinding], into original: KeyboardShortcutRegistry) throws -> KeyboardShortcutRegistry {
        var registry = original
        for binding in bindings {
            let peerMatches = registry.inputSwitchBindings.filter { old in
                old.id != binding.id && old.displayID == binding.displayID
                    && binding.availabilityPeerID != nil
                    && old.availabilityPeerID == binding.availabilityPeerID
            }
            guard peerMatches.count <= 1 else { throw MigrationError.ambiguous }
            let exactMatches = registry.inputSwitchBindings.filter { old in
                old.id != binding.id && old.displayID == binding.displayID
                    && old.availabilityPeerID == binding.availabilityPeerID
                    && old.inputCode == binding.inputCode && old.effectiveTransport == binding.effectiveTransport
                    && old.peripherals == binding.peripherals && old.binding == binding.binding
            }
            let matches = peerMatches.isEmpty ? exactMatches : peerMatches
            guard matches.count <= 1 else { throw MigrationError.ambiguous }
            if let match = matches.first { registry.removeInputSwitchBinding(id: match.id) }
            guard !registry.inputSwitchBindingConflicts(binding.binding, excludingInputSwitchID: binding.id) else {
                throw MigrationError.shortcutConflict
            }
            registry.addInputSwitchBinding(binding)
        }
        return registry
    }
}
