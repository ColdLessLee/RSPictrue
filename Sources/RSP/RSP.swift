import Foundation
import Photos
import UIKit
import RSPictureCore
import AssetsService

// MARK: - RSP Main Class
/// RSP - 统一的静态封装类，提供对RSPictureCore和AssetsService的访问
public final class RSP {
    
    // MARK: - Configuration
    public struct Config {
        public let coreConfiguration: RSPictureConfiguration
        public let enableKingfisherCache: Bool
        public let enableLogging: Bool
        
        public init(
            coreConfiguration: RSPictureConfiguration = .default,
            enableKingfisherCache: Bool = true,
            enableLogging: Bool = false
        ) {
            self.coreConfiguration = coreConfiguration
            self.enableKingfisherCache = enableKingfisherCache
            self.enableLogging = enableLogging
        }
        
        public static let `default` = Config()
    }
    
    // MARK: - Internal State
    private static var _configuration: Config = .default
    private static var _coreManager: RSPictureManager?
    private static var _assetsService: RSPAssetsService {
        return RSPAssetsService.shared
    }
    
    // MARK: - Initialization and Configuration
    
    /// 初始化RSP系统
    /// - Parameter config: 配置参数
    public static func initialize(with config: Config = .default) {
        _configuration = config
        _coreManager = RSPictureManager.shared
        _coreManager?.configure(with: config.coreConfiguration)
        
        // 配置日志系统
        RSPictureLogger.isEnabled = config.enableLogging
    }
    
    /// 获取当前配置
    public static var configuration: Config {
        return _configuration
    }
    
    // MARK: - Core Image Processing Functions
    
