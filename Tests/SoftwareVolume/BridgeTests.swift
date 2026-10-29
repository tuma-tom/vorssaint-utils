// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation

@main struct BridgeTests {
    static func main() {
        var failures = 0, checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; if !value { failures += 1; print("FAIL: \(label)") } }
        expect(VirtualOutputSupport.usesVirtualOutput(enabled: true, hardwareVolume: false), "Samsung fixed DisplayPort uses software fallback")
        expect(!VirtualOutputSupport.usesVirtualOutput(enabled: true, hardwareVolume: true), "AirPods native volume bypasses virtual processing")
        expect(!VirtualOutputSupport.usesVirtualOutput(enabled: false, hardwareVolume: false), "disabled fallback leaves native routing alone")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "monitor", available: ["monitor"]) == "monitor", "restore physical output we replaced")
        expect(VirtualOutputSupport.restoreUID(current: "headset", virtual: "virtual", previous: "monitor", available: ["monitor", "headset"]) == nil, "preserve external output choice")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "missing", available: ["speakers"]) == "speakers", "disconnected previous output falls back to available physical")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "monitor", available: ["monitor"], owned: false) == nil, "failed owner must not reroute another instance")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "aggregate", available: ["aggregate", "monitor"], fallback: ["monitor"]) == "aggregate", "restore existing nonphysical system-sound route")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "gone", available: ["aggregate", "monitor"], fallback: ["monitor"]) == "monitor", "only fallback destinations must be physical")
        expect(VirtualOutputSupport.inputMask(streamCount: 3, source: .virtualOutput(streams: 1, physicalStreams: 2)) == [1, 0, 0], "bridge enables virtual input and disables both physical microphone streams")
        expect(VirtualOutputSupport.inputMask(streamCount: 3, source: .processTap(physicalStreams: 2)) == [0, 0, 1], "per-app mixer enables only process tap and disables hardware microphone streams")
        expect(VirtualOutputSupport.inputMask(streamCount: 1, source: .virtualOutput(streams: 2, physicalStreams: 0)) == nil, "uncertain virtual input mapping must not enable any capture")
        expect(VirtualOutputSupport.inputMask(streamCount: 1, source: .processTap(physicalStreams: 1)) == nil, "a not-yet-published process tap cannot be mistaken for a physical microphone")
        expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Audio"), "microphone mute must exclude the playback loopback")
        expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Audio playback bridge"), "microphone mute must exclude the playback bridge")
        expect(VirtualOutputSupport.enableAction(requested: true, componentReady: false) == .install, "only enabling fallback without a component requests installation")
        expect(VirtualOutputSupport.enableAction(requested: false, componentReady: false) == .disable, "normal mixer/disabled fallback does not request installation")
        expect(VirtualOutputSupport.enableAction(requested: true, componentReady: true) == .enable, "installed component enables without another installer")
        expect(VirtualOutputSupport.RenderPlan(inputChannels: [2, 1], outputChannels: [1, 1], physicalOutputOffset: 0) != nil, "hidden input-only source renders directly to physical pair without a virtual output pair")
        expect(VirtualOutputSupport.isSoftwareDevice(VirtualOutputSupport.loopbackUID), "hidden loopback stays outside microphone controls")
        let input = AudioBufferList.allocate(maximumBuffers: 2)
        let output = AudioBufferList.allocate(maximumBuffers: 3)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        let data = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        let microphone = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        let virtual = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { data.deallocate(); microphone.deallocate(); virtual.deallocate(); left.deallocate(); right.deallocate() }
        for i in 0..<8 { data[i] = i % 2 == 0 ? 0.2 : 0.1; microphone[i] = 0.9; virtual[i] = 0.8 }
        input[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: data)
        input[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: microphone)
        output[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: virtual)
        output[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: left)
        output[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: right)
        let plan = VirtualOutputSupport.RenderPlan(inputChannels: [2, 2], outputChannels: [2, 1, 1], physicalOutputOffset: 2)
        expect(plan != nil, "accept stereo virtual source and planar physical output")
        if let plan {
            expect(plan.render(input: input, output: output), "render validated buffers")
            expect(left[0] == 0.2 && right[0] == 0.1, "copy loopback without capturing physical microphone or reapplying gain")
            expect((0..<8).allSatisfy { virtual[$0] == 0 }, "silence virtual output to prevent feedback")
            input[0].mData = nil
            expect(!plan.render(input: input, output: output) && left[0] == 0 && right[0] == 0, "missing source produces silence")
            input[0].mData = UnsafeMutableRawPointer(data)
            output[2].mData = nil
            expect(!plan.render(input: input, output: output) && left[0] == 0, "a missing physical channel must silence both channels")
            output[2].mData = UnsafeMutableRawPointer(right)
            input[0].mDataByteSize = 0
            expect(!plan.render(input: input, output: output) && left[0] == 0, "empty nonnil buffers cannot keep a silent bridge alive")
            input[0].mDataByteSize = 32
            output[2].mDataByteSize = 12
            expect(!plan.render(input: input, output: output) && left[0] == 0, "inconsistent stereo frame counts fail closed")
            output[2].mDataByteSize = 16
            input[0].mNumberChannels = 1
            expect(!plan.render(input: input, output: output), "changed input layout cannot play microphone or reinterpret samples")
        }
        expect(VirtualOutputSupport.RenderPlan(inputChannels: [1, 1], outputChannels: [2], physicalOutputOffset: 2) == nil, "reject missing physical pair")
        print("VORSSAINT AUDIO BRIDGE: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
