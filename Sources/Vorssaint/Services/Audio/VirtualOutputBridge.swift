// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import Foundation
import Darwin

/// The driver applies master gain to its loopback input. This bridge does no
/// gain processing and never captures a hardware microphone.
final class VirtualOutputBridge {
    final class Progress {
        private var count: Int64 = 0
        var cycles: Int64 { OSAtomicAdd64Barrier(0, &count) }
        func advance() { OSAtomicIncrement64Barrier(&count) }
    }
    let progress = Progress()
    let physicalUID: String
    private var aggregate = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var rate: Float64 = 0
    private var physical = AudioObjectID(0)
    private var inputLayout: [UInt32] = []
    private var outputLayout: [UInt32] = []

    init(virtual: AudioObjectID, physicalUID: String) throws {
        self.physicalUID = physicalUID
        guard let virtualUID = VirtualOutputHAL.uid(virtual), VirtualOutputSupport.isSoftwareOutput(virtualUID) else {
            throw Failure("Unexpected software volume input device")
        }
        // The public device has output streams only. Keep the playback return
        // on a separate hidden input so output clients need not open input IO.
        let sourceUID = virtualUID == VirtualOutputSupport.deviceUID ? VirtualOutputSupport.loopbackUID : virtualUID
        guard let sourceDevice = VirtualOutputHAL.device(sourceUID) else {
            throw Failure("Software volume loopback input is unavailable")
        }
        let sourceOutputs = VirtualOutputHAL.channels(sourceDevice, scope: kAudioObjectPropertyScopeOutput).reduce(0, +)
        guard let physical = VirtualOutputHAL.device(physicalUID),
              VirtualOutputHAL.read(physical, kAudioDevicePropertyNominalSampleRate, into: &rate),
              rate.isFinite, rate > 0 else { throw Failure("Physical output is unavailable", issue: .outputUnavailable) }
        self.physical = physical
        guard VirtualOutputHAL.write(virtual, kAudioDevicePropertyNominalSampleRate, value: rate) == noErr else {
            throw Failure("Could not match the virtual output sample rate")
        }
        var virtualRate: Float64 = 0
        for _ in 0..<30 {
            _ = VirtualOutputHAL.read(virtual, kAudioDevicePropertyNominalSampleRate, into: &virtualRate)
            if virtualRate == rate { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard virtualRate == rate else { throw Failure("Virtual output did not settle at the physical sample rate") }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Audio playback bridge",
            kAudioAggregateDeviceUIDKey: "com.vorssaint.utils.software-volume.bridge.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: physicalUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: sourceUID, kAudioSubDeviceDriftCompensationKey: true],
                [kAudioSubDeviceUIDKey: physicalUID, kAudioSubDeviceDriftCompensationKey: false]
            ]
        ]
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate) == noErr, aggregate != 0 else {
            throw Failure("Could not create the playback bridge")
        }
        do {
            var alive: UInt32 = 0
            for _ in 0..<30 {
                _ = VirtualOutputHAL.read(aggregate, kAudioDevicePropertyDeviceIsAlive, into: &alive)
                if alive != 0 { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard alive != 0 else { throw Failure("Playback bridge did not become ready") }
            // HAL owns the order. Refuse an unexpected one instead of guessing
            // and accidentally playing physical microphone input.
            var property = VirtualOutputHAL.address(kAudioAggregateDevicePropertyFullSubDeviceList)
            var list: Unmanaged<CFArray>?, size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
            guard AudioObjectGetPropertyData(aggregate, &property, 0, nil, &size, &list) == noErr,
                  let list, let order = list.takeRetainedValue() as? [String],
                  order == [sourceUID, physicalUID],
                  VirtualOutputHAL.floatFormats(aggregate, scope: kAudioObjectPropertyScopeInput),
                  VirtualOutputHAL.floatFormats(aggregate, scope: kAudioObjectPropertyScopeOutput) else {
                throw Failure("Playback bridge has an unsupported channel layout")
            }
            inputLayout = VirtualOutputHAL.channels(aggregate, scope: kAudioObjectPropertyScopeInput)
            outputLayout = VirtualOutputHAL.channels(aggregate, scope: kAudioObjectPropertyScopeOutput)
            guard VirtualOutputHAL.channels(sourceDevice, scope: kAudioObjectPropertyScopeInput).reduce(0,+) == 2,
                  VirtualOutputHAL.channels(virtual, scope: kAudioObjectPropertyScopeOutput).reduce(0,+) == 2,
                  sourceOutputs == (sourceUID == virtualUID ? 2 : 0),
                  let plan = VirtualOutputSupport.RenderPlan(inputChannels: inputLayout, outputChannels: outputLayout, physicalOutputOffset: Int(sourceOutputs)) else {
                throw Failure("Playback bridge requires a stereo virtual input and stereo physical output")
            }
            guard let virtualInputs = VirtualOutputHAL.inputStreamCount(sourceDevice),
                  let physicalInputs = VirtualOutputHAL.inputStreamCount(physical) else {
                throw Failure("Could not verify that physical microphone streams are disabled", issue: .privacyUnverified)
            }
            let progress = progress
            guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil, { _, input, _, output, _ in
                let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                let target = UnsafeMutableAudioBufferListPointer(output)
                if plan.render(input: source, output: target) { progress.advance() }
            }) == noErr, let ioProc else { throw Failure("Could not create playback callback") }
            guard VirtualOutputHAL.isolateInput(aggregate, ioProc: ioProc,
                    source: .virtualOutput(streams: virtualInputs, physicalStreams: physicalInputs)) else {
                throw Failure("Could not verify physical input isolation", issue: .privacyUnverified)
            }
            guard AudioDeviceStart(aggregate, ioProc) == noErr else { throw Failure("Could not start playback bridge") }
            for _ in 0..<20 {
                if progress.cycles > 0 { return }
                Thread.sleep(forTimeInterval: 0.05)
            }
            throw Failure("Playback bridge is not rendering")
        } catch { stop(); throw error }
    }
    func configurationIsCurrent() -> Bool {
        var alive: UInt32 = 0, actual: Float64 = 0
        return VirtualOutputHAL.read(physical, kAudioDevicePropertyDeviceIsAlive, into: &alive) && alive != 0
            && VirtualOutputHAL.read(physical, kAudioDevicePropertyNominalSampleRate, into: &actual) && actual == rate
            && VirtualOutputHAL.channels(aggregate, scope: kAudioObjectPropertyScopeInput) == inputLayout
            && VirtualOutputHAL.channels(aggregate, scope: kAudioObjectPropertyScopeOutput) == outputLayout
            && VirtualOutputHAL.floatFormats(aggregate, scope: kAudioObjectPropertyScopeInput)
            && VirtualOutputHAL.floatFormats(aggregate, scope: kAudioObjectPropertyScopeOutput)
    }
    func stop() {
        if let ioProc, aggregate != 0 {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        ioProc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
    }
    deinit { stop() }
    struct Failure: LocalizedError {
        let errorDescription: String?
        let issue: VirtualOutputSupport.Issue
        init(_ message: String, issue: VirtualOutputSupport.Issue = .setupFailed) {
            errorDescription = message; self.issue = issue
        }
    }
}