    /// 扫描相似图片
    /// - Parameters:
    ///   - assets: 需要扫描的图片资产
    ///   - delegate: 扫描进度代理
    /// - Returns: 相似图片结果
    public static func scanSimilarImages(
        from assets: [PHAsset],
        delegate: RSPictureDelegate? = nil
    ) async throws -> [SimilarityResult] {
        guard let manager = _coreManager else {
            throw RSPictureError.notInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let results = try await manager.scanSimilarImages(from: assets, delegate: delegate)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 批量处理图片
    /// - Parameter assets: 需要处理的图片资产
    /// - Returns: 处理进度
    public static func batchProcessImages(_ assets: [PHAsset]) -> AsyncThrowingStream<ScanProgress, Error> {
        guard let manager = _coreManager else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: RSPictureError.notInitialized)
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await progress in manager.processBatch(assets) {
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// 估算处理时间
    /// - Parameter assets: 资产列表
    /// - Returns: 预估处理时间（秒）
    public static func estimateProcessingTime(for assets: [PHAsset]) -> TimeInterval {
        guard let manager = _coreManager else {
            return 0
        }
        return manager.estimateProcessingTime(for: assets)
    }
    
    // MARK: - Assets Management Functions
    
    /// 获取所有指定类型的资产
    /// - Parameter mediaType: 媒体类型
    /// - Returns: 资产数组
    @available(iOS 14.0, *)
    public static func fetchAllAssets(for mediaType: RSPMediaType = .all) async throws -> [PHAsset] {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.fetchAllAssets(for: mediaType) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 分页获取资产
    /// - Parameters:
    ///   - mediaType: 媒体类型
    ///   - offset: 偏移量
    ///   - limit: 限制数量
    /// - Returns: 查询结果
    @available(iOS 14.0, *)
    public static func fetchAssets(
        for mediaType: RSPMediaType = .all,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> RSPAssetQueryResult {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.fetchAssets(for: mediaType, offset: offset, limit: limit) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 通过ID获取资产
    /// - Parameter ids: 资产ID数组
    /// - Returns: 批量操作结果
    @available(iOS 14.0, *)
    public static func fetchAssets(withIds ids: [String]) async throws -> RSPBatchOperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.fetchAssets(withIds: ids) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 删除资产
    /// - Parameter ids: 资产ID数组
    /// - Returns: 批量操作结果
    @available(iOS 14.0, *)
    public static func deleteAssets(withIds ids: [String]) async throws -> RSPBatchOperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.deleteAssets(withIds: ids) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 收藏资产
    /// - Parameter ids: 资产ID数组
    /// - Returns: 批量操作结果
    @available(iOS 14.0, *)
    public static func favoriteAssets(withIds ids: [String]) async throws -> RSPBatchOperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.favoriteAssets(withIds: ids) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 取消收藏资产
    /// - Parameter ids: 资产ID数组
    /// - Returns: 批量操作结果
    @available(iOS 14.0, *)
    public static func unfavoriteAssets(withIds ids: [String]) async throws -> RSPBatchOperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.unfavoriteAssets(withIds: ids) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 刷新缓存
    /// - Parameter mediaType: 媒体类型
    /// - Returns: 刷新后的资产数组
    @available(iOS 14.0, *)
    public static func refreshAssets(for mediaType: RSPMediaType = .all) async throws -> [PHAsset] {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.refreshAssets(for: mediaType) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Image Loading Functions
    
    /// 加载图片
    /// - Parameters:
    ///   - asset: 图片资产
    ///   - targetSize: 目标尺寸
    /// - Returns: UIImage对象
    public static func loadImage(
        from asset: PHAsset,
        targetSize: CGSize = CGSize(width: 300, height: 300)
    ) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.loadImage(from: asset, targetSize: targetSize) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// 加载原始尺寸图片
    /// - Parameter asset: 图片资产
    /// - Returns: UIImage对象
    public static func loadOriginalImage(from asset: PHAsset) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { continuation in
            _assetsService.loadOriginalImage(from: asset) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Utility Functions
    
    /// 检查Metal是否可用
    public static var isMetalAvailable: Bool {
        return RSPictureUtils.isMetalAvailable
    }
    
    /// 获取设备内存信息
    public static var deviceMemoryInfo: DeviceMemoryInfo {
        return RSPictureUtils.deviceMemoryInfo
    }
    
    /// 格式化进度信息
    /// - Parameter progress: 扫描进度
    /// - Returns: 格式化的进度字符串
    public static func formatProgress(_ progress: ScanProgress) -> String {
        return RSPictureUtils.formatProgress(progress)
    }
    
    /// 格式化时间估算
    /// - Parameter seconds: 秒数
    /// - Returns: 格式化的时间字符串
    public static func formatTimeEstimate(_ seconds: TimeInterval) -> String {
        return RSPictureUtils.formatTimeEstimate(seconds)
    }
    
    /// 检查是否应该使用增量处理
    /// - Parameter assetCount: 资产数量
    /// - Returns: 是否使用增量处理
    public static func shouldProcessIncrementally(assetCount: Int) -> Bool {
        guard let manager = _coreManager else {
            return assetCount > 500
        }
        return manager.shouldProcessIncrementally(assetCount: assetCount)
    }
    
    // MARK: - Logging Functions
    
    /// 记录日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - level: 日志级别
    public static func log(_ message: String, level: RSPictureLogger.LogLevel = .info) {
        RSPictureLogger.log(message, level: level)
    }
    
    /// 启用/禁用日志
    /// - Parameter enabled: 是否启用
    public static func setLoggingEnabled(_ enabled: Bool) {
        RSPictureLogger.isEnabled = enabled
    }
    
    /// 设置日志级别
    /// - Parameter level: 日志级别
    public static func setLogLevel(_ level: RSPictureLogger.LogLevel) {
        RSPictureLogger.logLevel = level
    }
}

// MARK: - Extensions for Convenience

public extension RSP {
    
    /// 快速扫描所有图片的相似性
    /// - Parameter delegate: 进度代理
    /// - Returns: 相似图片结果
    static func scanAllImages(delegate: RSPictureDelegate? = nil) async throws -> [SimilarityResult] {
        let assets = try await fetchAllAssets(for: .image)
        return try await scanSimilarImages(from: assets, delegate: delegate)
    }
    
    /// 获取高分辨率图片
    /// - Returns: 高分辨率图片资产数组
    static func getHighResolutionAssets() async throws -> [PHAsset] {
        let allAssets = try await fetchAllAssets(for: .image)
        return allAssets.highResolutionAssets
    }
    
    /// 按创建日期分组资产
    /// - Parameter mediaType: 媒体类型
    /// - Returns: 按日期分组的资产字典
    static func getAssetsGroupedByDate(for mediaType: RSPMediaType = .all) async throws -> [Date: [PHAsset]] {
        let assets = try await fetchAllAssets(for: mediaType)
        return assets.groupedByCreationDate
    }
}

