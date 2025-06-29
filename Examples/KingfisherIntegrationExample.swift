import UIKit
import Photos
import RspictureCore
import AssetsService

// 这个示例展示如何正确处理Kingfisher的可选依赖
// 使用 #if canImport 编译宏，而不是运行时检查

#if canImport(Kingfisher)
import Kingfisher
#endif

// MARK: - Kingfisher Integration Example
class KingfisherIntegrationViewController: UIViewController {
    
    private let assetsService = RSPAssetsService.shared
    private var testAssets: [PHAsset] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kingfisher 集成示例"
        view.backgroundColor = .systemBackground
        
        setupUI()
        loadTestAssets()
    }
    
    private func setupUI() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Kingfisher 状态标签
        let kingfisherStatusLabel = UILabel()
        kingfisherStatusLabel.textAlignment = .center
        kingfisherStatusLabel.numberOfLines = 0
        
        #if canImport(Kingfisher)
        kingfisherStatusLabel.text = "✅ Kingfisher 可用\n图片将使用 Kingfisher 缓存"
        kingfisherStatusLabel.textColor = .systemGreen
        #else
        kingfisherStatusLabel.text = "❌ Kingfisher 不可用\n图片将使用 PHImageManager"
        kingfisherStatusLabel.textColor = .systemOrange
        #endif
        
        // 测试按钮
        let testButton = UIButton(type: .system)
        testButton.setTitle("测试图片加载", for: .normal)
        testButton.addTarget(self, action: #selector(testImageLoading), for: .touchUpInside)
        
        let clearCacheButton = UIButton(type: .system)
        clearCacheButton.setTitle("清除缓存", for: .normal)
        clearCacheButton.addTarget(self, action: #selector(clearCache), for: .touchUpInside)
        
        stackView.addArrangedSubview(kingfisherStatusLabel)
        stackView.addArrangedSubview(testButton)
        stackView.addArrangedSubview(clearCacheButton)
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    private func loadTestAssets() {
        assetsService.fetchAssets(for: .image, offset: 0, limit: 10) { [weak self] result in
            switch result {
            case .success(let queryResult):
                self?.testAssets = queryResult.assets
            case .failure(let error):
                print("加载测试资源失败: \(error)")
            }
        }
    }
    
    @objc private func testImageLoading() {
        guard !testAssets.isEmpty else {
            showAlert(title: "提示", message: "没有可用的测试图片")
            return
        }
        
        let asset = testAssets[0]
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 测试图片加载性能
        assetsService.loadImage(from: asset, targetSize: CGSize(width: 300, height: 300)) { result in
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            
            switch result {
            case .success(let image):
                let message = """
                图片加载成功！
                加载时间: \(String(format: "%.3f", loadTime))秒
                图片尺寸: \(image?.size ?? CGSize.zero)
                
                #if canImport(Kingfisher)
                使用了 Kingfisher 缓存
                #else
                使用了 PHImageManager
                #endif
                """
                self.showAlert(title: "加载结果", message: message)
                
            case .failure(let error):
                self.showAlert(title: "加载失败", message: error.localizedDescription)
            }
        }
    }
    
    @objc private func clearCache() {
        #if canImport(Kingfisher)
        // 清除 Kingfisher 缓存
        ImageCache.default.clearCache {
            DispatchQueue.main.async {
                self.showAlert(title: "缓存清除", message: "Kingfisher 缓存已清除")
            }
        }
        #else
        // 如果没有 Kingfisher，只能清除系统缓存
        URLCache.shared.removeAllCachedResponses()
        showAlert(title: "缓存清除", message: "系统缓存已清除")
        #endif
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Conditional Compilation Examples
extension KingfisherIntegrationViewController {
    
    // 这个方法展示如何在不同编译条件下使用不同的实现
    private func configureCachePolicy() {
        #if canImport(Kingfisher)
        // 当 Kingfisher 可用时的配置
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024 // 50MB
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024 // 200MB
        cache.diskStorage.config.expiration = .days(7) // 7天过期
        
        print("✅ Kingfisher 缓存已配置: 内存50MB, 磁盘200MB, 7天过期")
        #else
        // 当 Kingfisher 不可用时的替代方案
        let urlCache = URLCache.shared
        urlCache.memoryCapacity = 50 * 1024 * 1024 // 50MB
        urlCache.diskCapacity = 200 * 1024 * 1024 // 200MB
        
        print("⚠️ 使用系统 URLCache: 内存50MB, 磁盘200MB")
        #endif
    }
    
    // 展示如何为不同的编译条件提供不同的用户界面
    private func setupKingfisherSpecificUI() -> [UIView] {
        var views: [UIView] = []
        
        #if canImport(Kingfisher)
        // 只有在 Kingfisher 可用时才显示这些控件
        let kingfisherInfoLabel = UILabel()
        kingfisherInfoLabel.text = "高级缓存功能可用"
        kingfisherInfoLabel.textColor = .systemBlue
        
        let prefetchButton = UIButton(type: .system)
        prefetchButton.setTitle("预取图片", for: .normal)
        
        views.append(kingfisherInfoLabel)
        views.append(prefetchButton)
        #endif
        
        return views
    }
}

// MARK: - 编译宏使用说明
/*
 使用 #if canImport 的优势：
 
 1. 编译时检查：
    - 在编译时就知道 Kingfisher 是否可用
    - 避免运行时反射和字符串查找
    - 更好的性能和类型安全
 
 2. 代码清晰：
    - 明确区分有/无 Kingfisher 的代码路径
    - 避免复杂的运行时检查逻辑
    - 更容易维护和调试
 
 3. 优化编译：
    - 不需要的代码会在编译时被排除
    - 减少最终二进制文件大小
    - 避免无用的导入和依赖
 
 4. 类型安全：
    - 可以直接使用 Kingfisher 的类型和 API
    - 编译器会进行类型检查
    - 避免运行时类型转换错误
 
 使用方法：
 
 // 检查模块是否可导入
 #if canImport(Kingfisher)
 import Kingfisher
 // 使用 Kingfisher 的代码
 #else
 // 替代实现
 #endif
 
 // 也可以结合其他条件
 #if canImport(Kingfisher) && !DEBUG
 // 只在 Release 模式下使用 Kingfisher
 #endif
 
 注意事项：
 - canImport 检查的是编译时可用性，不是运行时
 - 需要确保在不同配置下都能正常编译
 - 测试时要分别测试有/无依赖的情况
 */ 