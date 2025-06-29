import Foundation
import Photos

// MARK: - Public Interface
@_exported import Foundation
@_exported import Photos

// Export main manager
public typealias RSPictureManager = RSPictureCore.RSPictureManager

// Export delegate protocol
public typealias RSPictureDelegate = RSPictureCore.RSPictureDelegate

// Export result types
public typealias ScanProgress = RSPictureCore.ScanProgress
public typealias SimilarityResult = RSPictureCore.SimilarityResult

// Export error types
public typealias RSPictureError = RSPictureCore.RSPictureError

// MARK: - Configuration
public struct RSPictureConfiguration {
    /// Maximum number of assets to process in a single batch
    public let maxBatchSize: Int
    
    /// Memory budget in bytes for image processing
    public let memoryBudget: Int
    
    /// Similarity threshold for grouping images (0.0 - 1.0)
    public let similarityThreshold: Float
    
    /// Whether to use incremental processing for large datasets
    public let useIncrementalProcessing: Bool
    
    /// Cache size limit in MB
    public let cacheSize: Int
    
    public init(maxBatchSize: Int = 50,
                memoryBudget: Int = 100 * 1024 * 1024, // 100MB
                similarityThreshold: Float = 0.8,
                useIncrementalProcessing: Bool = true,
                cacheSize: Int = 50) {
        self.maxBatchSize = maxBatchSize
        self.memoryBudget = memoryBudget
        self.similarityThreshold = similarityThreshold
        self.useIncrementalProcessing = useIncrementalProcessing
        self.cacheSize = cacheSize
    }
    
    public static let `default` = RSPictureConfiguration()
}

// MARK: - Convenience Extensions
public extension RSPictureManager {
    /// Configure the manager with custom settings
    func configure(with configuration: RSPictureConfiguration) {
        // Implementation would be added to configure internal components
        // For now, this is a placeholder for future configuration options
    }
    
    /// Quick method to check if processing is recommended for the given asset count
    func shouldProcessIncrementally(assetCount: Int) -> Bool {
        return assetCount > 500
    }
    
    /// Estimate processing time for the given assets
    func estimateProcessingTime(for assets: [PHAsset]) -> TimeInterval {
        let complexity = batchProcessor.analyzeAssetComplexity(assets)
        return TimeInterval(complexity.estimatedProcessingTimeSeconds)
    }
}

public extension Array where Element == PHAsset {
    /// Convenience method to get total pixel count
    var totalPixels: Int64 {
        return self.reduce(0) { result, asset in
            result + Int64(asset.pixelWidth * asset.pixelHeight)
        }
    }
    
    /// Get assets that are likely high resolution
    var highResolutionAssets: [PHAsset] {
        return self.filter { asset in
            let pixels = asset.pixelWidth * asset.pixelHeight
            return pixels > 4_000_000 // > 4MP
        }
    }
    
    /// Group assets by creation date for better batch processing
    var groupedByCreationDate: [Date: [PHAsset]] {
        var groups: [Date: [PHAsset]] = [:]
        
        for asset in self {
            guard let creationDate = asset.creationDate else { continue }
            
            // Group by day
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: creationDate)
            
            if groups[dayStart] == nil {
                groups[dayStart] = []
            }
            groups[dayStart]?.append(asset)
        }
        
        return groups
    }
}

// MARK: - Utility Functions
public struct RSPictureUtils {
    /// Check if Metal is available on the current device
    public static var isMetalAvailable: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    /// Get device memory information
    public static var deviceMemoryInfo: DeviceMemoryInfo {
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory
        
        return DeviceMemoryInfo(
            totalMemoryBytes: physicalMemory,
            totalMemoryMB: Int(physicalMemory / (1024 * 1024)),
            isMemoryConstrained: physicalMemory < 2 * 1024 * 1024 * 1024 // < 2GB
        )
    }
    
    /// Format progress percentage for display
    public static func formatProgress(_ progress: ScanProgress) -> String {
        let percentage = Int(progress.percentage * 100)
        return "\(percentage)% (\(progress.processedAssets)/\(progress.totalAssets))"
    }
    
    /// Format time estimate for display
    public static func formatTimeEstimate(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Supporting Types
public struct DeviceMemoryInfo {
    public let totalMemoryBytes: UInt64
    public let totalMemoryMB: Int
    public let isMemoryConstrained: Bool
}

// MARK: - Debugging and Logging
public struct RSPictureLogger {
    public enum LogLevel {
        case debug, info, warning, error
    }
    
    public static var isEnabled = false
    public static var logLevel: LogLevel = .info
    
    public static func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        print("[\(timestamp)] [\(level)] [\(fileName):\(line)] \(function) - \(message)")
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
} 