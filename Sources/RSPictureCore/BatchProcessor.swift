import Foundation
import Photos

// MARK: - Batch Configuration
struct BatchConfiguration {
    static let defaultBatchSize = 50
    static let maxBatchSize = 500
    static let incrementalThreshold = 500
}

// MARK: - Batch Processor
final class BatchProcessor {
    
    // MARK: - Properties
    private var _isCancelled = false
    private let cancellationQueue = DispatchQueue(label: "com.rspicture.batch.cancellation", qos: .userInitiated)
    
    // MARK: - Public Interface
    var isCancelled: Bool {
        return cancellationQueue.sync {
            return _isCancelled
        }
    }
    
    func cancelCurrentOperation() {
        cancellationQueue.sync {
            _isCancelled = true
        }
    }
    
    func resetCancellation() {
        cancellationQueue.sync {
            _isCancelled = false
        }
    }
    
    // MARK: - Batch Creation
    func createBatches(from assets: [PHAsset], threshold: Int = BatchConfiguration.incrementalThreshold) -> [[PHAsset]] {
        resetCancellation()
        
        guard !assets.isEmpty else { return [] }
        
        let batchSize = determineBatchSize(for: assets.count, threshold: threshold)
        var batches: [[PHAsset]] = []
        
        for i in stride(from: 0, to: assets.count, by: batchSize) {
            let endIndex = min(i + batchSize, assets.count)
            let batch = Array(assets[i..<endIndex])
            batches.append(batch)
        }
        
        return batches
    }
    
    func createIncrementalBatches(from assets: [PHAsset], 
                                 processedAssets: Set<String>,
                                 threshold: Int = BatchConfiguration.incrementalThreshold) -> [[PHAsset]] {
        resetCancellation()
        
        // Filter out already processed assets
        let unprocessedAssets = assets.filter { asset in
            !processedAssets.contains(asset.localIdentifier)
        }
        
        guard !unprocessedAssets.isEmpty else { return [] }
        
        // If we have many unprocessed assets, use incremental processing
        if unprocessedAssets.count > threshold {
            return createSmartIncrementalBatches(from: unprocessedAssets, threshold: threshold)
        } else {
            return createBatches(from: unprocessedAssets, threshold: threshold)
        }
    }
    
    // MARK: - Batch Optimization
    func optimizeBatchesForMemory(batches: [[PHAsset]], memoryBudget: Int = 100 * 1024 * 1024) -> [[PHAsset]] {
        var optimizedBatches: [[PHAsset]] = []
        
        for batch in batches {
            let estimatedMemory = estimateMemoryUsage(for: batch)
            
            if estimatedMemory > memoryBudget {
                // Split large batches
                let splitBatches = splitBatchByMemory(batch, memoryBudget: memoryBudget)
                optimizedBatches.append(contentsOf: splitBatches)
            } else {
                optimizedBatches.append(batch)
            }
        }
        
        return optimizedBatches
    }
    
    // MARK: - Asset Analysis
    func analyzeAssetComplexity(_ assets: [PHAsset]) -> BatchComplexityReport {
        var totalPixels: Int64 = 0
        var highResolutionCount = 0
        var videoCount = 0
        var imageCount = 0
        
        for asset in assets {
            let pixels = Int64(asset.pixelWidth * asset.pixelHeight)
            totalPixels += pixels
            
            if asset.mediaType == .video {
                videoCount += 1
            } else if asset.mediaType == .image {
                imageCount += 1
                
                // Consider high resolution if > 4MP
                if pixels > 4_000_000 {
                    highResolutionCount += 1
                }
            }
        }
        
        let averagePixels = assets.isEmpty ? 0 : totalPixels / Int64(assets.count)
        let complexity = calculateComplexityScore(
            totalAssets: assets.count,
            averagePixels: averagePixels,
            highResCount: highResolutionCount,
            videoCount: videoCount
        )
        
        return BatchComplexityReport(
            totalAssets: assets.count,
            imageCount: imageCount,
            videoCount: videoCount,
            highResolutionCount: highResolutionCount,
            averagePixels: averagePixels,
            totalPixels: totalPixels,
            complexityScore: complexity
        )
    }
    
    // MARK: - Private Methods
    private func determineBatchSize(for assetCount: Int, threshold: Int) -> Int {
        if assetCount <= BatchConfiguration.defaultBatchSize {
            return assetCount
        }
        
        if assetCount > threshold {
            // Use smaller batches for large datasets to maintain responsiveness
            return min(BatchConfiguration.defaultBatchSize, threshold / 10)
        }
        
        // Calculate optimal batch size based on available memory and processing power
        let optimalSize = calculateOptimalBatchSize(for: assetCount)
        return min(optimalSize, BatchConfiguration.maxBatchSize)
    }
    
