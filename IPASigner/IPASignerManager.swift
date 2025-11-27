import Foundation
import SwiftUI
import UniformTypeIdentifiers

class IPASignerManager: ObservableObject {
    @Published var ipaPath: String = "" {
        didSet { UserDefaults.standard.set(ipaPath, forKey: "lastIPAPath") }
    }
    @Published var profilePath: String = "" {
        didSet { UserDefaults.standard.set(profilePath, forKey: "lastProfilePath") }
    }
    @Published var outputDirectory: String = "" {
        didSet { UserDefaults.standard.set(outputDirectory, forKey: "lastOutputDirectory") }
    }
    @Published var selectedCertificate: String = "" {
        didSet { UserDefaults.standard.set(selectedCertificate, forKey: "lastCertificate") }
    }
    
    // Load saved settings
    init() {
        self.outputDirectory = UserDefaults.standard.string(forKey: "lastOutputDirectory") ?? ""
        self.selectedCertificate = UserDefaults.standard.string(forKey: "lastCertificate") ?? ""
        // Don't restore file paths as they may not exist anymore
    }
    @Published var certificates: [String] = []
    @Published var isSigning: Bool = false
    @Published var logOutput: String = ""
    @Published var showSuccess: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var outputPath: String?
    @Published var showImportSuccess: Bool = false
    @Published var importMessage: String = ""
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var selectedDevice: String = ""
    @Published var isInstalling: Bool = false
    @Published var showInstallSuccess: Bool = false
    @Published var installMessage: String = ""
    @Published var hasInstallTool: Bool = false
    @Published var isInstallingTool: Bool = false
    
    private let fileManager = FileManager.default
    
    // MARK: - Device Info
    struct DeviceInfo: Identifiable, Hashable {
        let id: String  // UDID
        let name: String
    }
    
    // MARK: - Import Certificate
    func importCertificate() {
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.init(filenameExtension: "cer")!, .init(filenameExtension: "p12")!]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "选择证书文件 (.cer 或 .p12)"
            panel.prompt = "导入"
            
