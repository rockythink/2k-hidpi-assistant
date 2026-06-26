import CoreGraphics
import Foundation
import IOKit
import IOKit.i2c

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePortPrivate(_ display: CGDirectDisplayID) -> io_service_t

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithServicePrivate(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2CPrivate(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2CPrivate(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

struct NativeDDCService {
    struct VCPValue: Equatable, Codable, Hashable {
        var current: UInt16
        var maximum: UInt16

        var normalized: Double {
            guard maximum > 0 else { return 0 }
            return Double(current) / Double(maximum)
        }
    }

    struct BackendStatus: Codable, Hashable {
        var backend: DDCBackendID
        var isAvailable: Bool
        var reason: String
        var matchScore: Int?
    }

    struct VCPProbeResult: Codable, Hashable {
        var code: UInt8
        var name: String
        var backend: DDCBackendID?
        var readable: Bool
        var current: UInt16?
        var maximum: UInt16?
        var error: String?
    }

    struct VCPWriteResult: Codable, Hashable {
        var code: UInt8
        var name: String
        var backend: DDCBackendID
        var requested: UInt16
        var sent: Bool
        var verified: Bool
        var readBack: VCPValue?
        var error: String?
    }

    private let appleSiliconBackend = AppleSiliconDDCBackend()
    private let framebufferBackend = FramebufferDDCBackend()
    private let discovery = DisplayDiscoveryService()

    static let supportedWriteFeatures: [(code: UInt8, name: String)] = [
        (0x10, "brightness"),
        (0x12, "contrast"),
        (0x62, "volume")
    ]

    func setBrightness(_ value: UInt16, for displayID: CGDirectDisplayID) throws {
        try writeVCPFeatureUnverified(0x10, value: min(value, 100), for: displayID)
    }

    func setBrightness(_ value: UInt16, for display: DisplayDevice) throws {
        try writeVCPFeatureUnverified(0x10, value: min(value, 100), for: display)
    }

    func setContrast(_ value: UInt16, for displayID: CGDirectDisplayID) throws {
        try writeVCPFeatureUnverified(0x12, value: min(value, 100), for: displayID)
    }

    func setContrast(_ value: UInt16, for display: DisplayDevice) throws {
        try writeVCPFeatureUnverified(0x12, value: min(value, 100), for: display)
    }

    func setVolume(_ value: UInt16, for displayID: CGDirectDisplayID) throws {
        try writeVCPFeatureUnverified(0x62, value: min(value, 100), for: displayID)
    }

    func setVolume(_ value: UInt16, for display: DisplayDevice) throws {
        try writeVCPFeatureUnverified(0x62, value: min(value, 100), for: display)
    }

    func setPowerMode(_ value: UInt16, for displayID: CGDirectDisplayID) throws {
        try unsupportedWriteFeature(0xD6, value: value)
    }

    func getBrightness(for displayID: CGDirectDisplayID) throws -> VCPValue {
        try getVCPFeature(0x10, for: displayID)
    }

    func getContrast(for displayID: CGDirectDisplayID) throws -> VCPValue {
        try getVCPFeature(0x12, for: displayID)
    }

    func getVolume(for displayID: CGDirectDisplayID) throws -> VCPValue {
        try getVCPFeature(0x62, for: displayID)
    }

    func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        guard let display = display(for: displayID) else { return false }
        return !availableBackends(for: display).isEmpty
    }

    func backendStatuses(for display: DisplayDevice) -> [BackendStatus] {
        let appleStatus = appleSiliconBackend.status(for: display)
        let framebufferStatus = framebufferBackend.status(for: display)
        return [appleStatus, framebufferStatus]
    }

    func preferredBackendID(for display: DisplayDevice) -> DDCBackendID? {
        availableBackends(for: display).first?.id
    }

    func probe(display: DisplayDevice) -> [VCPProbeResult] {
        Self.supportedWriteFeatures.map { feature in
            do {
                let backend = try backend(for: display)
                let value = try backend.readVCP(feature.code, display: display)
                return VCPProbeResult(
                    code: feature.code,
                    name: feature.name,
                    backend: backend.id,
                    readable: true,
                    current: value.current,
                    maximum: value.maximum,
                    error: nil
                )
            } catch {
                return VCPProbeResult(
                    code: feature.code,
                    name: feature.name,
                    backend: preferredBackendID(for: display),
                    readable: false,
                    current: nil,
                    maximum: nil,
                    error: error.localizedDescription
                )
            }
        }
    }

    func getVCPFeature(_ feature: UInt8, for displayID: CGDirectDisplayID) throws -> VCPValue {
        guard let display = display(for: displayID) else {
            throw DisplayPowerError.commandFailed("找不到显示器 \(displayID)。")
        }
        let backend = try backend(for: display)
        return try backend.readVCP(feature, display: display)
    }

    func writeVCPFeature(_ feature: UInt8, value: UInt16, for displayID: CGDirectDisplayID) throws -> VCPWriteResult {
        guard Self.supportedWriteFeatures.contains(where: { $0.code == feature }) else {
            try unsupportedWriteFeature(feature, value: value)
        }
        guard let display = display(for: displayID) else {
            throw DisplayPowerError.commandFailed("找不到显示器 \(displayID)。")
        }
        return try writeVCPFeature(feature, value: value, for: display)
    }

    func writeVCPFeatureUnverified(_ feature: UInt8, value: UInt16, for displayID: CGDirectDisplayID) throws {
        guard Self.supportedWriteFeatures.contains(where: { $0.code == feature }) else {
            try unsupportedWriteFeature(feature, value: value)
        }
        guard let display = display(for: displayID) else {
            throw DisplayPowerError.commandFailed("找不到显示器 \(displayID)。")
        }
        try writeVCPFeatureUnverified(feature, value: value, for: display)
    }

    func writeVCPFeatureUnverified(_ feature: UInt8, value: UInt16, for display: DisplayDevice) throws {
        guard Self.supportedWriteFeatures.contains(where: { $0.code == feature }) else {
            try unsupportedWriteFeature(feature, value: value)
        }
        let backend = try backend(for: display)
        try backend.writeVCP(feature, value: value, display: display)
    }

    func writeVCPFeature(_ feature: UInt8, value: UInt16, for display: DisplayDevice) throws -> VCPWriteResult {
        guard let featureName = Self.supportedWriteFeatures.first(where: { $0.code == feature })?.name else {
            try unsupportedWriteFeature(feature, value: value)
        }

        let backend = try backend(for: display)
        try backend.writeVCP(feature, value: value, display: display)

        do {
            let readBack = try readBackAfterWrite(feature: feature, backend: backend, display: display)
            let verified = readBack.maximum > 0 && abs(Int(readBack.current) - Int(value)) <= max(2, Int(readBack.maximum) / 50)
            return VCPWriteResult(
                code: feature,
                name: featureName,
                backend: backend.id,
                requested: value,
                sent: true,
                verified: verified,
                readBack: readBack,
                error: verified ? nil : "write-unverified"
            )
        } catch {
            return VCPWriteResult(
                code: feature,
                name: featureName,
                backend: backend.id,
                requested: value,
                sent: true,
                verified: false,
                readBack: nil,
                error: "write-unverified: \(error.localizedDescription)"
            )
        }
    }

    private func readBackAfterWrite(feature: UInt8, backend: DDCBackend, display: DisplayDevice) throws -> VCPValue {
        var lastError: Error?
        for attempt in 0..<4 {
            if attempt > 0 {
                usleep(80_000)
            }
            do {
                return try backend.readVCP(feature, display: display)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DisplayPowerError.commandFailed("写入后无法读回 VCP 0x\(String(format: "%02X", feature))。")
    }

    private func backend(for display: DisplayDevice) throws -> DDCBackend {
        guard let backend = availableBackends(for: display).first else {
            let reasons = backendStatuses(for: display)
                .map { "\($0.backend.rawValue): \($0.reason)" }
                .joined(separator: "; ")
            throw DisplayPowerError.commandFailed("当前显示器没有可用 DDC/CI 后端。\(reasons)")
        }
        return backend
    }

    private func availableBackends(for display: DisplayDevice) -> [DDCBackend] {
        [appleSiliconBackend, framebufferBackend].filter { $0.status(for: display).isAvailable }
    }

    private func display(for displayID: CGDirectDisplayID) -> DisplayDevice? {
        discovery.discover(language: .system).first { $0.id == displayID }
    }

    private func unsupportedWriteFeature(_ feature: UInt8, value _: UInt16) throws -> Never {
        throw DisplayPowerError.commandFailed("VCP 0x\(String(format: "%02X", feature)) 未开放真实写入。")
    }
}

enum DDCBackendID: String, Codable, Hashable {
    case appleSiliconIOAVService
    case framebufferI2C

    func label(language: AppLanguage) -> String {
        switch self {
        case .appleSiliconIOAVService:
            language.resolvedCode == "zh" ? "Apple Silicon DDC" : "Apple Silicon DDC"
        case .framebufferI2C:
            language.resolvedCode == "zh" ? "Framebuffer DDC" : "Framebuffer DDC"
        }
    }
}

protocol DDCBackend {
    var id: DDCBackendID { get }
    func status(for display: DisplayDevice) -> NativeDDCService.BackendStatus
    func readVCP(_ feature: UInt8, display: DisplayDevice) throws -> NativeDDCService.VCPValue
    func writeVCP(_ feature: UInt8, value: UInt16, display: DisplayDevice) throws
}

private struct FramebufferDDCBackend: DDCBackend {
    var id: DDCBackendID { .framebufferI2C }

    func status(for display: DisplayDevice) -> NativeDDCService.BackendStatus {
        let framebuffer = CGDisplayIOServicePortPrivate(display.id)
        guard framebuffer != 0 else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "no framebuffer service", matchScore: nil)
        }

        var count: IOItemCount = 0
        let countResult = IOFBGetI2CInterfaceCount(framebuffer, &count)
        guard countResult == kIOReturnSuccess, count > 0 else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "no I2C/DDC bus", matchScore: nil)
        }

        return NativeDDCService.BackendStatus(backend: id, isAvailable: true, reason: "\(count) I2C/DDC bus(es)", matchScore: nil)
    }

    func readVCP(_ feature: UInt8, display: DisplayDevice) throws -> NativeDDCService.VCPValue {
        let framebuffer = try framebuffer(for: display)
        let busCount = try i2cBusCount(framebuffer: framebuffer)
        var lastError: Error?
        for bus in 0..<busCount {
            do {
                return try sendGetVCP(feature: feature, framebuffer: framebuffer, bus: IOOptionBits(bus))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DisplayPowerError.commandFailed("DDC 读取失败。")
    }

    func writeVCP(_ feature: UInt8, value: UInt16, display: DisplayDevice) throws {
        let framebuffer = try framebuffer(for: display)
        let busCount = try i2cBusCount(framebuffer: framebuffer)
        var lastError: Error?
        for bus in 0..<busCount {
            do {
                try sendSetVCP(feature: feature, value: value, framebuffer: framebuffer, bus: IOOptionBits(bus))
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DisplayPowerError.commandFailed("DDC 指令发送失败。")
    }

    private func framebuffer(for display: DisplayDevice) throws -> io_service_t {
        let framebuffer = CGDisplayIOServicePortPrivate(display.id)
        guard framebuffer != 0 else {
            throw DisplayPowerError.commandFailed("当前连接没有暴露显示器 framebuffer，无法使用 DDC/CI。")
        }
        return framebuffer
    }

    private func i2cBusCount(framebuffer: io_service_t) throws -> IOItemCount {
        var count: IOItemCount = 0
        let countResult = IOFBGetI2CInterfaceCount(framebuffer, &count)
        guard countResult == kIOReturnSuccess, count > 0 else {
            throw DisplayPowerError.commandFailed("当前显示器没有可用 I2C/DDC bus。")
        }
        return count
    }

    private func sendSetVCP(feature: UInt8, value: UInt16, framebuffer: io_service_t, bus: IOOptionBits) throws {
        let connect = try i2cConnect(framebuffer: framebuffer, bus: bus)
        defer { IOI2CInterfaceClose(connect, 0) }

        var payload = makeFramebufferSetPayload(feature: feature, value: value)
        let payloadCount = payload.count
        try payload.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw DisplayPowerError.commandFailed("DDC payload 为空。")
            }

            var request = IOI2CRequest()
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            request.sendAddress = 0x6E
            request.replyAddress = 0x6F
            request.sendBytes = UInt32(payloadCount)
            request.sendBuffer = vm_address_t(UInt(bitPattern: baseAddress))
            request.minReplyDelay = 40_000_000

            let result = IOI2CSendRequest(connect, 0, &request)
            guard result == kIOReturnSuccess, request.result == kIOReturnSuccess else {
                throw DisplayPowerError.commandFailed("DDC 指令失败：\(result)/\(request.result)。")
            }
        }
    }

    private func sendGetVCP(feature: UInt8, framebuffer: io_service_t, bus: IOOptionBits) throws -> NativeDDCService.VCPValue {
        let connect = try i2cConnect(framebuffer: framebuffer, bus: bus)
        defer { IOI2CInterfaceClose(connect, 0) }

        var payload = makeFramebufferGetPayload(feature: feature)
        var reply = [UInt8](repeating: 0, count: 12)
        let payloadCount = payload.count
        let replyCount = reply.count

        return try payload.withUnsafeMutableBytes { payloadBytes in
            try reply.withUnsafeMutableBytes { replyBytes in
                guard let payloadAddress = payloadBytes.baseAddress,
                      let replyAddress = replyBytes.baseAddress else {
                    throw DisplayPowerError.commandFailed("DDC 读取 buffer 为空。")
                }

                var request = IOI2CRequest()
                request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                request.replyTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                request.sendAddress = 0x6E
                request.replyAddress = 0x6F
                request.sendBytes = UInt32(payloadCount)
                request.replyBytes = UInt32(replyCount)
                request.sendBuffer = vm_address_t(UInt(bitPattern: payloadAddress))
                request.replyBuffer = vm_address_t(UInt(bitPattern: replyAddress))
                request.minReplyDelay = 40_000_000

                let result = IOI2CSendRequest(connect, 0, &request)
                guard result == kIOReturnSuccess, request.result == kIOReturnSuccess else {
                    throw DisplayPowerError.commandFailed("DDC 读取失败：\(result)/\(request.result)。")
                }

                let response = Array(replyBytes.bindMemory(to: UInt8.self).prefix(Int(request.replyBytes)))
                return try DDCCodec.parseGetVCPReply(response, feature: feature)
            }
        }
    }

    private func i2cConnect(framebuffer: io_service_t, bus: IOOptionBits) throws -> IOI2CConnectRef {
        var interface: io_service_t = 0
        let copyResult = IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface)
        guard copyResult == kIOReturnSuccess, interface != 0 else {
            throw DisplayPowerError.commandFailed("无法打开 I2C bus \(bus)。")
        }
        defer { IOObjectRelease(interface) }

        var connect: IOI2CConnectRef?
        let openResult = IOI2CInterfaceOpen(interface, 0, &connect)
        guard openResult == kIOReturnSuccess, let connect else {
            throw DisplayPowerError.commandFailed("无法连接 I2C bus \(bus)。")
        }
        return connect
    }

    private func makeFramebufferSetPayload(feature: UInt8, value: UInt16) -> [UInt8] {
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        var bytes: [UInt8] = [0x51, 0x84, 0x03, feature, high, low]
        bytes.append(DDCCodec.checksum(seed: 0x6E, bytes: bytes))
        return bytes
    }

    private func makeFramebufferGetPayload(feature: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0x51, 0x82, 0x01, feature]
        bytes.append(DDCCodec.checksum(seed: 0x6E, bytes: bytes))
        return bytes
    }
}