    private func calculateOptimalBatchSize(for assetCount: Int) -> Int {
        // Get device capabilities
        let deviceCapabilities = getDeviceCapabilities()
        
        // Base calculation on memory and GPU capabilities
        let memoryBasedSize = Int(deviceCapabilities.availableMemoryMB / 10) // ~10MB per asset estimate
        let gpuBasedSize = deviceCapabilities.isHighEndGPU ? 100 : 50
        
        // Use the more conservative estimate
        let baseSize = min(memoryBasedSize, gpuBasedSize)
        
        // Adjust based on total asset count
        if assetCount < 100 {
            return min(baseSize, assetCount)
        } else if assetCount < 1000 {
            return min(baseSize, BatchConfiguration.defaultBatchSize)
        } else {
            // For very large datasets, use smaller batches for better progress reporting
            return min(baseSize, 30)
        }
    }
    
    private func createSmartIncrementalBatches(from assets: [PHAsset], threshold: Int) -> [[PHAsset]] {
        // Group assets by creation date for better similarity detection
        let sortedAssets = assets.sorted { asset1, asset2 in
            guard let date1 = asset1.creationDate,
                  let date2 = asset2.creationDate else {
                return false
            }
            return date1 < date2
        }
        
        let batchSize = max(20, threshold / 20) // Create ~20 batches for incremental processing
        var batches: [[PHAsset]] = []
        
        for i in stride(from: 0, to: sortedAssets.count, by: batchSize) {
            let endIndex = min(i + batchSize, sortedAssets.count)
            let batch = Array(sortedAssets[i..<endIndex])
            batches.append(batch)
        }
        
        return batches
    }
    
    private func estimateMemoryUsage(for assets: [PHAsset]) -> Int {
        var totalMemory = 0
        
        for asset in assets {
            let pixels = asset.pixelWidth * asset.pixelHeight
            // Estimate 4 bytes per pixel (RGBA) + overhead
            let assetMemory = pixels * 4 + 1024 * 1024 // 1MB overhead per asset
            totalMemory += assetMemory
        }
        
        return totalMemory
    }
    
    private func splitBatchByMemory(_ batch: [PHAsset], memoryBudget: Int) -> [[PHAsset]] {
        var splitBatches: [[PHAsset]] = []
        var currentBatch: [PHAsset] = []
        var currentMemory = 0
        
        for asset in batch {
            let assetMemory = estimateMemoryUsage(for: [asset])
            
            if currentMemory + assetMemory > memoryBudget && !currentBatch.isEmpty {
                splitBatches.append(currentBatch)
                currentBatch = [asset]
                currentMemory = assetMemory
            } else {
                currentBatch.append(asset)
                currentMemory += assetMemory
            }
        }
        
        if !currentBatch.isEmpty {
            splitBatches.append(currentBatch)
        }
        
        return splitBatches.isEmpty ? [batch] : splitBatches
    }
    
    private func calculateComplexityScore(totalAssets: Int, averagePixels: Int64, highResCount: Int, videoCount: Int) -> Float {
        var score: Float = 0.0
        
        // Base score from asset count
        score += Float(totalAssets) * 0.1
        
        // Resolution complexity
        score += Float(averagePixels) / 1_000_000.0 * 2.0 // 2 points per megapixel
        
        // High resolution penalty
        score += Float(highResCount) * 3.0
        
        // Video processing is more complex
        score += Float(videoCount) * 5.0
        
        return score
    }
    
    private func getDeviceCapabilities() -> DeviceCapabilities {
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory
        let availableMemoryMB = Int(physicalMemory / (1024 * 1024))
        
        // Simple heuristic for GPU capability based on memory
        let isHighEndGPU = availableMemoryMB > 3000 // Assume devices with >3GB RAM have better GPUs
        
        return DeviceCapabilities(
            availableMemoryMB: availableMemoryMB,
            isHighEndGPU: isHighEndGPU
        )
    }
}

// MARK: - Supporting Models
struct BatchComplexityReport {
    let totalAssets: Int
    let imageCount: Int
    let videoCount: Int
    let highResolutionCount: Int
    let averagePixels: Int64
    let totalPixels: Int64
    let complexityScore: Float
    
    var isHighComplexity: Bool {
        return complexityScore > 100.0
    }
    
    var estimatedProcessingTimeSeconds: Int {
        // Rough estimate: 0.1 seconds per complexity point
        return Int(complexityScore * 0.1)
    }
}

private struct DeviceCapabilities {
    let availableMemoryMB: Int
    let isHighEndGPU: Bool
} 