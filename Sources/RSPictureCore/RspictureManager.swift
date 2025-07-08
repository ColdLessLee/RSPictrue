import Foundation
import Photos
import Metal

// MARK: - Progress Models
public struct ScanProgress {
    public let totalAssets: Int
    public let processedAssets: Int
    public let currentBatchIndex: Int
    public let totalBatches: Int
    public let similarGroupsFound: Int
    
    public var percentage: Float {
        guard totalAssets > 0 else { return 0.0 }
        return Float(processedAssets) / Float(totalAssets)
    }
}

public struct SimilarityResult {
    public let similarGroups: [[PHAsset]]
    public let progress: ScanProgress
    public let isComplete: Bool
}

// MARK: - Delegate Protocol
public protocol RSPictureDelegate: AnyObject {
    func rspictureDidUpdateProgress(_ result: SimilarityResult)
    func rspictureDidComplete(_ finalResult: SimilarityResult)
    func rspictureDidEncounterError(_ error: Error)
}

// MARK: - Main Manager Class
public final class RSPictureManager {
    
    // MARK: - Singleton
    public static let shared = RSPictureManager()
    
    // MARK: - Properties
    let metalProcessor: MetalImageProcessor
    let batchProcessor: BatchProcessor
    let algorithmProcessor: ImageSimilarityAlgorithms
    
    // Thread-safe properties
    private let serialQueue = DispatchQueue(label: "com.rspicture.serial", qos: .userInitiated)
    private let concurrentQueue = DispatchQueue(label: "com.rspicture.concurrent", qos: .userInitiated, attributes: .concurrent)
    
    // State management with GCD serial queue
    private var _currentDelegate: RSPictureDelegate?
    private var _isProcessing = false
    private let stateQueue = DispatchQueue(label: "com.rspicture.state", qos: .userInitiated)
    
    // Cache management
    private var imageCache = NSCache<NSString, NSData>()
    private var histogramCache = NSCache<NSString, NSData>()
    
    // MARK: - Initialization
    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.metalProcessor = MetalImageProcessor(device: device)
        self.batchProcessor = BatchProcessor()
        self.algorithmProcessor = ImageSimilarityAlgorithms()
        
