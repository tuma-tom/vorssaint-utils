# Software volume: microphone boundaries and verification

## Signal path

For outputs with writable native volume (for example built-in speakers or AirPods), macOS keeps its normal output and volume control. No virtual bridge is needed.

For a fixed-volume output such as a DisplayPort monitor:

`Application output → optional per-app output tap/gain → Vorssaint Audio output mix → virtual loopback input/master gain → physical output`

The public Vorssaint Audio device is output-only: its input stream list is empty. A separate hidden input-only mirror supplies the playback return to the bridge. The hidden input is a loopback of samples written to the public output. It has no physical microphone source. It is not described as a microphone terminal and is not offered in Vorssaint's microphone selector, cannot become the default input, and is excluded from global microphone-mute sweeps. Its loopback input nevertheless exists in Core Audio; hiding it in this app is not access control against another application with audio-input access.

## Physical microphone isolation

Before starting audio IO, both the bridge and per-app engines set `kAudioDevicePropertyIOProcStreamUsage` and read the mask back. The bridge enables only the virtual driver's leading input streams. A per-app engine enables only the process-output tap appended after the physical device's input streams. The observed stream count must equal the known source count plus the physical input count. An incomplete or unexpected layout, failed setter, or mismatching readback prevents startup.

Apple's HAL contract states that disabled streams have a NULL data pointer in that IOProc's callback. The bridge additionally validates its virtual-first subdevice order, copies only its declared virtual stereo source, and clears every other output. The per-app engines therefore do not need physical microphone samples, including when the selected output device also contains a microphone.

This supports a specific assurance: these playback callbacks are configured not to receive/read physical microphone samples. It does **not** prove that a microphone is powered off, prohibit another app from using it, replace the OS privacy controls, or narrow macOS's application-wide microphone permission to a single device. Isolation is verified before startup; device/format changes cause the bridge to stop or rebuild. Topology-change and physical-microphone tests on each device family remain relevant.

## Recording and network scope

The new driver and local software-volume bridge use in-memory PCM buffers. Their processing path has no audio-file writer, recording store, upload, or network client. Device-level preferences save identifiers and volume numbers, not audio.

This statement applies to this processing path. The existing screen recorder can record a microphone when explicitly enabled; explicitly selected AirPlay routing sends playback to the chosen AirPlay output. Those separate features keep their own behavior and permissions. The local validation profile enables the volume mixer only.

## Evidence and limits

Automated checks exercise driver volume/mute, loopback DSP, owner expiry, input-mask construction, unexpected stream counts, NULL/empty callback buffers, stereo/microphone isolation and output restoration. The app refuses to start these IO paths if the live HAL mask cannot be verified.

The code and tests are reviewable; they are not an independent security certification or a promise about all future changes to the original application. Runtime checks, tested devices and remaining gaps are recorded in the accompanying PR rather than inferred from unit tests.

## Browser permission prompts

A macOS microphone permission prompt was reported during Firefox playback with the earlier duplex prototype. A live follow-up found output running and input stopped; after explicitly revoking Firefox microphone permission and restarting it, playback still worked (confirmed audibly by the tester). This does not establish what triggered the earlier request.

The public driver now splits output and loopback input surfaces, as supported by upstream BlackHole. Output clients do not need to open the hidden input. Only a fresh-permission reproduction can establish whether this prevents the original prompt; an absence of another prompt after macOS has remembered a response is not that test. Do not instruct users to grant browsers microphone access merely to play media.
