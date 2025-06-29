import UIKit
import Photos
import RSPictureCore

// MARK: - Basic Usage Example
class ImageSimilarityViewController: UIViewController {
    
    // MARK: - Properties
    private let rspictureManager = RSPictureManager.shared
    private var allAssets: [PHAsset] = []
    private var similarGroups: [[PHAsset]] = []
    
    // UI Elements
    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(frame: .zero)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var scanButton: UIButton = {
        let button = UIButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var resultsTableView: UITableView = {
        let tableView = UITableView(frame: .zero)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupRSPicture()
        requestPhotoAccess()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "图片相似性扫描"
        
        progressView.isHidden = true
        statusLabel.text = "准备扫描相册图片"
        
        scanButton.setTitle("开始扫描", for: .normal)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.isHidden = true
        
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    private func setupRSPicture() {
        // 设置delegate
        rspictureManager.setDelegate(self)
        
        // 可选：配置参数
        let configuration = RSPictureConfiguration(
            maxBatchSize: 50,
            memoryBudget: 100 * 1024 * 1024, // 100MB
            similarityThreshold: 0.8,
            useIncrementalProcessing: true,
            cacheSize: 50
        )
        rspictureManager.configure(with: configuration)
        
        // 启用日志（可选）
        RSPictureLogger.isEnabled = true
        RSPictureLogger.logLevel = .info
    }
    
    // MARK: - Photo Access
    private func requestPhotoAccess() {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            loadAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                // PHPhotoLibrary authorization callbacks are on main queue
                if newStatus == .authorized || newStatus == .limited {
                    self?.loadAssets()
                } else {
                    self?.showPhotoAccessDeniedAlert()
                }
            }
        case .denied, .restricted:
            showPhotoAccessDeniedAlert()
        @unknown default:
            break
        }
    }
    
    private func loadAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        allAssets = []
        fetchResult.enumerateObjects { [weak self] asset, _, _ in
            self?.allAssets.append(asset)
        }
        
        // Update UI on main queue
        statusLabel.text = "已加载 \(allAssets.count) 张图片"
        scanButton.isEnabled = !allAssets.isEmpty
        