        setupCache()
    }
    
    // MARK: - Public Interface
    public func setDelegate(_ delegate: RSPictureDelegate?) {
        stateQueue.sync {
            _currentDelegate = delegate
        }
    }
    
    public var delegate: RSPictureDelegate? {
        return stateQueue.sync {
            return _currentDelegate
        }
    }
    
    public var isProcessing: Bool {
        return stateQueue.sync {
            return _isProcessing
        }
    }
    
    public func findSimilarImages(from assets: [PHAsset]) {
        guard !assets.isEmpty else {
            delegate?.rspictureDidComplete(SimilarityResult(
                similarGroups: [],
                progress: ScanProgress(totalAssets: 0, processedAssets: 0, currentBatchIndex: 0, totalBatches: 0, similarGroupsFound: 0),
                isComplete: true
            ))
            return
        }
        
        // Check if already processing
        let shouldStartProcessing = stateQueue.sync { () -> Bool in
            if _isProcessing {
                return false
            }
            _isProcessing = true
            return true
        }
        
        guard shouldStartProcessing else {
            notifyDelegate { delegate in
                delegate.rspictureDidEncounterError(RSPictureError.alreadyProcessing)
            }
            return
        }
        
        // Start processing on background queue
        concurrentQueue.async { [weak self] in
            self?.performSimilarityDetection(assets: assets)
        }
    }
    
    public func cancelProcessing() {
        serialQueue.async { [weak self] in
            self?.batchProcessor.cancelCurrentOperation()
            
            self?.stateQueue.sync {
                self?._isProcessing = false
            }
        }
    }
    
    public func clearCache() {
        serialQueue.async { [weak self] in
            self?.imageCache.removeAllObjects()
            self?.histogramCache.removeAllObjects()
        }
    }
    
    // MARK: - Async Interface
    public func scanSimilarImages(from assets: [PHAsset], delegate: RSPictureDelegate? = nil) async throws -> [SimilarityResult] {
        setDelegate(delegate)
        
        return try await withCheckedThrowingContinuation { continuation in
            var results: [SimilarityResult] = []
            var hasCompleted = false
            
            // Create a temporary delegate to capture results
            let tempDelegate = TempScanDelegate { result in
                results.append(result)
            } onComplete: { finalResult in
                results.append(finalResult)
                if !hasCompleted {
                    hasCompleted = true
                    continuation.resume(returning: results)
                }
            } onError: { error in
                if !hasCompleted {
                    hasCompleted = true
                    continuation.resume(throwing: error)
                }
            }
            
            setDelegate(tempDelegate)
            findSimilarImages(from: assets)
        }
    }
    
    public func processBatch(_ assets: [PHAsset]) -> AsyncThrowingStream<ScanProgress, Error> {
        return AsyncThrowingStream { continuation in
            setDelegate(StreamingDelegate { progress in
                continuation.yield(progress.progress)
            } onComplete: { _ in
                continuation.finish()
            } onError: { error in
                continuation.finish(throwing: error)
            })
            
            findSimilarImages(from: assets)
        }
    }
    
    // MARK: - Private Methods
    private func setupCache() {
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        histogramCache.countLimit = 200
        histogramCache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }
    
    private func notifyDelegate(_ block: @escaping (RSPictureDelegate) -> Void) {
        let currentDelegate = stateQueue.sync { _currentDelegate }
        guard let delegate = currentDelegate else { return }
        
        DispatchQueue.main.async {
            block(delegate)
        }
    }
    
    private func performSimilarityDetection(assets: [PHAsset]) {
        defer {
            stateQueue.sync {
                _isProcessing = false
            }
        }
        
        do {
            let batches = batchProcessor.createBatches(from: assets, threshold: 500)
            var allSimilarGroups: [[PHAsset]] = []
            
            for (batchIndex, batch) in batches.enumerated() {
                // Check if operation was cancelled
                guard !batchProcessor.isCancelled else {
                    return
                }
                
                let batchGroups = try processBatch(batch, batchIndex: batchIndex, totalBatches: batches.count, totalAssets: assets.count)
                allSimilarGroups.append(contentsOf: batchGroups)
                
                // Report progress for this batch
                let processedCount = (batchIndex + 1) * batch.count
                let progress = ScanProgress(
                    totalAssets: assets.count,
                    processedAssets: min(processedCount, assets.count),
                    currentBatchIndex: batchIndex + 1,
                    totalBatches: batches.count,
                    similarGroupsFound: allSimilarGroups.count
                )
                
                let result = SimilarityResult(
                    similarGroups: allSimilarGroups,
                    progress: progress,
                    isComplete: batchIndex == batches.count - 1
                )
                
                self.notifyDelegate { delegate in
                    if result.isComplete {
                        delegate.rspictureDidComplete(result)
                    } else {
                        delegate.rspictureDidUpdateProgress(result)
                    }
                }
            }
            
        } catch {
            self.notifyDelegate { delegate in
                delegate.rspictureDidEncounterError(error)
            }
        }
    }
    
    func processBatch(_ batch: [PHAsset], batchIndex: Int, totalBatches: Int, totalAssets: Int) throws -> [[PHAsset]] {
        // Extract image features using Metal
        let features = try metalProcessor.extractBatchFeatures(from: batch, cache: imageCache)
        
        // Run similarity algorithms on GPU
        let similarities = try algorithmProcessor.calculateSimilarities(features: features, using: metalProcessor)
        
        // Group similar images
        return groupSimilarAssets(batch: batch, similarities: similarities)
    }
    
    func groupSimilarAssets(batch: [PHAsset], similarities: [[Float]]) -> [[PHAsset]] {
        var groups: [[PHAsset]] = []
        var visited = Set<Int>()
        
        for i in 0..<batch.count {
            guard !visited.contains(i) else { continue }
            
            var currentGroup = [batch[i]]
            visited.insert(i)
            
            for j in (i+1)..<batch.count {
                guard !visited.contains(j) else { continue }
                
                // Check similarity threshold (adjustable)
                if similarities[i][j] > 0.8 {
                    currentGroup.append(batch[j])
                    visited.insert(j)
                }
            }
            
            // Only add groups with more than one image
            if currentGroup.count > 1 {
                groups.append(currentGroup)
            }
        }
        
        return groups
    }
}

// MARK: - Temporary Delegate Classes for Async Support
private class TempScanDelegate: RSPictureDelegate {
    private let onProgress: (SimilarityResult) -> Void
    private let onComplete: (SimilarityResult) -> Void
    private let onError: (Error) -> Void
    
    init(
        onProgress: @escaping (SimilarityResult) -> Void,
        onComplete: @escaping (SimilarityResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func rspictureDidUpdateProgress(_ result: SimilarityResult) {
        onProgress(result)
    }
    
    func rspictureDidComplete(_ finalResult: SimilarityResult) {
        onComplete(finalResult)
    }
    
    func rspictureDidEncounterError(_ error: Error) {
        onError(error)
    }
}

private class StreamingDelegate: RSPictureDelegate {
    private let onProgress: (SimilarityResult) -> Void
    private let onComplete: (SimilarityResult) -> Void
    private let onError: (Error) -> Void
    
    init(
        onProgress: @escaping (SimilarityResult) -> Void,
        onComplete: @escaping (SimilarityResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func rspictureDidUpdateProgress(_ result: SimilarityResult) {
        onProgress(result)
    }
    
    func rspictureDidComplete(_ finalResult: SimilarityResult) {
        onComplete(finalResult)
    }
    
    func rspictureDidEncounterError(_ error: Error) {
        onError(error)
    }
}
