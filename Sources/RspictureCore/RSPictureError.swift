import Foundation

// MARK: - Error Types
public enum RSPictureError: LocalizedError {
    case alreadyProcessing
    case metalNotSupported
    case imageProcessingFailed
    case cacheError
    case photosAccessDenied
    case assetNotFound
    case batchOperationFailed
    case invalidOffset
    case imageLoadingFailed
    
    public var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "Another processing operation is already in progress"
        case .metalNotSupported:
            return "Metal is not supported on this device"
        case .imageProcessingFailed:
            return "Failed to process images"
        case .cacheError:
            return "Cache operation failed"
        case .photosAccessDenied:
            return "Photos access is denied. Please grant permission in Settings."
        case .assetNotFound:
            return "The specified asset could not be found."
        case .batchOperationFailed:
            return "Batch operation failed to complete."
        case .invalidOffset:
            return "Invalid offset provided for pagination."
        case .imageLoadingFailed:
            return "Failed to load image from asset."
        }
    }
} 