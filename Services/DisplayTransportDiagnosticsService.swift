import CoreGraphics
import Foundation
import IOKit

struct DisplayTransportDiagnostic: Codable, Hashable {
    var serviceLocation: Int
    var edidUUID: String
    var manufacturerID: String
    var productName: String
    var serialNumber: Int64
    var alphanumericSerialNumber: String
    var ioDisplayLocation: String
    var dcpLocation: String
    var transportUpstream: String
    var transportDownstream: String
    var hasExternalAVService: Bool
    var matchScore: Int

    var summary: String {
        let service = hasExternalAVService ? "external-av" : "no-external-av"
        let transport = [transportUpstream, transportDownstream].filter { !$0.isEmpty }.joined(separator: " -> ")
        let transportText = transport.isEmpty ? "-" : transport
        return "score=\(matchScore) service=\(service) location=\(dcpLocation.isEmpty ? "-" : dcpLocation) transport=\(transportText) product=\(productName.isEmpty ? "-" : productName) serial=\(alphanumericSerialNumber.isEmpty ? serialText : alphanumericSerialNumber)"
    }

    private var serialText: String {
        serialNumber == 0 ? "-" : "\(serialNumber)"
    }
}

struct DisplayTransportDiagnosticsService {
    func diagnostics(for display: DisplayDevice) -> [DisplayTransportDiagnostic] {
        enumerateIORegistry().map { entry in
            var diagnostic = entry
            diagnostic.matchScore = matchScore(display: display, entry: entry)
            return diagnostic
        }
        .sorted { lhs, rhs in
            if lhs.matchScore != rhs.matchScore { return lhs.matchScore > rhs.matchScore }
            if lhs.hasExternalAVService != rhs.hasExternalAVService { return lhs.hasExternalAVService && !rhs.hasExternalAVService }
            return lhs.serviceLocation < rhs.serviceLocation
        }
    }

    private func enumerateIORegistry() -> [DisplayTransportDiagnostic] {
        var results: [DisplayTransportDiagnostic] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            "IOService",
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        let framebufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]
        let proxyName = "DCPAVServiceProxy"
        var pending = emptyDiagnostic(serviceLocation: 0)
        var serviceLocation = 0

        while let next = nextEntry(namedLike: framebufferNames + [proxyName], iterator: &iterator) {
            defer { IOObjectRelease(next.entry) }

            if framebufferNames.contains(where: { next.name.contains($0) }) {
                serviceLocation += 1
                pending = framebufferProperties(entry: next.entry, serviceLocation: serviceLocation)
            } else if next.name.contains(proxyName) {
                attachAVServiceProperties(entry: next.entry, into: &pending)
                results.append(pending)
            }
        }