private struct AppleSiliconDDCBackend: DDCBackend {
    var id: DDCBackendID { .appleSiliconIOAVService }

    func status(for display: DisplayDevice) -> NativeDDCService.BackendStatus {
        guard !display.isBuiltin else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "built-in display", matchScore: nil)
        }
        guard let candidate = bestCandidate(for: display) else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "no DCPAVServiceProxy match", matchScore: nil)
        }
        guard candidate.hasExternalAVService else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "matched service is not external", matchScore: candidate.matchScore)
        }
        guard candidate.matchScore > 0 else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "DCPAVServiceProxy match score is 0", matchScore: candidate.matchScore)
        }
        guard service(for: candidate) != nil else {
            return NativeDDCService.BackendStatus(backend: id, isAvailable: false, reason: "IOAVService unavailable", matchScore: candidate.matchScore)
        }
        return NativeDDCService.BackendStatus(backend: id, isAvailable: true, reason: "external DCPAVServiceProxy", matchScore: candidate.matchScore)
    }

    func readVCP(_ feature: UInt8, display: DisplayDevice) throws -> NativeDDCService.VCPValue {
        let service = try service(for: display)
        var send: [UInt8] = [feature]
        var reply = [UInt8](repeating: 0, count: 11)
        try performDDC(service: service, send: &send, reply: &reply)
        return try DDCCodec.parseGetVCPReply(reply, feature: feature)
    }

    func writeVCP(_ feature: UInt8, value: UInt16, display: DisplayDevice) throws {
        let service = try service(for: display)
        var send: [UInt8] = [feature, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        try performDDC(service: service, send: &send, reply: &reply)
    }

    private func bestCandidate(for display: DisplayDevice) -> DisplayTransportDiagnostic? {
        DisplayTransportDiagnosticsService()
            .diagnostics(for: display)
            .filter(\.hasExternalAVService)
            .sorted {
                if $0.matchScore != $1.matchScore { return $0.matchScore > $1.matchScore }
                return $0.serviceLocation < $1.serviceLocation
            }
            .first
    }

    private func service(for display: DisplayDevice) throws -> CFTypeRef {
        guard let candidate = bestCandidate(for: display), candidate.matchScore > 0, candidate.hasExternalAVService else {
            throw DisplayPowerError.commandFailed("没有匹配到可用的外接 DCPAVServiceProxy。")
        }
        guard let service = service(for: candidate) else {
            throw DisplayPowerError.commandFailed("无法创建 IOAVService。")
        }
        return service
    }

    private func service(for candidate: DisplayTransportDiagnostic) -> CFTypeRef? {
        var matchedService: CFTypeRef?
        enumerateDCPAVServices { serviceCandidate in
            guard matchedService == nil,
                  serviceCandidate.serviceLocation == candidate.serviceLocation,
                  serviceCandidate.location == "External" else { return }
            matchedService = IOAVServiceCreateWithServicePrivate(kCFAllocatorDefault, serviceCandidate.service)?.takeRetainedValue()
        }
        return matchedService
    }

    private func performDDC(service: CFTypeRef, send: inout [UInt8], reply: inout [UInt8]) throws {
        let dataAddress: UInt8 = 0x51
        let ddcAddress: UInt8 = 0x37
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let seed = send.count == 1 ? ddcAddress << 1 : (ddcAddress << 1) ^ dataAddress
        packet[packet.count - 1] = DDCCodec.checksum(seed: seed, bytes: Array(packet.dropLast()))
        let packetCount = UInt32(packet.count)
        let replyCount = UInt32(reply.count)

        var lastError = kIOReturnError
        for _ in 0..<5 {
            for _ in 0..<2 {
                usleep(10_000)
                let writeResult = packet.withUnsafeMutableBytes { bytes in
                    IOAVServiceWriteI2CPrivate(service, UInt32(ddcAddress), UInt32(dataAddress), bytes.baseAddress!, packetCount)
                }
                lastError = writeResult
                if writeResult == kIOReturnSuccess {
                    break
                }
            }

            guard !reply.isEmpty else {
                if lastError == kIOReturnSuccess { return }
                usleep(20_000)
                continue
            }

            usleep(50_000)
            let readResult = reply.withUnsafeMutableBytes { bytes in
                IOAVServiceReadI2CPrivate(service, UInt32(ddcAddress), UInt32(dataAddress), bytes.baseAddress!, replyCount)
            }
            lastError = readResult
            if readResult == kIOReturnSuccess,
               reply.count >= 2,
               DDCCodec.checksum(seed: 0x50, bytes: Array(reply.dropLast())) == reply[reply.count - 1] {
                return
            }
            usleep(20_000)
        }

        throw DisplayPowerError.commandFailed("Apple Silicon DDC 通信失败：\(lastError)。")
    }

    private func enumerateDCPAVServices(_ handler: (DCPAVServiceCandidate) -> Void) {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        let framebufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]
        var serviceLocation = 0
        var pendingServiceLocation = 0

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { return }
            defer { IOObjectRelease(entry) }

            let name = registryName(for: entry)
            if framebufferNames.contains(where: { name.contains($0) }) {
                serviceLocation += 1
                pendingServiceLocation = serviceLocation
            } else if name.contains("DCPAVServiceProxy") {
                handler(DCPAVServiceCandidate(
                    serviceLocation: pendingServiceLocation,
                    location: stringProperty("Location", from: entry),
                    service: entry
                ))
            }
        }
    }

    private func registryName(for entry: io_service_t) -> String {
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { nameBuffer.deallocate() }
        guard IORegistryEntryGetName(entry, nameBuffer) == KERN_SUCCESS else { return "" }
        return String(cString: nameBuffer)
    }

    private func stringProperty(_ key: String, from entry: io_service_t) -> String {
        guard let unmanaged = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) else {
            return ""
        }
        return unmanaged.takeRetainedValue() as? String ?? ""
    }

    private struct DCPAVServiceCandidate {
        var serviceLocation: Int
        var location: String
        var service: io_service_t
    }
}