        if allAssets.count > 500 {
            statusLabel.text = "已加载 \(allAssets.count) 张图片（建议增量处理）"
        }
    }
    
    // MARK: - Actions
    @IBAction private func scanButtonTapped(_ sender: UIButton) {
        guard !allAssets.isEmpty else { return }
        
        // 显示预估时间
        let estimatedTime = rspictureManager.estimateProcessingTime(for: allAssets)
        let timeString = RSPictureUtils.formatTimeEstimate(estimatedTime)
        
        let alert = UIAlertController(
            title: "开始扫描",
            message: "将扫描 \(allAssets.count) 张图片\n预估时间：\(timeString)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "开始", style: .default) { [weak self] _ in
            self?.startScanning()
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
    
    @IBAction private func cancelButtonTapped(_ sender: UIButton) {
        rspictureManager.cancelProcessing()
        updateUIForScanComplete()
    }
    
    private func startScanning() {
        // 更新UI状态
        progressView.isHidden = false
        progressView.progress = 0.0
        scanButton.isHidden = true
        cancelButton.isHidden = false
        statusLabel.text = "正在扫描..."
        
        // 清空之前的结果
        similarGroups.removeAll()
        resultsTableView.reloadData()
        
        // 开始扫描
        rspictureManager.findSimilarImages(from: allAssets)
    }
    
    // MARK: - UI Updates
    private func updateUIForScanComplete() {
        progressView.isHidden = true
        scanButton.isHidden = false
        cancelButton.isHidden = true
        scanButton.setTitle("重新扫描", for: .normal)
    }
    
    private func showPhotoAccessDeniedAlert() {
        let alert = UIAlertController(
            title: "需要相册权限",
            message: "请在设置中允许访问相册以扫描图片",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "设置", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
}

// MARK: - RSPictureDelegate
extension ImageSimilarityViewController: RSPictureDelegate {
    func rspictureDidUpdateProgress(_ result: SimilarityResult) {
        // 更新进度条
        progressView.progress = result.progress.percentage
        
        // 更新状态文本
        let progressText = RSPictureUtils.formatProgress(result.progress)
        statusLabel.text = "扫描中... \(progressText)"
        
        // 更新结果（流式输出）
        similarGroups = result.similarGroups
        resultsTableView.reloadData()
        
        RSPictureLogger.log("Progress update: \(progressText), Found \(result.similarGroups.count) groups", level: .info)
    }
    
    func rspictureDidComplete(_ finalResult: SimilarityResult) {
        updateUIForScanComplete()
        
        // 更新最终结果
        similarGroups = finalResult.similarGroups
        resultsTableView.reloadData()
        
        // 显示完成状态
        let totalGroups = finalResult.similarGroups.count
        let totalSimilarImages = finalResult.similarGroups.reduce(0) { $0 + $1.count }
        
        statusLabel.text = "扫描完成！找到 \(totalGroups) 组相似图片，共 \(totalSimilarImages) 张"
        
        RSPictureLogger.log("Scan completed: \(totalGroups) groups, \(totalSimilarImages) similar images", level: .info)
        
        // 显示完成提示
        if totalGroups > 0 {
            let alert = UIAlertController(
                title: "扫描完成",
                message: "找到 \(totalGroups) 组相似图片，共 \(totalSimilarImages) 张图片",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }
    
    func rspictureDidEncounterError(_ error: Error) {
        updateUIForScanComplete()
        statusLabel.text = "扫描出错：\(error.localizedDescription)"
        
        RSPictureLogger.log("Scan error: \(error.localizedDescription)", level: .error)
        
        let alert = UIAlertController(
            title: "扫描失败",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - TableView DataSource & Delegate
extension ImageSimilarityViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return similarGroups.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return similarGroups[section].count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "相似组 \(section + 1) (\(similarGroups[section].count) 张)"
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        let asset = similarGroups[indexPath.section][indexPath.row]
        
        // 配置cell
        cell.textLabel?.text = "图片 \(asset.localIdentifier.prefix(8))..."
        cell.detailTextLabel?.text = "\(asset.pixelWidth)×\(asset.pixelHeight)"
        
        // 异步加载缩略图
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 60, height: 60),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            // PHImageManager callbacks are already on main queue for UI operations
            if let currentCell = tableView.cellForRow(at: indexPath) {
                currentCell.imageView?.image = image
                currentCell.setNeedsLayout()
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - Advanced Usage Example
class AdvancedImageSimilarityManager {
    private let rspictureManager = RSPictureManager.shared
    private var processedAssets = Set<String>()
    
    func performIncrementalScan(newAssets: [PHAsset]) {
        // 检查设备能力
        let memoryInfo = RSPictureUtils.deviceMemoryInfo
        if memoryInfo.isMemoryConstrained {
            RSPictureLogger.log("Device is memory constrained, using smaller batches", level: .warning)
        }
        
        // 只处理新增的资产
        let unprocessedAssets = newAssets.filter { asset in
            !processedAssets.contains(asset.localIdentifier)
        }
        
        guard !unprocessedAssets.isEmpty else {
            RSPictureLogger.log("No new assets to process", level: .info)
            return
        }
        
        RSPictureLogger.log("Starting incremental scan for \(unprocessedAssets.count) assets", level: .info)
        rspictureManager.findSimilarImages(from: unprocessedAssets)
    }
    
    func analyzeAssetComplexity(_ assets: [PHAsset]) {
        let highResAssets = assets.highResolutionAssets
        let totalPixels = assets.totalPixels
        
        RSPictureLogger.log("Asset analysis: \(assets.count) total, \(highResAssets.count) high-res, \(totalPixels) total pixels", level: .info)
        
        // 根据资产复杂度调整处理策略
        if highResAssets.count > assets.count / 2 {
            RSPictureLogger.log("High percentage of high-res assets, consider using smaller batches", level: .warning)
        }
    }
} 