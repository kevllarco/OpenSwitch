# Guided computer setup

## User journey

1. Get started identifies this Mac and its available devices. The user confirms its name.
2. Bonjour discovery lists other OpenSwitch installations. The user chooses one and accepts the pairing request on that Mac.
3. The user assigns a shared monitor input to each computer.
4. For each selected keyboard and mouse, the user assigns the Easy-Switch slot for each computer. Unknown mappings remain unselected.
5. A review shows both computers, inputs, slots and shortcuts. Save applies the reviewed setup to both Macs and reports each result.
6. Later additions reuse the existing profiles and identify peers by their OpenSwitch IDs.

## Data boundaries

The shared setup needs a version, a stable setup ID and revision, and computer profiles keyed by OpenSwitch peer ID. A profile contains the user's display name, monitor input and transport, optional peripheral names and slots, and the intended shortcut. It must not contain credentials, raw input events, or a display record ID from another Mac.

Each Mac maintains its own mapping from the shared monitor identity to a local display record. Match only when the local monitor is unambiguous; otherwise ask the user to select it locally. Shortcut availability is checked locally and an unavailable shortcut is reported for that Mac.

Existing input-switch bindings remain usable until a reviewed setup is successfully applied. Migration must preserve their IDs, inputs, peripheral settings and shortcuts; names alone are not sufficient evidence to merge two profiles.

## Shared save

Use the existing authenticated paired connection, with a separately versioned and bounded setup message. Authenticate the sender and intended recipient by peer ID, validate the complete payload and reject unsupported versions or invalid values before changing settings. The receiver resolves its local monitor and checks shortcut conflicts before applying. Applying a revision must be idempotent.

The initiating Mac records the setup as pending until the other Mac acknowledges the same setup ID and revision. A timeout, unsupported peer, ambiguous display or local conflict must remain visible as pending or failed with a retry path. An acknowledgement must mean the receiver persisted and applied the settings; it is not proof that physical switching works. Never replace a newer revision with an older retry.

## Implementation order

1. Define and validate the versioned shared setup and local display mapping, including migration from existing bindings.
2. Add authenticated transfer, acknowledgement and durable pending/retry state.
3. Build the guided screens and a reviewable preview using sample data.
4. Connect save, migration, menu state and per-Mac shortcut conflict reporting.
5. Verify interrupted saves, retries, duplicate identities, pairing rejection and display ambiguity; then verify physical switching in both directions on the user's Macs.

The preview must not write live configuration or switch hardware. Review it before replacing the installed app.
