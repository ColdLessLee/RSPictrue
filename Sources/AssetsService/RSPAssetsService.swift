import Foundation
import Photos
import UIKit
import AVFoundation
import RSPictureCore

#if canImport(Kingfisher)
import Kingfisher
#endif

// MARK: - Media Type Enumeration
public enum RSPMediaType: CaseIterable {
    case image
    case video
    case audio
    case livePhoto
    case all
    
    var phAssetMediaType: PHAssetMediaType? {
        switch self {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .livePhoto, .all:
            return nil
        }
    }
}

// MARK: - Asset Query Result
public struct RSPAssetQueryResult {
    public let assets: [PHAsset]
    public let totalCount: Int
    public let hasMore: Bool
    public let nextOffset: Int
}

// MARK: - Batch Operation Result
public struct RSPBatchOperationResult {
    public let successfulIds: [String]
    public let failedIds: [String: Error]
    public let totalProcessed: Int
}



public final class RSPAssetsService: NSObject {
    
    // MARK: - Singleton
    public static let shared = RSPAssetsService()
    
    // MARK: - Threading
    private let serialQueue = DispatchQueue(label: "com.rspicture.assets.serial", qos: .userInitiated)
    private let concurrentQueue = DispatchQueue(label: "com.rspicture.assets.concurrent", qos: .userInitiated, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "com.rspicture.assets.state", qos: .userInitiated)
    
    // MARK: - Cache Management
    private var assetCache: [RSPMediaType: [PHAsset]] = [:]
    private var lastFetchDate: [RSPMediaType: Date] = [:]
    private let imageManager = PHImageManager.default()
    
    // MARK: - Kingfisher Support
    #if canImport(Kingfisher)
    private let kingfisherCache = ImageCache.default
    #endif
    
