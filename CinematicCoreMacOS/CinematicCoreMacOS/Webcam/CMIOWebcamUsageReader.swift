import CoreMediaIO
import Foundation

/// Only CoreMediaIO metadata reads. Never opens or starts a camera/stream.
nonisolated enum CMIOWebcamUsageReader {
    // The existing extension's fixed device UUID. No display-name matching.
    static let deviceUUID = UUID(uuidString: "6089D528-8D1B-45C5-8D24-E76CD0E2C3BF")!

    static func matchesDeviceUID(_ uid: String) -> Bool {
        UUID(uuidString: uid) == deviceUUID
    }

    static func decode(status: OSStatus, size: UInt32, value: UInt32) -> WebcamUsageState {
        guard status == noErr, size == MemoryLayout<UInt32>.size else { return .unknown }
        switch value {
        case 0: return .notInUse
        case 1: return .inUse
        default: return .unknown
        }
    }

    static func read() -> WebcamUsageState {
        var address = property(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<CMIODeviceID>.size) == 0,
              size <= 65536 else { return .unknown }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, $0.baseAddress!)
        }
        guard status == noErr, used == size else { return .unknown }
        let matches = devices.filter { device in
            var uidAddress = property(kCMIODevicePropertyDeviceUID)
            guard CMIOObjectHasProperty(device, &uidAddress) else { return false }
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            let result = CMIOObjectGetPropertyData(device, &uidAddress, 0, nil, uidSize, &uidSize, &uid)
            return result == noErr && uidSize == MemoryLayout<CFString>.size && matchesDeviceUID(uid as String)
        }
        guard matches.count == 1, let device = matches.first else { return .unknown }
        var running = property(kCMIODevicePropertyDeviceIsRunningSomewhere)
        guard CMIOObjectHasProperty(device, &running) else { return .unknown }
        var value: UInt32 = 0
        var valueSize = UInt32(MemoryLayout<UInt32>.size)
        let result = CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize, &valueSize, &value)
        return decode(status: result, size: valueSize, value: value)
    }

    private static func property(_ selector: Int) -> CMIOObjectPropertyAddress {
        .init(mSelector: CMIOObjectPropertySelector(selector), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }
}
