import UIKit
import Photos
import RspictureCore

// MARK: - Assets Service Usage Example
class AssetsServiceViewController: UIViewController {
    
    // MARK: - Properties
    private let assetsService = RSPAssetsService.shared
    private var currentAssets: [PHAsset] = []
    private var currentOffset = 0
    private let pageSize = 50
    
    // UI Elements
    private lazy var mediaTypeSegmentedControl: UISegmentedControl = {
        let items = ["全部", "图片", "视频", "Live Photo"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 1 // 默认选择图片
        control.addTarget(self, action: #selector(mediaTypeChanged), for: .valueChanged)
        return control
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.text = "选择媒体类型并点击加载"
        return label
    }()
    
    private lazy var loadButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("加载资源", for: .normal)
        button.addTarget(self, action: #selector(loadAssets), for: .touchUpInside)
        return button
    }()
    
    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("刷新缓存", for: .normal)
        button.addTarget(self, action: #selector(refreshAssets), for: .touchUpInside)
        return button
    }()
    
    private lazy var favoriteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("收藏选中", for: .normal)
        button.addTarget(self, action: #selector(favoriteSelected), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()
    
    private lazy var deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("删除选中", for: .normal)
        button.tintColor = .systemRed
        button.addTarget(self, action: #selector(deleteSelected), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(AssetCell.self, forCellWithReuseIdentifier: "AssetCell")
        return collectionView
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Assets Service 示例"
        view.backgroundColor = .systemBackground
        
        view.addSubview(mediaTypeSegmentedControl)
        view.addSubview(statusLabel)
        view.addSubview(loadButton)
        view.addSubview(refreshButton)
        view.addSubview(favoriteButton)
        view.addSubview(deleteButton)
        view.addSubview(collectionView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Media Type Segmented Control
            mediaTypeSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            mediaTypeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mediaTypeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Status Label
            statusLabel.topAnchor.constraint(equalTo: mediaTypeSegmentedControl.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Load Button
            loadButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            loadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            loadButton.widthAnchor.constraint(equalToConstant: 80),
            
            // Refresh Button
            refreshButton.topAnchor.constraint(equalTo: loadButton.topAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: loadButton.trailingAnchor, constant: 16),
            refreshButton.widthAnchor.constraint(equalToConstant: 80),
            
            // Favorite Button
            favoriteButton.topAnchor.constraint(equalTo: loadButton.topAnchor),
            favoriteButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 16),
            favoriteButton.widthAnchor.constraint(equalToConstant: 80),
            
            // Delete Button
            deleteButton.topAnchor.constraint(equalTo: loadButton.topAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: favoriteButton.trailingAnchor, constant: 16),
            deleteButton.widthAnchor.constraint(equalToConstant: 80),
            
            // Collection View
            collectionView.topAnchor.constraint(equalTo: loadButton.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc private func mediaTypeChanged() {
        currentAssets.removeAll()
        currentOffset = 0
        collectionView.reloadData()
        updateButtonStates()
    }
    
    @objc private func loadAssets() {
        let mediaType = getSelectedMediaType()
        loadButton.isEnabled = false
        statusLabel.text = "正在加载..."
        
        // 使用分页查询来加载资源
        assetsService.fetchAssets(
            for: mediaType,
            offset: currentOffset,
            limit: pageSize
        ) { [weak self] result in
            switch result {
            case .success(let queryResult):
                self?.currentAssets.append(contentsOf: queryResult.assets)
                self?.currentOffset = queryResult.nextOffset
                self?.collectionView.reloadData()
                
                let statusText = "已加载 \(self?.currentAssets.count ?? 0) 个资源"
                let hasMoreText = queryResult.hasMore ? "（还有更多）" : "（全部加载完成）"
                self?.statusLabel.text = statusText + hasMoreText
                
            case .failure(let error):
                self?.statusLabel.text = "加载失败: \(error.localizedDescription)"
            }
            
            self?.loadButton.isEnabled = true
        }
    }
    
    @objc private func refreshAssets() {
        let mediaType = getSelectedMediaType()
        refreshButton.isEnabled = false
        statusLabel.text = "正在刷新缓存..."
        
        assetsService.refreshAssets(for: mediaType) { [weak self] result in
            switch result {
            case .success(let assets):
                self?.currentAssets = Array(assets.prefix(self?.pageSize ?? 50))
                self?.currentOffset = min(self?.pageSize ?? 50, assets.count)
                self?.collectionView.reloadData()
                self?.statusLabel.text = "缓存已刷新，共 \(assets.count) 个资源"
                
            case .failure(let error):
                self?.statusLabel.text = "刷新失败: \(error.localizedDescription)"
            }
            
            self?.refreshButton.isEnabled = true
        }
    }
    
    @objc private func favoriteSelected() {
        guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems,
              !selectedIndexPaths.isEmpty else { return }
        
        let selectedAssets = selectedIndexPaths.map { currentAssets[$0.item] }
        let assetIds = selectedAssets.map { $0.localIdentifier }
        
        favoriteButton.isEnabled = false
        statusLabel.text = "正在添加到收藏..."
        
        assetsService.favoriteAssets(withIds: assetIds) { [weak self] result in
            switch result {
            case .success(let batchResult):
                let successCount = batchResult.successfulIds.count
                let failCount = batchResult.failedIds.count
                self?.statusLabel.text = "收藏操作完成: 成功 \(successCount), 失败 \(failCount)"
                
                // 取消选择
                selectedIndexPaths.forEach { self?.collectionView.deselectItem(at: $0, animated: true) }
                
            case .failure(let error):
                self?.statusLabel.text = "收藏失败: \(error.localizedDescription)"
            }
            
            self?.favoriteButton.isEnabled = true
            self?.updateButtonStates()
        }
    }
    
    @objc private func deleteSelected() {
        guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems,
              !selectedIndexPaths.isEmpty else { return }
        
        let selectedAssets = selectedIndexPaths.map { currentAssets[$0.item] }
        let assetIds = selectedAssets.map { $0.localIdentifier }
        
        // 显示确认对话框
        let alert = UIAlertController(
            title: "确认删除",
            message: "确定要删除选中的 \(selectedAssets.count) 个资源吗？",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performDelete(assetIds: assetIds, selectedIndexPaths: selectedIndexPaths)
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func performDelete(assetIds: [String], selectedIndexPaths: [IndexPath]) {
        deleteButton.isEnabled = false
        statusLabel.text = "正在删除..."
        
        assetsService.deleteAssets(withIds: assetIds) { [weak self] result in
            switch result {
            case .success(let batchResult):
                let successCount = batchResult.successfulIds.count
                let failCount = batchResult.failedIds.count
                
                // 从本地数组中移除成功删除的资源
                let successfulAssetIds = Set(batchResult.successfulIds)
                self?.currentAssets.removeAll { asset in
                    successfulAssetIds.contains(asset.localIdentifier)
                }
                
                self?.collectionView.reloadData()
                self?.statusLabel.text = "删除操作完成: 成功 \(successCount), 失败 \(failCount)"
                
            case .failure(let error):
                self?.statusLabel.text = "删除失败: \(error.localizedDescription)"
            }
            
            self?.deleteButton.isEnabled = true
            self?.updateButtonStates()
        }
    }
    
    // MARK: - Helper Methods
    private func getSelectedMediaType() -> RSPMediaType {
        switch mediaTypeSegmentedControl.selectedSegmentIndex {
        case 0: return .all
        case 1: return .image
        case 2: return .video
        case 3: return .livePhoto
        default: return .image
        }
    }
    
    private func updateButtonStates() {
        let hasSelection = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
        favoriteButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }
}

// MARK: - UICollectionViewDataSource
extension AssetsServiceViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return currentAssets.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AssetCell", for: indexPath) as! AssetCell
        let asset = currentAssets[indexPath.item]
        cell.configure(with: asset)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension AssetsServiceViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        updateButtonStates()
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        updateButtonStates()
    }
    
    // 加载更多数据（当滚动到底部时）
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height
        
        if offsetY > contentHeight - height * 2 {
            // 当滚动到接近底部时，自动加载更多
            loadAssets()
        }
    }
}

// MARK: - Custom Cell
class AssetCell: UICollectionViewCell {
    
    private let imageView = UIImageView()
    private let typeLabel = UILabel()
    private let assetsService = RSPAssetsService.shared
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        typeLabel.font = UIFont.systemFont(ofSize: 10)
        typeLabel.textColor = .white
        typeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        typeLabel.textAlignment = .center
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(imageView)
        contentView.addSubview(typeLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            typeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            typeLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
        
        // 设置选中样式
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        selectedBackgroundView?.layer.borderColor = UIColor.systemBlue.cgColor
        selectedBackgroundView?.layer.borderWidth = 2
    }
    
    func configure(with asset: PHAsset) {
        // 设置媒体类型标签
        switch asset.mediaType {
        case .image:
            typeLabel.text = asset.mediaSubtypes.contains(.photoLive) ? "Live" : "图片"
        case .video:
            typeLabel.text = "视频"
        case .audio:
            typeLabel.text = "音频"
        @unknown default:
            typeLabel.text = "未知"
        }
        
        // 使用 AssetsService 加载图片
        assetsService.loadImage(from: asset, targetSize: CGSize(width: 100, height: 100)) { [weak self] result in
            switch result {
            case .success(let image):
                self?.imageView.image = image
            case .failure:
                self?.imageView.image = UIImage(systemName: "photo")
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
} 