    // MARK: - Image Request Options
    private let imageRequestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }()
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupNotifications()
    }
    
    // MARK: - Utility Function
    private func useMainQueueCalling<Arg>(_ block: @escaping (Arg) -> Void) -> (Arg) -> Void {
        return { arg in
            if Thread.isMainThread {
                block(arg)
            } else {
                DispatchQueue.main.async {
                    block(arg)
                }
            }
        }
    }
    
    // MARK: - Setup
    private func setupNotifications() {
        PHPhotoLibrary.shared().register(self)
    }
    
    // MARK: - Public Interface - Asset Fetching
    
    /// Fetch all assets for a specific media type with caching
    public func fetchAllAssets(
        for mediaType: RSPMediaType,
        completion: @escaping (Result<[PHAsset], Error>) -> Void
    ) {
        checkPhotosPermission { [weak self] authorized in
            guard authorized else {
                let callback = self?.useMainQueueCalling(completion) ?? completion
                callback(.failure(RSPictureError.photosAccessDenied))
                return
            }
            
            self?.concurrentQueue.async { [weak self] in
                self?.performAssetFetch(for: mediaType, completion: completion)
            }
        }
    }
    
    /// Refresh cached assets for a specific media type
    public func refreshAssets(
        for mediaType: RSPMediaType,
        completion: @escaping (Result<[PHAsset], Error>) -> Void
    ) {
        stateQueue.async { [weak self] in
            self?.assetCache[mediaType] = nil
            self?.lastFetchDate[mediaType] = nil
        }
        
        fetchAllAssets(for: mediaType, completion: completion)
    }
    
    // MARK: - Public Interface - Pagination
    
    /// Fetch assets with pagination support
    public func fetchAssets(
        for mediaType: RSPMediaType,
        offset: Int,
        limit: Int,
        completion: @escaping (Result<RSPAssetQueryResult, Error>) -> Void
    ) {
        guard offset >= 0, limit > 0 else {
            let callback = useMainQueueCalling(completion)
            callback(.failure(RSPictureError.invalidOffset))
            return
        }
        
        fetchAllAssets(for: mediaType) { [weak self] result in
            switch result {
            case .success(let allAssets):
                let totalCount = allAssets.count
                let startIndex = min(offset, totalCount)
                let endIndex = min(startIndex + limit, totalCount)
                
                let paginatedAssets = Array(allAssets[startIndex..<endIndex])
                let hasMore = endIndex < totalCount
                let nextOffset = hasMore ? endIndex : totalCount
                
                let queryResult = RSPAssetQueryResult(
                    assets: paginatedAssets,
                    totalCount: totalCount,
                    hasMore: hasMore,
                    nextOffset: nextOffset
                )
                
                let callback = self?.useMainQueueCalling(completion) ?? completion
                callback(.success(queryResult))
                
            case .failure(let error):
                let callback = self?.useMainQueueCalling(completion) ?? completion
                callback(.failure(error))
            }
        }
    }
    
    // MARK: - Public Interface - CRUD Operations
    
    /// Fetch assets by IDs
    public func fetchAssets(
        withIds ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        guard !ids.isEmpty else {
            let result = RSPBatchOperationResult(successfulIds: [], failedIds: [:], totalProcessed: 0)
            let callback = useMainQueueCalling(completion)
            callback(.success(result))
            return
        }
        
        concurrentQueue.async { [weak self] in
            self?.performBatchFetch(ids: ids, completion: completion)
        }
    }
    
    /// Delete assets by IDs
    public func deleteAssets(
        withIds ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        guard !ids.isEmpty else {
            let result = RSPBatchOperationResult(successfulIds: [], failedIds: [:], totalProcessed: 0)
            let callback = useMainQueueCalling(completion)
            callback(.success(result))
            return
        }
        
        checkPhotosPermission { [weak self] authorized in
            guard authorized else {
                let callback = self?.useMainQueueCalling(completion) ?? completion
                callback(.failure(RSPictureError.photosAccessDenied))
                return
            }
            
            self?.serialQueue.async { [weak self] in
                self?.performBatchDelete(ids: ids, completion: completion)
            }
        }
    }
    
    /// Add assets to favorites
    public func favoriteAssets(
        withIds ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        performBatchUpdate(ids: ids, updateBlock: { asset in
            PHAssetChangeRequest(for: asset).isFavorite = true
        }, completion: completion)
    }
    
    /// Remove assets from favorites
    public func unfavoriteAssets(
        withIds ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        performBatchUpdate(ids: ids, updateBlock: { asset in
            PHAssetChangeRequest(for: asset).isFavorite = false
        }, completion: completion)
    }
    
    // MARK: - Public Interface - Image Loading
    
    /// Load UIImage from PHAsset with optional Kingfisher caching
    public func loadImage(
        from asset: PHAsset,
        targetSize: CGSize = CGSize(width: 300, height: 300),
        completion: @escaping (Result<UIImage?, Error>) -> Void
    ) {
        #if canImport(Kingfisher)
        loadImageWithKingfisher(asset: asset, targetSize: targetSize, completion: completion)
        #else
        loadImageWithPHImageManager(asset: asset, targetSize: targetSize, completion: completion)
        #endif
    }
    
    /// Load original UIImage from PHAsset
    public func loadOriginalImage(
        from asset: PHAsset,
        completion: @escaping (Result<UIImage?, Error>) -> Void
    ) {
        let originalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        loadImage(from: asset, targetSize: originalSize, completion: completion)
    }
    
    // MARK: - Private Methods - Asset Fetching
    
    private func performAssetFetch(
        for mediaType: RSPMediaType,
        completion: @escaping (Result<[PHAsset], Error>) -> Void
    ) {
        // Check cache first
        let cachedAssets = stateQueue.sync { () -> [PHAsset]? in
            guard let cached = assetCache[mediaType],
                  let lastFetch = lastFetchDate[mediaType],
                  Date().timeIntervalSince(lastFetch) < 300 else { // 5 minutes cache
                return nil
            }
            return cached
        }
        
        if let cached = cachedAssets {
            let callback = useMainQueueCalling(completion)
            callback(.success(cached))
            return
        }
        
        // Fetch from Photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult: PHFetchResult<PHAsset>
        
        switch mediaType {
        case .all:
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        case .livePhoto:
            fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)
            fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        default:
            guard let phMediaType = mediaType.phAssetMediaType else {
                let callback = useMainQueueCalling(completion)
                callback(.failure(RSPictureError.assetNotFound))
                return
            }
            fetchResult = PHAsset.fetchAssets(with: phMediaType, options: fetchOptions)
        }
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        // Update cache
        stateQueue.async { [weak self] in
            self?.assetCache[mediaType] = assets
            self?.lastFetchDate[mediaType] = Date()
        }
        
        let callback = useMainQueueCalling(completion)
        callback(.success(assets))
    }
    
    // MARK: - Private Methods - Batch Operations
    
    private func performBatchFetch(
        ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        let fetchOptions = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: fetchOptions)
        
        var successfulIds: [String] = []
        var failedIds: [String: Error] = [:]
        
        fetchResult.enumerateObjects { asset, _, _ in
            successfulIds.append(asset.localIdentifier)
        }
        
        // Find failed IDs
        let foundIds = Set(successfulIds)
        for id in ids {
            if !foundIds.contains(id) {
                failedIds[id] = RSPictureError.assetNotFound
            }
        }
        
        let result = RSPBatchOperationResult(
            successfulIds: successfulIds,
            failedIds: failedIds,
            totalProcessed: ids.count
        )
        
        let callback = useMainQueueCalling(completion)
        callback(.success(result))
    }
    
    private func performBatchDelete(
        ids: [String],
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        let fetchOptions = PHFetchOptions()
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        guard !assets.isEmpty else {
            let result = RSPBatchOperationResult(
                successfulIds: [],
                failedIds: ids.reduce(into: [:]) { dict, id in
                    dict[id] = RSPictureError.assetNotFound
                },
                totalProcessed: ids.count
            )
            let callback = useMainQueueCalling(completion)
            callback(.success(result))
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }) { [weak self] success, error in
            let result: RSPBatchOperationResult
            
            if success {
                let successfulIds = assets.map { $0.localIdentifier }
                result = RSPBatchOperationResult(
                    successfulIds: successfulIds,
                    failedIds: [:],
                    totalProcessed: ids.count
                )
            } else {
                let failedIds = ids.reduce(into: [:]) { dict, id in
                    dict[id] = error ?? RSPictureError.batchOperationFailed
                }
                result = RSPBatchOperationResult(
                    successfulIds: [],
                    failedIds: failedIds,
                    totalProcessed: ids.count
                )
            }
            
            let callback = self?.useMainQueueCalling(completion) ?? completion
            callback(.success(result))
        }
    }
    
    private func performBatchUpdate(
        ids: [String],
        updateBlock: @escaping (PHAsset) -> Void,
        completion: @escaping (Result<RSPBatchOperationResult, Error>) -> Void
    ) {
        checkPhotosPermission { [weak self] authorized in
            guard authorized else {
                let callback = self?.useMainQueueCalling(completion) ?? completion
                callback(.failure(RSPictureError.photosAccessDenied))
                return
            }
            
            self?.serialQueue.async { [weak self] in
                let fetchOptions = PHFetchOptions()
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: fetchOptions)
                
                var assets: [PHAsset] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }
                
                PHPhotoLibrary.shared().performChanges({
                    for asset in assets {
                        updateBlock(asset)
                    }
                }) { [weak self] success, error in
                    let result: RSPBatchOperationResult
                    
                    if success {
                        let successfulIds = assets.map { $0.localIdentifier }
                        result = RSPBatchOperationResult(
                            successfulIds: successfulIds,
                            failedIds: [:],
                            totalProcessed: ids.count
                        )
                    } else {
                        let failedIds = ids.reduce(into: [:]) { dict, id in
                            dict[id] = error ?? RSPictureError.batchOperationFailed
                        }
                        result = RSPBatchOperationResult(
                            successfulIds: [],
                            failedIds: failedIds,
                            totalProcessed: ids.count
                        )
                    }
                    
                    let callback = self?.useMainQueueCalling(completion) ?? completion
                    callback(.success(result))
                }
            }
        }
    }
    
    // MARK: - Private Methods - Image Loading
    
    private func loadImageWithPHImageManager(
        asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (Result<UIImage?, Error>) -> Void
    ) {
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: imageRequestOptions
        ) { [weak self] image, info in
            let callback = self?.useMainQueueCalling(completion) ?? completion
            
            if let error = info?[PHImageErrorKey] as? Error {
                callback(.failure(error))
            } else if let image = image {
                callback(.success(image))
            } else {
                callback(.failure(RSPictureError.imageLoadingFailed))
            }
        }
    }
    
    #if canImport(Kingfisher)
    private func loadImageWithKingfisher(
        asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (Result<UIImage?, Error>) -> Void
    ) {
        let cacheKey = "\(asset.localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))"
        
        // Try to retrieve from Kingfisher cache first
        kingfisherCache.retrieveImage(forKey: cacheKey) { [weak self] result in
            switch result {
            case .success(let value):
                if let cachedImage = value.image {
                    // Found in cache
                    let callback = self?.useMainQueueCalling(completion) ?? completion
                    callback(.success(cachedImage))
                    return
                }
                
                // Not in cache, load from PHImageManager and cache the result
                self?.loadImageWithPHImageManager(asset: asset, targetSize: targetSize) { [weak self] result in
                    switch result {
                    case .success(let image):
                        // Store in Kingfisher cache for future use
                        if let image = image {
                            self?.kingfisherCache.store(image, forKey: cacheKey)
                        }
                        let callback = self?.useMainQueueCalling(completion) ?? completion
                        callback(.success(image))
                        
                    case .failure(let error):
                        let callback = self?.useMainQueueCalling(completion) ?? completion
                        callback(.failure(error))
                    }
                }
                
            case .failure:
                // Cache retrieval failed, fallback to PHImageManager
                self?.loadImageWithPHImageManager(asset: asset, targetSize: targetSize, completion: completion)
            }
        }
    }
    #endif
    
    // MARK: - Private Methods - Permissions
    
    private func checkPhotosPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        @unknown default:
            completion(false)
        }
    }
    
    // MARK: - Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension RSPAssetsService: PHPhotoLibraryChangeObserver {
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Invalidate cache when photo library changes
        stateQueue.async { [weak self] in
            self?.assetCache.removeAll()
            self?.lastFetchDate.removeAll()
        }
    }
}
