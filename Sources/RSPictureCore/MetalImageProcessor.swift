import Foundation
import Metal
import MetalKit
import Photos
import CoreImage
import ImageIO
import UIKit

// MARK: - Image Feature Models
public struct ImageFeatures: Sendable {
    let assetIdentifier: String
    let colorHistogram: [Float]
    let orbFeatures: [Float]
    let pHashValue: UInt64
    let width: Int
    let height: Int
}

public struct BatchFeatures: Sendable {
    let features: [ImageFeatures]
    let batchSize: Int
}

// MARK: - Metal Image Processor
@available(iOS 14.0, *)
final class MetalImageProcessor: @unchecked Sendable {
    
    // MARK: - Properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Compute pipeline states
    private var colorHistogramPipeline: MTLComputePipelineState!
    private var orbFeaturesPipeline: MTLComputePipelineState!
    private var pHashPipeline: MTLComputePipelineState!
    private var similarityPipeline: MTLComputePipelineState!
    
    // Core Image context for image processing
    private let ciContext: CIContext
    
    // Thread safety
    private let processingQueue = DispatchQueue(label: "com.rspicture.metal", qos: .userInitiated)
    private let semaphore = DispatchSemaphore(value: 4) // Limit concurrent operations
    
    // MARK: - Initialization
    init(device: MTLDevice) {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = commandQueue
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library")
        }
        self.library = library
        
        // Initialize Core Image context with Metal
        self.ciContext = CIContext(mtlDevice: device)
        
