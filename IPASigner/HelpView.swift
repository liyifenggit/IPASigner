import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    
    let steps: [(title: String, icon: String, content: String)] = [
        (
            title: "1. 创建 CSR 证书请求",
            icon: "1.circle.fill",
            content: """
            在 Mac 电脑上操作：
            
            1. 打开「钥匙串访问」应用
               • Spotlight 搜索 "Keychain Access"
            
            2. 菜单栏选择：
               钥匙串访问 → 证书助理 → 从证书颁发机构请求证书...
            
            3. 填写信息：
               • 用户电子邮件：你的邮箱
               • 常用名称：任意名称
               • 选择「存储到磁盘」
            
            4. 保存 .certSigningRequest 文件到桌面
            """
        ),
        (
            title: "2. 上传到 Apple Developer",
            icon: "2.circle.fill",
            content: """
            登录 Apple Developer 网站：
            
            1. 访问 developer.apple.com/account
            
            2. 进入 Certificates, Identifiers & Profiles
            
            3. 点击 Certificates → 点击 + 按钮
            
            4. 选择证书类型：
               • Apple Development（开发测试）
               • Apple Distribution（发布）
            
            5. 上传刚才创建的 CSR 文件
            
            6. 下载生成的 .cer 证书文件
            """
        ),
        (
            title: "3. 安装证书",
            icon: "3.circle.fill",
            content: """
            安装下载的证书：
            
            方法一：双击 .cer 文件
            • 系统会自动添加到钥匙串
            
            方法二：使用本软件
            • 点击「导入证书」按钮
            • 选择 .cer 或 .p12 文件
            
            验证安装：
            • 打开钥匙串访问
            • 选择「我的证书」
            • 应该能看到证书和私钥
            """
        ),
        (
            title: "4. 创建 App ID",
            icon: "4.circle.fill",
            content: """
            在 Apple Developer 网站：
            
            1. 进入 Identifiers → 点击 +
            
            2. 选择 App IDs → Continue
            
            3. 选择 App → Continue
            
            4. 填写：
               • Description：应用描述
               • Bundle ID：如 com.yourname.appname
            
            5. 选择需要的 Capabilities
            
            6. 点击 Register
            """
        ),
        (
            title: "5. 添加测试设备",
            icon: "5.circle.fill",
            content: """
            在 Apple Developer 网站：
            
            1. 进入 Devices → 点击 +
            
            2. 填写：
               • Device Name：设备名称
               • Device ID (UDID)：设备唯一标识
            
            获取 UDID 方法：
            • 连接设备到 Mac
            • 打开「访达」→ 点击设备
            • 点击设备信息直到显示 UDID
            • 或使用命令：
              idevice_id -l
            """
        ),
        (
            title: "6. 创建 Provisioning Profile",
            icon: "6.circle.fill",
            content: """
            在 Apple Developer 网站：
            
            1. 进入 Profiles → 点击 +
            
            2. 选择类型：
               • iOS App Development（开发）
               • Ad Hoc（分发到指定设备）
            
            3. 选择之前创建的 App ID
            
            4. 选择证书
            
            5. 选择测试设备
            
            6. 命名并下载 .mobileprovision 文件
            """
        ),
        (
            title: "7. 签名并安装",
            icon: "7.circle.fill",
            content: """
            使用本软件完成签名：
            
            1. 选择 IPA 文件
            
            2. 选择 Provisioning Profile
            
            3. 选择签名证书
            
            4. 可选：设置导出目录
            
            5. 点击「开始签名」
            
            6. 安装到设备（两种方式）：
            
            方式一：一键安装
            • 点击「安装到设备」按钮
            • 需要已安装 ideviceinstaller
            
            方式二：通过 Xcode 安装
            • 点击「打开 Xcode Devices」
            • 在 Xcode 中选择你的设备
            • 将签名后的 IPA 拖入已安装应用列表
            • 或点击 + 按钮选择 IPA 文件
            
            ⚠️ 安装前请确保：
            • 设备已连接并信任此电脑
            • 设备 UDID 已添加到 Profile
            • 安装后需在设备上信任证书：
              设置 → 通用 → VPN与设备管理
            """
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("使用帮助")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            HStack(spacing: 0) {
                // Step List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            StepButton(
                                title: steps[index].title,
                                icon: steps[index].icon,
                                isSelected: currentStep == index
                            ) {
                                withAnimation {
                                    currentStep = index
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 250)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Step Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: steps[currentStep].icon)
                                .font(.title)
                                .foregroundColor(.accentColor)
                            
                            Text(steps[currentStep].title)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Divider()
                        
                        Text(steps[currentStep].content)
                            .font(.body)
                            .lineSpacing(6)
                        
                        Spacer()
                        
                        // Navigation buttons
                        HStack {
                            if currentStep > 0 {
                                Button(action: {
                                    withAnimation { currentStep -= 1 }
                                }) {
                                    Label("上一步", systemImage: "chevron.left")
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Spacer()
                            
                            if currentStep < steps.count - 1 {
                                Button(action: {
                                    withAnimation { currentStep += 1 }
                                }) {
                                    Label("下一步", systemImage: "chevron.right")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button(action: { dismiss() }) {
                                    Label("开始使用", systemImage: "checkmark")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 750, height: 550)
    }
}

struct StepButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HelpView()
}