enum DDCCodec {
    static func checksum(seed: UInt8, bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }

    static func parseGetVCPReply(_ reply: [UInt8], feature: UInt8) throws -> NativeDDCService.VCPValue {
        let bytes = Array(reply.drop(while: { $0 == 0 }))
        guard !bytes.isEmpty else {
            throw DisplayPowerError.commandFailed("DDC 读取返回为空。")
        }

        if let featureIndex = bytes.indices.first(where: { bytes[$0] == feature }),
           bytes.distance(from: featureIndex, to: bytes.endIndex) >= 6 {
            let typeIndex = bytes.index(after: featureIndex)
            let maxHighIndex = bytes.index(after: typeIndex)
            let maxLowIndex = bytes.index(after: maxHighIndex)
            let currentHighIndex = bytes.index(after: maxLowIndex)
            let currentLowIndex = bytes.index(after: currentHighIndex)

            let maximum = UInt16(bytes[maxHighIndex]) << 8 | UInt16(bytes[maxLowIndex])
            let current = UInt16(bytes[currentHighIndex]) << 8 | UInt16(bytes[currentLowIndex])
            if maximum > 0 {
                return NativeDDCService.VCPValue(current: current, maximum: maximum)
            }
        }

        throw DisplayPowerError.commandFailed("无法解析 DDC 读取返回：\(reply.map { String(format: "%02X", $0) }.joined(separator: " "))。")
    }
}
