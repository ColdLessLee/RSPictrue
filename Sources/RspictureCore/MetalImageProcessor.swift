import Foundation
import Metal
import MetalKit
import Photos
import CoreImage
import ImageIO

// MARK: - Image Feature Models
public struct ImageFeatures {
    let assetIdentifier: String
    let colorHistogram: [Float]
    let orbFeatures: [Float]
    let pHashValue: UInt64
    let width: Int
    let height: Int
}

public struct BatchFeatures {
    let features: [ImageFeatures]
    let batchSize: Int
}

// MARK: - Metal Image Processor
final class MetalImageProcessor {
    
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
                    let feature = try self?.extractFeatures(from: asset, cache: cache)
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
            throw RspictureError.metalNotSupported
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
    
    private func extractFeatures(from asset: PHAsset, cache: NSCache<NSString, NSData>) throws -> ImageFeatures {
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
        var loadError: Error?
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: 512, height: 512) // Optimize for Metal processing
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, _, _, _) in
            imageData = data
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard let data = imageData else {
            throw RspictureError.imageProcessingFailed
        }
        
        return data
    }
    
    private func extractFeaturesFromImageData(_ imageData: Data, assetIdentifier: String) throws -> ImageFeatures {
        // Create CIImage from data
        guard let ciImage = CIImage(data: imageData) else {
            throw RspictureError.imageProcessingFailed
        }
        
        // Resize for consistent processing
        let resizedImage = ciImage.resized(to: CGSize(width: 512, height: 512))
        
        // Create Metal texture
        guard let texture = try createMetalTexture(from: resizedImage) else {
            throw RspictureError.metalNotSupported
        }
        
        // Extract features using Metal compute shaders
        let colorHistogram = try computeColorHistogram(texture: texture)
        let orbFeatures = try computeORBFeatures(texture: texture)
        let pHashValue = try computePHash(texture: texture)
        
        return ImageFeatures(
            assetIdentifier: assetIdentifier,
            colorHistogram: colorHistogram,
            orbFeatures: orbFeatures,
            pHashValue: pHashValue,
            width: Int(resizedImage.extent.width),
            height: Int(resizedImage.extent.height)
        )
    }
    
    private func createMetalTexture(from ciImage: CIImage) throws -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(ciImage.extent.width),
            height: Int(ciImage.extent.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RspictureError.metalNotSupported
        }
        
        // Render CIImage to Metal texture
        ciContext.render(ciImage, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return texture
    }
    
    private func computeColorHistogram(texture: MTLTexture) throws -> [Float] {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RspictureError.metalNotSupported
        }
        
        // Create output buffer for histogram (RGB channels * 256 bins each)
        let histogramSize = 256 * 3 * MemoryLayout<Float>.size
        guard let histogramBuffer = device.makeBuffer(length: histogramSize, options: .storageModeShared) else {
            throw RspictureError.metalNotSupported
        }
        
        // Configure compute encoder
        computeEncoder.setComputePipelineState(colorHistogramPipeline)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(histogramBuffer, offset: 0, index: 0)
        
        // Dispatch threads
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let numThreadgroups = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let histogramPointer = histogramBuffer.contents().bindMemory(to: Float.self, capacity: 256 * 3)
        return Array(UnsafeBufferPointer(start: histogramPointer, count: 256 * 3))
    }
    
    private func computeORBFeatures(texture: MTLTexture) throws -> [Float] {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RspictureError.metalNotSupported
        }
        
        // Create output buffer for ORB features (500 features * 32 bytes each)
        let orbSize = 500 * 32 * MemoryLayout<Float>.size
        guard let orbBuffer = device.makeBuffer(length: orbSize, options: .storageModeShared) else {
            throw RspictureError.metalNotSupported
        }
        
        // Configure compute encoder
        computeEncoder.setComputePipelineState(orbFeaturesPipeline)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(orbBuffer, offset: 0, index: 0)
        
        // Dispatch threads
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let numThreadgroups = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let orbPointer = orbBuffer.contents().bindMemory(to: Float.self, capacity: 500 * 32)
        return Array(UnsafeBufferPointer(start: orbPointer, count: 500 * 32))
    }
    
    private func computePHash(texture: MTLTexture) throws -> UInt64 {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RspictureError.metalNotSupported
        }
        
        // Create output buffer for PHash
        guard let pHashBuffer = device.makeBuffer(length: MemoryLayout<UInt64>.size, options: .storageModeShared) else {
            throw RspictureError.metalNotSupported
        }
        
        // Configure compute encoder
        computeEncoder.setComputePipelineState(pHashPipeline)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(pHashBuffer, offset: 0, index: 0)
        
        // Dispatch threads
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let numThreadgroups = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read result
        let pHashPointer = pHashBuffer.contents().bindMemory(to: UInt64.self, capacity: 1)
        return pHashPointer.pointee
    }
    
    private func prepareFeatureDataForGPU(features: BatchFeatures) throws -> MTLBuffer {
        let batchSize = features.batchSize
        let featureSize = 256 * 3 + 500 * 32 + 1 // Histogram + ORB + PHash (as float)
        let totalSize = batchSize * featureSize * MemoryLayout<Float>.size
        
        guard let buffer = device.makeBuffer(length: totalSize, options: .storageModeShared) else {
            throw RspictureError.metalNotSupported
        }
        
        let bufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: batchSize * featureSize)
        
        for (index, feature) in features.features.enumerated() {
            let offset = index * featureSize
            
            // Copy histogram
            for (i, value) in feature.colorHistogram.enumerated() {
                bufferPointer[offset + i] = value
            }
            
            // Copy ORB features
            let orbOffset = offset + 256 * 3
            for (i, value) in feature.orbFeatures.enumerated() {
                bufferPointer[orbOffset + i] = value
            }
            
            // Copy PHash as float
            let pHashOffset = offset + 256 * 3 + 500 * 32
            bufferPointer[pHashOffset] = Float(feature.pHashValue)
        }
        
        return buffer
    }
    
    private func executeSimilarityCalculation(featureData: MTLBuffer, outputBuffer: MTLBuffer, batchSize: Int) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RspictureError.metalNotSupported
        }
        
        // Configure compute encoder
        computeEncoder.setComputePipelineState(similarityPipeline)
        computeEncoder.setBuffer(featureData, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        
        var batchSizeInt32 = Int32(batchSize)
        computeEncoder.setBytes(&batchSizeInt32, length: MemoryLayout<Int32>.size, index: 2)
        
        // Dispatch threads
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let numThreadgroups = MTLSize(
            width: (batchSize + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (batchSize + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if let error = commandBuffer.error {
            throw error
        }
    }
    
    // MARK: - Serialization Helpers
    private func serializeFeatures(_ features: ImageFeatures) throws -> Data {
        let encoder = JSONEncoder()
        let wrapper = SerializableImageFeatures(
            assetIdentifier: features.assetIdentifier,
            colorHistogram: features.colorHistogram,
            orbFeatures: features.orbFeatures,
            pHashValue: features.pHashValue,
            width: features.width,
            height: features.height
        )
        return try encoder.encode(wrapper)
    }
    
    private func deserializeFeatures(from data: Data) throws -> ImageFeatures {
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(SerializableImageFeatures.self, from: data)
        
        return ImageFeatures(
            assetIdentifier: wrapper.assetIdentifier,
            colorHistogram: wrapper.colorHistogram,
            orbFeatures: wrapper.orbFeatures,
            pHashValue: wrapper.pHashValue,
            width: wrapper.width,
            height: wrapper.height
        )
    }
}

// MARK: - Serializable Wrapper
private struct SerializableImageFeatures: Codable {
    let assetIdentifier: String
    let colorHistogram: [Float]
    let orbFeatures: [Float]
    let pHashValue: UInt64
    let width: Int
    let height: Int
}

// MARK: - CIImage Extension
private extension CIImage {
    func resized(to size: CGSize) -> CIImage {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
} 