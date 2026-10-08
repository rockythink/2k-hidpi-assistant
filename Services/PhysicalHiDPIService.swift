import CryptoKit
import Darwin
import Foundation

struct PhysicalHiDPIService {
    struct Paths {
        let overrides: URL
        let systemOverrides: URL
        let state: URL
        let boundary: URL
        let owner: uid_t
        let authorize: Bool

        static let production = Paths(
            overrides: URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides"),
            systemOverrides: URL(fileURLWithPath: "/System/Library/Displays/Contents/Resources/Overrides"),
            state: URL(fileURLWithPath: "/Library/Application Support/HiDPIBuddy"),
            boundary: URL(fileURLWithPath: "/"), owner: 0, authorize: true)
    }

    private struct Receipt: Codable {
        let version: Int
        let key: DisplayOverrideKey
        let target: DisplayResolutionTarget
        let nativeResolution: DisplayResolutionTarget
        // nil means there was no application override, not an empty original file.
        let originalData: Data?
        let originalDigest: String
        let installedDigest: String
    }

    private let paths: Paths
    init() { paths = .production }
    /// Tests use a private sandbox boundary and getuid(), never administrator authorization.
    init(testPaths: Paths) { paths = testPaths }

    func status(for key: DisplayOverrideKey) throws -> PhysicalHiDPIStatus {
        do {
            let current = try safeData(at: productURL(key))
            guard let bytes = try safeData(at: receiptURL(key)) else { return PhysicalHiDPIStatus() }
            let receipt = try JSONDecoder().decode(Receipt.self, from: bytes)
            try validate(receipt, key: key)
            let digest = Self.digest(current)
            if digest == receipt.installedDigest {
                return PhysicalHiDPIStatus(phase: .installed, target: receipt.target,
                                          nativeResolution: receipt.nativeResolution)
            }
            if digest == receipt.originalDigest {
                return PhysicalHiDPIStatus(phase: .restored, target: receipt.target,
                                          nativeResolution: receipt.nativeResolution)
            }
            return PhysicalHiDPIStatus(phase: .conflict, target: receipt.target,
                                      nativeResolution: receipt.nativeResolution,
                                      problem: "本产品覆盖文件已被其他程序更改，拒绝覆盖或恢复。")
        } catch {
            return PhysicalHiDPIStatus(phase: .conflict, problem: error.localizedDescription)
        }
    }

    func prepare(for display: DisplayDevice, target: DisplayResolutionTarget) throws -> PhysicalHiDPIPlan {
        guard !display.isBuiltin, let nativeMode = display.nativeMode else {
            throw PhysicalHiDPIError(message: "仅支持具有已知原生分辨率的外接物理显示器。")
        }
        let key = DisplayOverrideKey(display: display)
        let currentStatus = try status(for: key)
        guard currentStatus.phase == .notInstalled || currentStatus.phase == .restored else {
            throw PhysicalHiDPIError(message: currentStatus.problem ?? "请先恢复现有自定义配置，再安装新的配置。")
        }
        let native = DisplayResolutionTarget(width: nativeMode.pixelWidth, height: nativeMode.pixelHeight)
        let original = try safeData(at: productURL(key))
        // /System is a read-only template. Its existence is never recorded as a /Library original.
        let template = try original ?? safeData(at: paths.systemOverrides
            .appendingPathComponent(key.vendorDirectory).appendingPathComponent(key.productFile))
        return PhysicalHiDPIPlan(key: key, target: target, nativeResolution: native,
                                 expectedInstalledData: original,
                                 generatedData: try PhysicalHiDPIConfiguration.generate(
                                    existing: template, key: key, target: target, native: native))
    }

    func install(_ plan: PhysicalHiDPIPlan) async throws {
        // Revalidate the public plan before constructing a privileged transaction.
        let validatedData = try PhysicalHiDPIConfiguration.generate(existing: plan.generatedData, key: plan.key,
                                                                    target: plan.target, native: plan.nativeResolution)
        guard validatedData == plan.generatedData, plan.generatedData != plan.expectedInstalledData else {
            throw PhysicalHiDPIError(message: "配置计划缺少目标模式、格式不一致，或与原配置相同。")
        }
        let receipt = Receipt(version: 1, key: plan.key, target: plan.target,
                              nativeResolution: plan.nativeResolution, originalData: plan.expectedInstalledData,
                              originalDigest: Self.digest(plan.expectedInstalledData),
                              installedDigest: Self.digest(plan.generatedData))
        try await transact(operation: "install", key: plan.key,
                           payload: plan.generatedData, receipt: JSONEncoder().encode(receipt))
    }