        return results
    }

    private func emptyDiagnostic(serviceLocation: Int) -> DisplayTransportDiagnostic {
        DisplayTransportDiagnostic(
            serviceLocation: serviceLocation,
            edidUUID: "",
            manufacturerID: "",
            productName: "",
            serialNumber: 0,
            alphanumericSerialNumber: "",
            ioDisplayLocation: "",
            dcpLocation: "",
            transportUpstream: "",
            transportDownstream: "",
            hasExternalAVService: false,
            matchScore: 0
        )
    }

    private func nextEntry(
        namedLike interests: [String],
        iterator: inout io_iterator_t
    ) -> (name: String, entry: io_service_t)? {
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { nameBuffer.deallocate() }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { return nil }
            guard IORegistryEntryGetName(entry, nameBuffer) == KERN_SUCCESS else {
                IOObjectRelease(entry)
                continue
            }

            let name = String(cString: nameBuffer)
            if interests.contains(where: { name.contains($0) }) {
                return (name, entry)
            }
            IOObjectRelease(entry)
        }
    }

    private func framebufferProperties(entry: io_service_t, serviceLocation: Int) -> DisplayTransportDiagnostic {
        var diagnostic = emptyDiagnostic(serviceLocation: serviceLocation)
        diagnostic.edidUUID = stringProperty("EDID UUID", from: entry)
        diagnostic.ioDisplayLocation = registryPath(for: entry)

        if let displayAttributes = dictionaryProperty("DisplayAttributes", from: entry),
           let productAttributes = displayAttributes["ProductAttributes"] as? NSDictionary {
            diagnostic.manufacturerID = productAttributes["ManufacturerID"] as? String ?? ""
            diagnostic.productName = productAttributes["ProductName"] as? String ?? ""
            diagnostic.serialNumber = productAttributes["SerialNumber"] as? Int64 ?? 0
            diagnostic.alphanumericSerialNumber = productAttributes["AlphanumericSerialNumber"] as? String ?? ""
        }

        if let transport = dictionaryProperty("Transport", from: entry) {
            diagnostic.transportUpstream = transport["Upstream"] as? String ?? ""
            diagnostic.transportDownstream = transport["Downstream"] as? String ?? ""
        }

        return diagnostic
    }

    private func attachAVServiceProperties(entry: io_service_t, into diagnostic: inout DisplayTransportDiagnostic) {
        diagnostic.dcpLocation = stringProperty("Location", from: entry)
        diagnostic.hasExternalAVService = diagnostic.dcpLocation == "External"
    }

    private func stringProperty(_ key: String, from entry: io_service_t) -> String {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return ""
        }
        return unmanaged.takeRetainedValue() as? String ?? ""
    }

    private func dictionaryProperty(_ key: String, from entry: io_service_t) -> NSDictionary? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? NSDictionary
    }

    private func registryPath(for entry: io_service_t) -> String {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_string_t>.size)
        defer { pathBuffer.deallocate() }
        guard IORegistryEntryGetPath(entry, kIOServicePlane, pathBuffer) == KERN_SUCCESS else {
            return ""
        }
        return String(cString: pathBuffer)
    }

    private func matchScore(display: DisplayDevice, entry: DisplayTransportDiagnostic) -> Int {
        var score = 0
        let edid = entry.edidUUID.uppercased()
        let keys = edidSearchKeys(for: display)

        for key in keys where key.value != "0000" {
            guard edid.count >= key.offset + key.value.count else { continue }
            let start = edid.index(edid.startIndex, offsetBy: key.offset)
            let end = edid.index(start, offsetBy: key.value.count)
            if String(edid[start..<end]) == key.value {
                score += 1
            }
        }

        if !entry.productName.isEmpty,
           let productName = display.metadata.productName,
           productName.localizedCaseInsensitiveCompare(entry.productName) == .orderedSame {
            score += 1
        }

        if entry.serialNumber != 0, UInt32(clamping: entry.serialNumber) == display.serialNumber {
            score += 1
        }

        if !entry.ioDisplayLocation.isEmpty {
            score += entry.hasExternalAVService ? 2 : 1
        }

        return min(score, 20)
    }

    private func edidSearchKeys(for display: DisplayDevice) -> [(value: String, offset: Int)] {
        var keys: [(value: String, offset: Int)] = [
            (String(format: "%04X", UInt16(clamping: display.vendorID)), 0),
            (String(
                format: "%02X%02X",
                UInt8(UInt16(clamping: display.modelID) & 0xFF),
                UInt8((UInt16(clamping: display.modelID) >> 8) & 0xFF)
            ), 4)
        ]

        if let week = display.metadata.manufactureWeek,
           let year = display.metadata.manufactureYear,
           year >= 1990 {
            keys.append((
                String(format: "%02X%02X", UInt8(clamping: week), UInt8(clamping: year - 1990)),
                19
            ))
        }

        if display.metadata.physicalWidthMM > 0, display.metadata.physicalHeightMM > 0 {
            keys.append((
                String(
                    format: "%02X%02X",
                    UInt8(clamping: Int(display.metadata.physicalWidthMM / 10)),
                    UInt8(clamping: Int(display.metadata.physicalHeightMM / 10))
                ),
                30
            ))
        }

        return keys
    }
}