        // Setup compute pipelines
        setupComputePipelines()
    }
    
    // MARK: - Public Methods
    func extractBatchFeatures(from assets: [PHAsset], cache: NSCache<NSString, NSData>) throws -> BatchFeatures {
        let group = DispatchGroup()
        var features: [ImageFeatures] = Array(repeating: ImageFeatures(assetIdentifier: "", colorHistogram: [], orbFeatures: [], pHashValue: 0, width: 0, height: 0), count: assets.count)
        var processingErrors: [Error] = []
        let errorQueue = DispatchQueue(label: "com.rspicture.metal.error", qos: .userInitiated)
        
        // Create a sendable cache wrapper
        let sendableCache = SendableCacheWrapper(cache: cache)
        
        // Process assets in parallel
        for (index, asset) in assets.enumerated() {
            group.enter()
            semaphore.wait()
            
            processingQueue.async { [weak self] in
                defer {
                    self?.semaphore.signal()
                    group.leave()
                }
                
                do {
                    let feature = try self?.extractFeatures(from: asset, cache: sendableCache)
                    if let feature = feature {
                        features[index] = feature
                    }
                } catch {
                    errorQueue.sync {
                        processingErrors.append(error)
                    }
                }
            }
        }
        
        group.wait()
        
        // Check for errors
        if !processingErrors.isEmpty {
            throw processingErrors.first!
        }
        
        return BatchFeatures(features: features, batchSize: assets.count)
    }
    
    func calculateSimilarityMatrix(features: BatchFeatures) throws -> MTLBuffer {
        let batchSize = features.batchSize
        let matrixSize = batchSize * batchSize
        
        guard let buffer = device.makeBuffer(length: matrixSize * MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        // Prepare feature data for GPU
        let featureData = try prepareFeatureDataForGPU(features: features)
        
        // Execute similarity calculation on GPU
        try executeSimilarityCalculation(featureData: featureData, outputBuffer: buffer, batchSize: batchSize)
        
        return buffer
    }
    
    // MARK: - Private Methods
    private func setupComputePipelines() {
        do {
            // Color Histogram Pipeline
            if let colorHistogramFunction = library.makeFunction(name: "compute_color_histogram") {
                colorHistogramPipeline = try device.makeComputePipelineState(function: colorHistogramFunction)
            }
            
            // ORB Features Pipeline
            if let orbFunction = library.makeFunction(name: "compute_orb_features") {
                orbFeaturesPipeline = try device.makeComputePipelineState(function: orbFunction)
            }
            
            // PHash Pipeline
            if let pHashFunction = library.makeFunction(name: "compute_phash") {
                pHashPipeline = try device.makeComputePipelineState(function: pHashFunction)
            }
            
            // Similarity Pipeline
            if let similarityFunction = library.makeFunction(name: "compute_similarity") {
                similarityPipeline = try device.makeComputePipelineState(function: similarityFunction)
            }
            
        } catch {
            fatalError("Failed to create compute pipeline states: \(error)")
        }
    }
    
    private func extractFeatures(from asset: PHAsset, cache: SendableCacheWrapper) throws -> ImageFeatures {
        let cacheKey = asset.localIdentifier as NSString
        
        // Check cache first
        if let cachedData = cache.object(forKey: cacheKey) {
            return try deserializeFeatures(from: cachedData as Data)
        }
        
        // Load image data
        let imageData = try loadImageData(from: asset)
        
        // Extract features using Metal
        let features = try extractFeaturesFromImageData(imageData, assetIdentifier: asset.localIdentifier)
        
        // Cache the result
        let serializedData = try serializeFeatures(features)
        cache.setObject(serializedData as NSData, forKey: cacheKey)
        
        return features
    }
    
    private func loadImageData(from asset: PHAsset) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var imageData: Data?
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        // Use iOS compatible method
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, _, _, _) in
            imageData = data
            semaphore.signal()
        }
        semaphore.wait()

        guard let data = imageData else {
            throw RSPictureError.imageProcessingFailed
        }
        
        return data
    }
    
    private func extractFeaturesFromImageData(_ imageData: Data, assetIdentifier: String) throws -> ImageFeatures {
        // Create CIImage from data
        guard let ciImage = CIImage(data: imageData) else {
            throw RSPictureError.imageProcessingFailed
        }
        
        // Create texture from CIImage
        guard let texture = try? createTextureFromCIImage(ciImage) else {
            throw RSPictureError.imageProcessingFailed
        }
        
        // Extract features using Metal compute shaders
        let colorHistogram = try extractColorHistogram(from: texture)
        let orbFeatures = try extractORBFeatures(from: texture)
        let pHashValue = try extractPHash(from: texture)
        
        return ImageFeatures(
            assetIdentifier: assetIdentifier,
            colorHistogram: colorHistogram,
            orbFeatures: orbFeatures,
            pHashValue: pHashValue,
            width: Int(ciImage.extent.width),
            height: Int(ciImage.extent.height)
        )
    }
    
    // MARK: - Helper Methods
    private func createTextureFromCIImage(_ ciImage: CIImage) throws -> MTLTexture {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(ciImage.extent.width),
            height: Int(ciImage.extent.height),
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw RSPictureError.metalNotSupported
        }
        
        ciContext.render(ciImage, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: colorSpace)
        
        return texture
    }
    
    private func extractColorHistogram(from texture: MTLTexture) throws -> [Float] {
        let histogramSize = AlgorithmConfiguration.histogramSize // RGB histogram bins
        
        guard let buffer = device.makeBuffer(length: histogramSize * MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RSPictureError.metalNotSupported
        }
        
        encoder.setComputePipelineState(colorHistogramPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (texture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (texture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let bufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: histogramSize)
        return Array(UnsafeBufferPointer(start: bufferPointer, count: histogramSize))
    }
    
    private func extractORBFeatures(from texture: MTLTexture) throws -> [Float] {
        let orbSize = AlgorithmConfiguration.orbSize // ORB feature vector size
        
        guard let buffer = device.makeBuffer(length: orbSize * MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RSPictureError.metalNotSupported
        }
        
        encoder.setComputePipelineState(orbFeaturesPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (texture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (texture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let bufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: orbSize)
        return Array(UnsafeBufferPointer(start: bufferPointer, count: orbSize))
    }
    
    private func extractPHash(from texture: MTLTexture) throws -> UInt64 {
        guard let buffer = device.makeBuffer(length: MemoryLayout<UInt64>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RSPictureError.metalNotSupported
        }
        
        encoder.setComputePipelineState(pHashPipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroupsPerGrid = MTLSize(width: 1, height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return buffer.contents().load(as: UInt64.self)
    }
    
    private func prepareFeatureDataForGPU(features: BatchFeatures) throws -> MTLBuffer {
        let histogramSize = AlgorithmConfiguration.histogramSize
        let orbSize = AlgorithmConfiguration.orbSize
        let featureSize = histogramSize + orbSize + 2 // +2 for pHash (stored as 2 floats)
        let totalSize = features.batchSize * featureSize
        
        guard let buffer = device.makeBuffer(length: totalSize * MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        let bufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: totalSize)
        
        for (index, feature) in features.features.enumerated() {
            let offset = index * featureSize
            
            // Copy histogram
            for i in 0..<histogramSize {
                bufferPointer[offset + i] = i < feature.colorHistogram.count ? feature.colorHistogram[i] : 0.0
            }
            
            // Copy ORB features
            for i in 0..<orbSize {
                bufferPointer[offset + histogramSize + i] = i < feature.orbFeatures.count ? feature.orbFeatures[i] : 0.0
            }
            
            // Copy pHash (as 2 floats)
            let pHashLow = Float(feature.pHashValue & 0xFFFFFFFF)
            let pHashHigh = Float((feature.pHashValue >> 32) & 0xFFFFFFFF)
            bufferPointer[offset + histogramSize + orbSize] = pHashLow
            bufferPointer[offset + histogramSize + orbSize + 1] = pHashHigh
        }
        
        return buffer
    }
    
    private func executeSimilarityCalculation(featureData: MTLBuffer, outputBuffer: MTLBuffer, batchSize: Int) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RSPictureError.metalNotSupported
        }
        
        guard let batchSizeBuffer = device.makeBuffer(bytes: [UInt32(batchSize)], length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            throw RSPictureError.metalNotSupported
        }
        
        encoder.setComputePipelineState(similarityPipeline)
        encoder.setBuffer(featureData, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(batchSizeBuffer, offset: 0, index: 2)
        
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (batchSize + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (batchSize + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func serializeFeatures(_ features: ImageFeatures) throws -> Data {
        return try JSONEncoder().encode(features)
    }
    
    private func deserializeFeatures(from data: Data) throws -> ImageFeatures {
        return try JSONDecoder().decode(ImageFeatures.self, from: data)
    }
}

// MARK: - Sendable Cache Wrapper
private final class SendableCacheWrapper: @unchecked Sendable {
    private let cache: NSCache<NSString, NSData>
    
    init(cache: NSCache<NSString, NSData>) {
        self.cache = cache
    }
    
    func object(forKey key: NSString) -> NSData? {
        return cache.object(forKey: key)
    }
    
    func setObject(_ object: NSData, forKey key: NSString) {
        cache.setObject(object, forKey: key)
    }
}

// MARK: - ImageFeatures Codable Extension
extension ImageFeatures: Codable {}

// MARK: - CIImage Extension
private extension CIImage {
    func resized(to size: CGSize) -> CIImage {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
} 