    func restore(for key: DisplayOverrideKey) async throws {
        try await transact(operation: "restore", key: key, payload: Data(), receipt: Data())
    }

    private func validate(_ receipt: Receipt, key: DisplayOverrideKey) throws {
        guard receipt.version == 1, receipt.key == key,
              receipt.originalDigest == Self.digest(receipt.originalData),
              receipt.installedDigest.count == 64,
              receipt.installedDigest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw PhysicalHiDPIError(message: "备份收据损坏或与本产品不匹配。")
        }
        try PhysicalHiDPIConfiguration.validate(target: receipt.target, native: receipt.nativeResolution)
    }

    private func productURL(_ key: DisplayOverrideKey) -> URL {
        paths.overrides.appendingPathComponent(key.vendorDirectory).appendingPathComponent(key.productFile)
    }
    private func receiptURL(_ key: DisplayOverrideKey) -> URL {
        paths.state.appendingPathComponent(key.vendorDirectory + "-" + key.productFile + ".json")
    }
    private static func digest(_ data: Data?) -> String {
        guard let data else { return "absent" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// No-follow reads and checks mirror the privileged writer. No status requires root.
    private func safeData(at url: URL) throws -> Data? {
        let path = url.path
        let boundary = paths.boundary.path
        guard boundary == "/" || path.hasPrefix(boundary + "/") else {
            throw PhysicalHiDPIError(message: "路径不在安全边界内。")
        }
        var components = [String]()
        var cursor = url
        while cursor.path != boundary {
            components.append(cursor.path)
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { throw PhysicalHiDPIError(message: "无效安全边界。") }
            cursor = parent
        }
        components.append(boundary)
        for component in components.reversed() {
            var info = stat()
            if lstat(component, &info) != 0 {
                if errno == ENOENT { return nil }
                throw PhysicalHiDPIError(message: "无法读取安全路径：\(component)")
            }
            let isFile = component == path
            guard info.st_uid == paths.owner, info.st_mode & 0o022 == 0,
                  info.st_mode & S_IFMT == (isFile ? S_IFREG : S_IFDIR),
                  !isFile || info.st_nlink == 1 else {
                throw PhysicalHiDPIError(message: "拒绝不安全路径（所有者、写权限、链接或文件类型）：\(component)")
            }
            try Self.checkACL(component)
        }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PhysicalHiDPIError(message: "无法安全打开覆盖文件。") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == paths.owner,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_mode & 0o022 == 0,
              info.st_size <= 16 * 1024 * 1024 else {
            throw PhysicalHiDPIError(message: "覆盖文件不安全或超过 16MB。")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try handle.readToEnd() ?? Data()
    }

    private static func checkACL(_ path: String) throws {
        guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return } // macOS reports no extended ACL as ENOENT.
            throw PhysicalHiDPIError(message: "无法检查路径 ACL：\(path)")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard let text = acl_to_text(acl, nil) else {
            throw PhysicalHiDPIError(message: "无法读取路径 ACL：\(path)")
        }
        defer { acl_free(text) }
        // Standard /Library everyone-deny-delete ACL is safe; fail closed on grants.
        if String(cString: text).components(separatedBy: .newlines).contains(where: { $0.contains("allow") }) {
            throw PhysicalHiDPIError(message: "拒绝包含权限授予的路径 ACL：\(path)")
        }
    }

    private func transact(operation: String, key: DisplayOverrideKey, payload: Data, receipt: Data) async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ruby") else {
            throw PhysicalHiDPIError(message: "缺少可执行的系统 /usr/bin/ruby，无法安全安装或恢复配置；尚未请求管理员授权。不会使用 Homebrew、PATH 查找或自动安装替代运行时。")
        }
        let input: [String: Any] = ["operation": operation, "overrides": paths.overrides.path,
                                  "state": paths.state.path, "boundary": paths.boundary.path,
                                  "owner": paths.owner, "vendor": key.vendorDirectory,
                                  "product": key.productFile, "payload": payload.base64EncodedString(),
                                  "receipt": receipt.base64EncodedString()]
        let encoded = try JSONSerialization.data(withJSONObject: input).base64EncodedString()
        let command = "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C /usr/bin/ruby --disable=gems -e "
            + Self.shellQuote(Self.transactionScript) + " -- " + Self.shellQuote(encoded)
        if paths.authorize {
            // One OS authorization dialog; the user enters their password into macOS, never the app.
            let appleScript = "do shell script " + Self.appleScriptQuote(command) + " with administrator privileges"
            try await Self.run(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
        } else {
            try await Self.run(executable: "/bin/sh", arguments: ["-c", command])
        }
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func appleScriptQuote(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func run(executable: String, arguments: [String]) async throws {
        // Drain both pipes concurrently before waiting; all blocking work is off the main actor.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let out = Pipe()
                let err = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                    let group = DispatchGroup()
                    let errorBytes = ProcessOutput()
                    group.enter()
                    DispatchQueue.global().async {
                        errorBytes.set(err.fileHandleForReading.readDataToEndOfFile())
                        group.leave()
                    }
                    _ = out.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    group.wait()
                    guard process.terminationStatus == 0 else {
                        throw PhysicalHiDPIError(message: String(data: errorBytes.data, encoding: .utf8)
                                                ?? "物理显示器配置事务失败。")
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private final class ProcessOutput: @unchecked Sendable {
        // DispatchGroup provides the handoff; there is one writer and a post-wait reader.
        private(set) var data = Data()
        func set(_ data: Data) { self.data = data }
    }

    /// Independent implementation. Only Apple-provided binaries execute; no downloaded scripts/helper.
    /// The same inline transaction runs in tests, with only paths and expected owner injected.
    static let transactionScript = #"""
require 'json'
require 'base64'
require 'digest'
require 'securerandom'
File.umask(0022) # Public-readable permissions must not depend on the caller umask.
a = JSON.parse(Base64.strict_decode64(ARGV.fetch(0)))
owner = Integer(a.fetch('owner'))
raise 'wrong transaction owner' unless Process.uid == owner
boundary = a.fetch('boundary')
raise 'invalid boundary' unless boundary.start_with?('/') && File.expand_path(boundary) == boundary
safe = lambda do |path, kind|
  raise 'outside safe boundary' unless boundary == '/' || path.start_with?(boundary + '/') || path == boundary
  parts = []
  cursor = path
  loop do
    parts << cursor
    break if cursor == boundary
    parent = File.dirname(cursor)
    raise 'invalid path boundary' if parent == cursor
    cursor = parent
  end
  parts.reverse_each do |p|
    begin
      s = File.lstat(p)
    rescue Errno::ENOENT
      return false
    end
    file = p == path && kind == :file
    raise "unsafe path: #{p}" unless s.uid == owner && (s.mode & 0022) == 0 &&
      (file ? s.file? && s.nlink == 1 && s.size <= 16 * 1024 * 1024 : s.directory?)
    acl = IO.popen(['/bin/ls', '-lde', p], err: [:child, :out], &:read)
    raise "unreadable ACL: #{p}" unless $?.success?
    raise "unsafe ACL: #{p}" if acl.lines.drop(1).any? { |line| line.include?(' allow ') }
  end
  true
end
ensure_dir = lambda do |path|
  unless safe.call(path, :dir)
    ensure_dir.call(File.dirname(path))
    begin
      Dir.mkdir(path, 0755)
    rescue Errno::EEXIST
    end
    raise 'unsafe created directory' unless safe.call(path, :dir)
  end
end
read = lambda do |path|
  next nil unless safe.call(path, :file)
  File.open(path, File::RDONLY | File::NOFOLLOW) do |f|
    s = f.stat
    raise 'unsafe opened file' unless s.file? && s.nlink == 1 && s.uid == owner && (s.mode & 0022) == 0
    f.read
  end
end
digest = lambda { |bytes| bytes.nil? ? 'absent' : Digest::SHA256.hexdigest(bytes) }
state = a.fetch('state')
overrides = a.fetch('overrides')
vendor = a.fetch('vendor')
product = a.fetch('product')
raise 'invalid product key' unless vendor.match?(/\ADisplayVendorID-[0-9a-f]+\z/) && product.match?(/\ADisplayProductID-[0-9a-f]+\z/)
ensure_dir.call(state)
lock_path = File.join(state, 'transaction.lock')
if !safe.call(lock_path, :file)
  begin
    File.open(lock_path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0644) { |f| f.fsync }
  rescue Errno::EEXIST
  end
end
raise 'unsafe lock' unless safe.call(lock_path, :file)
File.open(lock_path, File::RDWR | File::NOFOLLOW) do |lock|
  raise 'unsafe lock descriptor' unless lock.stat.nlink == 1 && lock.stat.uid == owner
  lock.flock(File::LOCK_EX) # Kernel releases automatically on interruption, including SIGKILL.
  raise 'lock replaced' unless File.lstat(lock_path).ino == lock.stat.ino
  path = File.join(overrides, vendor, product)
  receipt_path = File.join(state, vendor + '-' + product + '.json')
  current = read.call(path)
  old_bytes = read.call(receipt_path)
  decode_receipt = lambda do |bytes|
    r = JSON.parse(bytes)
    original = r['originalData'].nil? ? nil : Base64.strict_decode64(r['originalData'])
    raise 'invalid receipt' unless r['version'] == 1 &&
      r.fetch('key').fetch('vendorID').to_s(16) == vendor.sub('DisplayVendorID-', '') &&
      r.fetch('key').fetch('productID').to_s(16) == product.sub('DisplayProductID-', '') &&
      r['originalDigest'] == digest.call(original) && r.fetch('installedDigest').match?(/\A[0-9a-f]{64}\z/)
    [r, original]
  end
  atomic = lambda do |destination, bytes, expected_digest|
    ensure_dir.call(File.dirname(destination))
    safe.call(destination, :file)
    temp = File.join(File.dirname(destination), '.hidpibuddy-' + SecureRandom.hex(16))
    begin
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0644) do |f|
        f.write(bytes)
        f.flush
        f.fsync
      end
      raise "configuration changed before atomic commit" unless digest.call(read.call(destination)) == expected_digest
      File.rename(temp, destination)
      File.open(File.dirname(destination), File::RDONLY) { |dir| dir.fsync }
    ensure
      File.unlink(temp) if File.exist?(temp)
    end
  end
  if a.fetch('operation') == 'install'
    receipt_bytes = Base64.strict_decode64(a.fetch('receipt'))
    r, original = decode_receipt.call(receipt_bytes)
    payload = Base64.strict_decode64(a.fetch('payload'))
    raise 'invalid installation payload' unless digest.call(payload) == r['installedDigest']
    raise 'original changed since preparation' unless digest.call(current) == r['originalDigest']
    if old_bytes
      old, _ = decode_receipt.call(old_bytes)
      raise 'existing installation must be restored first' unless digest.call(current) == old['originalDigest']
    end
    # This single receipt is also the exact-byte backup. Commit it durably BEFORE product mutation.
    atomic.call(receipt_path, receipt_bytes, digest.call(old_bytes))
    atomic.call(path, payload, r['originalDigest'])
  elsif a.fetch('operation') == 'restore'
    raise 'no safe backup receipt' unless old_bytes
    r, original = decode_receipt.call(old_bytes)
    current_digest = digest.call(current)
    # Idempotent after interruption or a completed restore.
    next if current_digest == r['originalDigest']
    raise 'installed configuration changed; refusing restore' unless current_digest == r['installedDigest']
    if original
      atomic.call(path, original, r['installedDigest'])
    else
      raise 'installed configuration changed before deletion' unless digest.call(read.call(path)) == r['installedDigest']
      File.unlink(path) # Never remove vendor/Overrides directories or sibling products.
      File.open(File.dirname(path), File::RDONLY) { |dir| dir.fsync }
    end
  else
    raise 'invalid operation'
  end
end
"""#
}
