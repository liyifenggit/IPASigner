import SwiftUI

struct ContentView: View {
    @StateObject private var signer = IPASignerManager()
    @State private var showHelp = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(onHelpTapped: { showHelp = true })
            
            Divider()
            
            // Main Content
            ScrollView {
                VStack(spacing: 20) {
                    // IPA File Selection
                    FileSelectionCard(
                        title: "IPA 文件",
                        icon: "doc.zipper",
                        filePath: $signer.ipaPath,
                        fileTypes: ["ipa"],
                        placeholder: "选择要签名的 IPA 文件"
                    )
                    
                    // Provisioning Profile Selection
                    FileSelectionCard(
                        title: "Provisioning Profile",
                        icon: "checkmark.seal",
                        filePath: $signer.profilePath,
                        fileTypes: ["mobileprovision"],
                        placeholder: "选择 .mobileprovision 文件"
                    )
                    
                    // Certificate Selection
                    CertificateSelectionCard(
                        selectedCertificate: $signer.selectedCertificate,
                        certificates: signer.certificates,
                        onImportCertificate: {
                            signer.importCertificate()
                        },
                        onRefreshCertificates: {
                            signer.loadCertificates()
                        }
                    )
                    
                    // Output Directory Selection
                    DirectorySelectionCard(
                        title: "导出目录",
                        icon: "folder",
                        directoryPath: $signer.outputDirectory,
                        placeholder: "默认保存到 IPA 文件所在目录"
                    )
                    
                    // Sign Button
                    SignButtonView(signer: signer)
                    
                    // Device Selection & Install (shown after signing)
                    if signer.outputPath != nil {
                        DeviceInstallCard(signer: signer)
                    }
                    
                    // Log Output
                    if !signer.logOutput.isEmpty {
                        LogOutputView(logOutput: signer.logOutput)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 750)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            signer.loadCertificates()
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    var onHelpTapped: (() -> Void)?
    
    var body: some View {
        HStack {
            Image(systemName: "signature")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("IPA Signer")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("一键签名 iOS 应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { onHelpTapped?() }) {
                Label("使用帮助", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - File Selection Card
struct FileSelectionCard: View {
    let title: String
    let icon: String
    @Binding var filePath: String
    let fileTypes: [String]
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            HStack {
                TextField(placeholder, text: $filePath)
                    .textFieldStyle(.roundedBorder)
                
                Button("浏览...") {
                    selectFile()
                }
                .buttonStyle(.bordered)
            }
            
            if !filePath.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(URL(fileURLWithPath: filePath).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = fileTypes.compactMap { ext in
            if ext == "ipa" {
                return .init(filenameExtension: "ipa")
            } else if ext == "mobileprovision" {
                return .init(filenameExtension: "mobileprovision")
            }
            return nil
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }
}

// MARK: - Directory Selection Card
struct DirectorySelectionCard: View {
    let title: String
    let icon: String
    @Binding var directoryPath: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            HStack {
                TextField(placeholder, text: $directoryPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("浏览...") {
                    selectDirectory()
                }
                .buttonStyle(.bordered)
            }
            
            if !directoryPath.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(URL(fileURLWithPath: directoryPath).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("留空则保存到 IPA 文件所在目录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择导出目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            directoryPath = url.path
        }
    }
}

// MARK: - Certificate Selection Card
struct CertificateSelectionCard: View {
    @Binding var selectedCertificate: String
    let certificates: [String]
    var onImportCertificate: (() -> Void)?
    var onRefreshCertificates: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("签名证书", systemImage: "person.badge.key")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    onImportCertificate?()
                }) {
                    Label("导入证书", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    onRefreshCertificates?()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("刷新证书列表")
            }
            
            if certificates.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在加载证书...")
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("", selection: $selectedCertificate) {
                    Text("请选择证书").tag("")
                    ForEach(certificates, id: \.self) { cert in
                        Text(cert)
                            .tag(cert)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            if !selectedCertificate.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("已选择证书")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Sign Button View
struct SignButtonView: View {
    @ObservedObject var signer: IPASignerManager
    
    var isReady: Bool {
        !signer.ipaPath.isEmpty &&
        !signer.profilePath.isEmpty &&
        !signer.selectedCertificate.isEmpty &&
        !signer.isSigning
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                signer.signIPA()
            }) {
                HStack {
                    if signer.isSigning {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "signature")
                    }
                    Text(signer.isSigning ? "签名中..." : "开始签名")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isReady)
            
            if !isReady && !signer.isSigning {
                Text("请先选择 IPA 文件、Provisioning Profile 和签名证书")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        
        // Success Alert
        .alert("签名完成", isPresented: $signer.showSuccess) {
            Button("在 Finder 中显示") {
                if let outputPath = signer.outputPath {
                    NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                }
            }
            Button("确定", role: .cancel) {}
        } message: {
            Text("已生成签名后的 IPA 文件")
        }
        
        // Error Alert
        .alert("签名失败", isPresented: $signer.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(signer.errorMessage)
        }
        
        // Import Certificate Alert
        .alert("导入证书", isPresented: $signer.showImportSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(signer.importMessage)
        }
        
        // Install Success Alert
        .alert("安装完成", isPresented: $signer.showInstallSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(signer.installMessage)
        }
    }
}

// MARK: - Device Install Card
struct DeviceInstallCard: View {
    @ObservedObject var signer: IPASignerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("安装到设备", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)
                
                Spacer()
                
                if signer.hasInstallTool {
                    Button(action: {
                        signer.refreshDevices()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("刷新设备列表")
                }
            }
            
            if !signer.hasInstallTool {
                // Tool not installed
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("需要安装设备管理工具")
                            .font(.subheadline)
                    }
                    
                    Button(action: {
                        signer.installDeviceTool()
                    }) {
                        HStack {
                            if signer.isInstallingTool {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(signer.isInstallingTool ? "安装中..." : "一键安装 ideviceinstaller")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(signer.isInstallingTool)
                    
                    Text("需要已安装 Homebrew，安装过程约需 1-2 分钟")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                // Tool installed, show device selection
                if signer.connectedDevices.isEmpty {
                    HStack {
                        Image(systemName: "iphone.slash")
                            .foregroundColor(.orange)
                        Text("未检测到设备，请连接 iPhone 并点击刷新")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("选择设备", selection: $signer.selectedDevice) {
                        Text("请选择设备").tag("")
                        ForEach(signer.connectedDevices) { device in
                            Text("\(device.name) (\(device.id.prefix(8))...)")
                                .tag(device.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                
                Button(action: {
                    signer.installToDevice()
                }) {
                    HStack {
                        if signer.isInstalling {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.app")
                        }
                        Text(signer.isInstalling ? "安装中..." : "安装到设备")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(signer.selectedDevice.isEmpty || signer.isInstalling)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Xcode alternative
            HStack {
                Image(systemName: "hammer")
                    .foregroundColor(.secondary)
                Text("或使用 Xcode 安装")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("打开 Xcode Devices") {
                    signer.openXcodeDevices()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            signer.checkInstallTool()
            if signer.hasInstallTool {
                signer.refreshDevices()
            }
        }
    }
}

// MARK: - Log Output View
struct LogOutputView: View {
    let logOutput: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("日志输出", systemImage: "terminal")
                .font(.headline)
            
            ScrollView {
                Text(logOutput)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 150)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