            if panel.runModal() == .OK, let url = panel.url {
                self?.performImportCertificate(from: url)
            }
        }
    }
    
    private func performImportCertificate(from url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                if fileExtension == "cer" {
                    // Import .cer file using security command
                    try self?.runCommand("/usr/bin/security", arguments: ["add-certificates", url.path])
                    
                    DispatchQueue.main.async {
                        self?.importMessage = "证书导入成功！\n\n请注意：.cer 证书需要配合对应的私钥才能用于签名。如果这是新下载的证书，请确保之前已在此电脑上创建过 CSR 请求。"
                        self?.showImportSuccess = true
                        self?.loadCertificates()
                    }
                } else if fileExtension == "p12" {
                    // For .p12 files, we need to use Keychain Access or prompt for password
                    // Open with default app (Keychain Access)
                    NSWorkspace.shared.open(url)
                    
                    DispatchQueue.main.async {
                        self?.importMessage = "已打开钥匙串访问来导入 .p12 证书。\n\n请在弹出的窗口中输入证书密码完成导入，然后点击刷新按钮更新证书列表。"
                        self?.showImportSuccess = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "证书导入失败: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }
    
    // MARK: - Load Certificates
    func loadCertificates() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let certs = self?.getSigningCertificates() ?? []
            DispatchQueue.main.async {
                self?.certificates = certs
            }
        }
    }
    
    private func getSigningCertificates() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-v", "-p", "codesigning"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse certificate names
            var certs: [String] = []
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                if let range = line.range(of: "\".*\"", options: .regularExpression) {
                    var cert = String(line[range])
                    cert = cert.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !cert.isEmpty && !certs.contains(cert) {
                        certs.append(cert)
                    }
                }
            }
            return certs
        } catch {
            return []
        }
    }
    
    // MARK: - Sign IPA
    func signIPA() {
        guard !ipaPath.isEmpty, !profilePath.isEmpty, !selectedCertificate.isEmpty else {
            return
        }
        
        isSigning = true
        logOutput = ""
        outputPath = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performSigning()
        }
    }
    
    private func performSigning() {
        log("🚀 开始签名流程...")
        
        // Create temp directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            log("📁 创建临时目录: \(tempDir.path)")
            
            // 1. Unzip IPA
            let ipaSize = (try? fileManager.attributesOfItem(atPath: ipaPath)[.size] as? Int) ?? 0
            let ipaSizeMB = Double(ipaSize) / 1024.0 / 1024.0
            log("📦 解压 IPA 文件 (\(String(format: "%.1f", ipaSizeMB)) MB)，请稍候...")
            try runCommandWithOutput("/usr/bin/unzip", arguments: ["-o", "-q", ipaPath, "-d", tempDir.path])
            log("✅ 解压完成")
            
            // Find .app directory
            let payloadDir = tempDir.appendingPathComponent("Payload")
            guard let appDir = try findAppDirectory(in: payloadDir) else {
                throw SigningError.appNotFound
            }
            log("✅ 找到应用: \(appDir.lastPathComponent)")
            
            // 2. Remove old signature
            log("🗑️ 移除旧签名...")
            let codeSignDir = appDir.appendingPathComponent("_CodeSignature")
            if fileManager.fileExists(atPath: codeSignDir.path) {
                try fileManager.removeItem(at: codeSignDir)
            }
            
            // Remove PlugIns signatures
            let pluginsDir = appDir.appendingPathComponent("PlugIns")
            if fileManager.fileExists(atPath: pluginsDir.path) {
                let pluginContents = try fileManager.contentsOfDirectory(atPath: pluginsDir.path)
                for item in pluginContents {
                    let itemPath = pluginsDir.appendingPathComponent(item).appendingPathComponent("_CodeSignature")
                    if fileManager.fileExists(atPath: itemPath.path) {
                        try fileManager.removeItem(at: itemPath)
                    }
                }
            }
            
            // 3. Copy provisioning profile
            log("📋 复制 Provisioning Profile...")
            let embeddedProfile = appDir.appendingPathComponent("embedded.mobileprovision")
            if fileManager.fileExists(atPath: embeddedProfile.path) {
                try fileManager.removeItem(at: embeddedProfile)
            }
            try fileManager.copyItem(atPath: profilePath, toPath: embeddedProfile.path)
            
            // Copy to PlugIns
            if fileManager.fileExists(atPath: pluginsDir.path) {
                let pluginContents = try fileManager.contentsOfDirectory(atPath: pluginsDir.path)
                for item in pluginContents where item.hasSuffix(".appex") {
                    let pluginProfile = pluginsDir.appendingPathComponent(item).appendingPathComponent("embedded.mobileprovision")
                    if fileManager.fileExists(atPath: pluginProfile.path) {
                        try fileManager.removeItem(at: pluginProfile)
                    }
                    try fileManager.copyItem(atPath: profilePath, toPath: pluginProfile.path)
                }
            }
            
            // 4. Extract entitlements
            log("🔐 提取 Entitlements...")
            let profilePlist = tempDir.appendingPathComponent("profile.plist")
            let entitlementsPlist = tempDir.appendingPathComponent("entitlements.plist")
            
            try runCommand("/usr/bin/security", arguments: ["cms", "-D", "-i", profilePath, "-o", profilePlist.path])
            try extractEntitlements(from: profilePlist, to: entitlementsPlist)
            
            // 5. Sign Frameworks
            let frameworksDir = appDir.appendingPathComponent("Frameworks")
            if fileManager.fileExists(atPath: frameworksDir.path) {
                log("📚 签名 Frameworks...")
                let frameworkContents = try fileManager.contentsOfDirectory(atPath: frameworksDir.path)
                for item in frameworkContents {
                    let itemPath = frameworksDir.appendingPathComponent(item)
                    try runCommand("/usr/bin/codesign", arguments: ["-f", "-s", selectedCertificate, itemPath.path])
                }
                log("✅ Frameworks 签名完成")
            }
            
            // 6. Sign PlugIns
            if fileManager.fileExists(atPath: pluginsDir.path) {
                log("🔌 签名 PlugIns...")
                let pluginContents = try fileManager.contentsOfDirectory(atPath: pluginsDir.path)
                for item in pluginContents where item.hasSuffix(".appex") {
                    let itemPath = pluginsDir.appendingPathComponent(item)
                    try runCommand("/usr/bin/codesign", arguments: ["-f", "-s", selectedCertificate, "--entitlements", entitlementsPlist.path, itemPath.path])
                }
                log("✅ PlugIns 签名完成")
            }
            
            // 7. Sign main app
            log("📱 签名主应用...")
            try runCommand("/usr/bin/codesign", arguments: ["-f", "-s", selectedCertificate, "--entitlements", entitlementsPlist.path, appDir.path])
            log("✅ 主应用签名完成")
            
            // 8. Repackage IPA
            log("📦 重新打包 IPA，请稍候...")
            let ipaURL = URL(fileURLWithPath: ipaPath)
            let outputName = ipaURL.deletingPathExtension().lastPathComponent + "-signed.ipa"
            let outputDir = outputDirectory.isEmpty ? ipaURL.deletingLastPathComponent() : URL(fileURLWithPath: outputDirectory)
            let outputURL = outputDir.appendingPathComponent(outputName)
            
            // Remove existing output file
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
            
            try runCommandWithOutput("/usr/bin/zip", arguments: ["-r", "-q", outputURL.path, "Payload"], currentDirectory: tempDir.path)
            
            // 9. Cleanup
            log("🧹 清理临时文件...")
            try fileManager.removeItem(at: tempDir)
            
            log("🎉 签名完成!")
            log("📍 输出文件: \(outputURL.path)")
            
            DispatchQueue.main.async { [weak self] in
                self?.outputPath = outputURL.path
                self?.isSigning = false
                self?.showSuccess = true
            }
            
        } catch {
            log("❌ 错误: \(error.localizedDescription)")
            
            // Cleanup on error
            try? fileManager.removeItem(at: tempDir)
            
            DispatchQueue.main.async { [weak self] in
                self?.isSigning = false
                self?.errorMessage = error.localizedDescription
                self?.showError = true
            }
        }
    }
    
    // MARK: - Helper Methods
    private func findAppDirectory(in payloadDir: URL) throws -> URL? {
        let contents = try fileManager.contentsOfDirectory(atPath: payloadDir.path)
        for item in contents where item.hasSuffix(".app") {
            return payloadDir.appendingPathComponent(item)
        }
        return nil
    }
    
    private func runCommand(_ command: String, arguments: [String], currentDirectory: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SigningError.commandFailed(output)
        }
    }
    
    private func extractEntitlements(from profilePlist: URL, to entitlementsPlist: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        process.arguments = ["-x", "-c", "Print :Entitlements", profilePlist.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try data.write(to: entitlementsPlist)
        } else {
            throw SigningError.commandFailed("无法提取 Entitlements")
        }
    }
    
    private func runCommandWithOutput(_ command: String, arguments: [String], currentDirectory: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        // Use /dev/null to avoid blocking on large output
        let nullDevice = FileHandle.nullDevice
        process.standardOutput = nullDevice
        process.standardError = nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SigningError.commandFailed("命令执行失败，退出码: \(process.terminationStatus)")
        }
    }
    
    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logOutput += message + "\n"
        }
    }
    
    // MARK: - Xcode Integration
    func openXcodeDevices() {
        // Open Xcode Devices and Simulators window
        let script = """
        tell application "Xcode"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Xcode"
                click menu item "Devices and Simulators" of menu "Window" of menu bar 1
            end tell
        end tell
        """
        
        // Try using open command first
        if let url = URL(string: "x-xcode-debug-device-list://") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback to AppleScript
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
        
        // Show the signed IPA in Finder for easy drag-and-drop
        if let path = outputPath {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
    
    // MARK: - Install Tool Check
    func checkInstallTool() {
        hasInstallTool = getInstallerPath() != nil
    }
    
    private func getInstallerPath() -> String? {
        let paths = [
            "/usr/local/bin/ideviceinstaller",
            "/opt/homebrew/bin/ideviceinstaller"
        ]
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    func installDeviceTool() {
        isInstallingTool = true
        log("📥 正在安装 ideviceinstaller...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            
            // Find brew path
            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            var brewPath: String?
            for path in brewPaths {
                if FileManager.default.fileExists(atPath: path) {
                    brewPath = path
                    break
                }
            }
            
            guard let brew = brewPath else {
                DispatchQueue.main.async {
                    self?.isInstallingTool = false
                    self?.errorMessage = "未找到 Homebrew。请先安装 Homebrew：\n\n/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    self?.showError = true
                    self?.log("❌ 未找到 Homebrew")
                }
                return
            }
            
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["install", "ideviceinstaller"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self?.isInstallingTool = false
                    if process.terminationStatus == 0 {
                        self?.hasInstallTool = true
                        self?.log("✅ ideviceinstaller 安装成功!")
                        self?.refreshDevices()
                    } else {
                        self?.errorMessage = "安装失败，请在终端手动运行：\nbrew install ideviceinstaller"
                        self?.showError = true
                        self?.log("❌ 安装失败")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isInstallingTool = false
                    self?.errorMessage = "安装失败: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }
    
    // MARK: - Device Management
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = self?.getConnectedDevices() ?? []
            DispatchQueue.main.async {
                self?.connectedDevices = devices
                if devices.count == 1 {
                    self?.selectedDevice = devices[0].id
                }
            }
        }
    }
    
    private func getConnectedDevices() -> [DeviceInfo] {
        // Try using idevice_id first (from libimobiledevice)
        if let devices = getDevicesUsingIdevice() {
            return devices
        }
        
        // Fallback to system_profiler
        return getDevicesUsingSystemProfiler()
    }
    
    private func getDevicesUsingIdevice() -> [DeviceInfo]? {
        // Find idevice_id path
        let ideviceIdPaths = ["/opt/homebrew/bin/idevice_id", "/usr/local/bin/idevice_id"]
        var ideviceIdPath: String?
        for path in ideviceIdPaths {
            if fileManager.fileExists(atPath: path) {
                ideviceIdPath = path
                break
            }
        }
        
        guard let idPath = ideviceIdPath else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: idPath)
        process.arguments = ["-l"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let udids = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                
                var devices: [DeviceInfo] = []
                for udid in udids {
                    let name = getDeviceName(udid: udid) ?? "iOS Device"
                    devices.append(DeviceInfo(id: udid, name: name))
                }
                return devices.isEmpty ? nil : devices
            }
        } catch {
            // idevice_id not available
        }
        return nil
    }
    
    private func getDeviceName(udid: String) -> String? {
        // Find idevicename path
        let paths = ["/opt/homebrew/bin/idevicename", "/usr/local/bin/idevicename"]
        var toolPath: String?
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                toolPath = path
                break
            }
        }
        
        guard let namePath = toolPath else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: namePath)
        process.arguments = ["-u", udid]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return name?.isEmpty == false ? name : nil
            }
        } catch {}
        return nil
    }
    
    private func getDevicesUsingSystemProfiler() -> [DeviceInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPUSBDataType", "-json"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let spusb = json["SPUSBDataType"] as? [[String: Any]] {
                return findIOSDevices(in: spusb)
            }
        } catch {}
        return []
    }
    
    private func findIOSDevices(in items: [[String: Any]]) -> [DeviceInfo] {
        var devices: [DeviceInfo] = []
        
        for item in items {
            if let name = item["_name"] as? String,
               let serialNum = item["serial_num"] as? String,
               (name.contains("iPhone") || name.contains("iPad") || name.contains("iPod")) {
                devices.append(DeviceInfo(id: serialNum, name: name))
            }
            
            if let subItems = item["_items"] as? [[String: Any]] {
                devices.append(contentsOf: findIOSDevices(in: subItems))
            }
        }
        
        return devices
    }
    
    // MARK: - Install to Device
    func installToDevice() {
        guard let ipaPath = outputPath, !selectedDevice.isEmpty else {
            errorMessage = "请先签名 IPA 并选择设备"
            showError = true
            return
        }
        
        isInstalling = true
        log("📲 开始安装到设备...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performInstall(ipaPath: ipaPath)
        }
    }
    
    private func performInstall(ipaPath: String) {
        // Use shell to run ideviceinstaller (handles PATH correctly)
        log("📦 使用 ideviceinstaller 安装...")
        
        let shellCommand = "ideviceinstaller -u '\(selectedDevice)' -i '\(ipaPath)'"
        
        do {
            try runShellCommand(shellCommand)
            
            DispatchQueue.main.async { [weak self] in
                self?.isInstalling = false
                self?.installMessage = "应用已成功安装到设备！\n\n如果应用无法打开，请在设备上前往：\n设置 → 通用 → VPN与设备管理\n信任开发者证书"
                self?.showInstallSuccess = true
                self?.log("✅ 安装成功!")
            }
            return
        } catch let error as SigningError {
            log("⚠️ 安装失败: \(error.localizedDescription ?? "未知错误")")
        } catch {
            log("⚠️ 安装失败: \(error.localizedDescription)")
        }
        
        // No installer available or failed
        DispatchQueue.main.async { [weak self] in
            self?.isInstalling = false
            self?.errorMessage = "安装失败。请尝试：\n\n1. 确保已运行：brew install ideviceinstaller\n2. 重启终端后再试\n3. 或使用 Xcode → Devices and Simulators 手动安装"
            self?.showError = true
        }
    }
    
    private func runShellCommand(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SigningError.commandFailed(output)
        }
    }
}

// MARK: - Errors
enum SigningError: LocalizedError {
    case appNotFound
    case commandFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "在 IPA 中找不到 .app 目录"
        case .commandFailed(let output):
            return "命令执行失败: \(output)"
        }
    }
}
