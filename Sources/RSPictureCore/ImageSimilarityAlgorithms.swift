import Foundation
import Metal

// MARK: - Similarity Metrics
struct SimilarityMetrics {
    let histogramSimilarity: Float
    let orbSimilarity: Float
    let pHashSimilarity: Float
    let combinedScore: Float
    
    init(histogram: Float, orb: Float, pHash: Float) {
        self.histogramSimilarity = histogram
        self.orbSimilarity = orb
        self.pHashSimilarity = pHash
        
        // Weighted combination of all three algorithms
        // Weights: Histogram 30%, ORB 50%, PHash 20%
        self.combinedScore = (histogram * 0.3) + (orb * 0.5) + (pHash * 0.2)
    }
}

// MARK: - Algorithm Configuration
struct AlgorithmConfiguration {
    static let histogramBins = 256
    static let histogramSize = histogramBins * 3  // RGB三通道总直方图大小 (768)
    static let orbFeatureCount = 500
    static let orbDescriptorSize = 32
    static let orbSize = orbFeatureCount * orbDescriptorSize  // ORB特征总大小 (16000)
    static let pHashSize = 64
    
    // Similarity thresholds
    static let histogramThreshold: Float = 0.7
    static let orbThreshold: Float = 0.6
    static let pHashThreshold: Float = 0.8
    static let combinedThreshold: Float = 0.75
}

// MARK: - Image Similarity Algorithms
final class ImageSimilarityAlgorithms {
    
    // MARK: - Properties
    private let metalProcessor: MetalImageProcessor?
    
    // Cache for expensive calculations
    private var similarityCache = NSCache<NSString, NSNumber>()
    private let cacheQueue = DispatchQueue(label: "com.rspicture.similarity.cache", attributes: .concurrent)
    
    // MARK: - Initialization
    init() {
        self.metalProcessor = nil
        setupCache()
    }
    
    // MARK: - Public Interface
    func calculateSimilarities(features: BatchFeatures, using metalProcessor: MetalImageProcessor) throws -> [[Float]] {
        let batchSize = features.batchSize
        
        // Use Metal for GPU acceleration when available
        if let metalBuffer = try? metalProcessor.calculateSimilarityMatrix(features: features) {
            return try extractSimilarityMatrix(from: metalBuffer, batchSize: batchSize)
        } else {
            // Fallback to CPU calculation
            return calculateSimilaritiesCPU(features: features)
        }
    }
    
    func calculatePairwiseSimilarity(feature1: ImageFeatures, feature2: ImageFeatures) -> SimilarityMetrics {
        let cacheKey = "\(feature1.assetIdentifier)_\(feature2.assetIdentifier)"
        
        // Check cache first
        if let cachedScore = getCachedSimilarity(for: cacheKey) {
            return cachedScore
        }
        
        // Calculate histogram similarity
        let histogramSim = calculateHistogramSimilarity(
            histogram1: feature1.colorHistogram,
            histogram2: feature2.colorHistogram
        )
        
        // Calculate ORB similarity
        let orbSim = calculateORBSimilarity(
            orb1: feature1.orbFeatures,
            orb2: feature2.orbFeatures
        )
        
        // Calculate PHash similarity
        let pHashSim = calculatePHashSimilarity(
            pHash1: feature1.pHashValue,
            pHash2: feature2.pHashValue
        )
        
        let metrics = SimilarityMetrics(histogram: histogramSim, orb: orbSim, pHash: pHashSim)
        
        // Cache the result
        cacheSimilarity(metrics, for: cacheKey)
        
        return metrics
    }
    
    // MARK: - Individual Algorithm Implementations
    
    // Color Histogram Similarity (using Bhattacharyya coefficient)
    private func calculateHistogramSimilarity(histogram1: [Float], histogram2: [Float]) -> Float {
        guard histogram1.count == histogram2.count,
              !histogram1.isEmpty else { return 0.0 }
        
        // Normalize histograms
        let norm1 = normalizeHistogram(histogram1)
        let norm2 = normalizeHistogram(histogram2)
        
        // Calculate Bhattacharyya coefficient
        var sum: Float = 0.0
        for i in 0..<norm1.count {
            sum += sqrt(norm1[i] * norm2[i])
        }
        
        return max(0.0, min(1.0, sum))
    }
    
    // ORB Features Similarity (using Hamming distance for binary descriptors)
    private func calculateORBSimilarity(orb1: [Float], orb2: [Float]) -> Float {
        guard orb1.count == orb2.count,
              orb1.count == AlgorithmConfiguration.orbFeatureCount * AlgorithmConfiguration.orbDescriptorSize else {
            return 0.0
        }
        
        let featureCount = AlgorithmConfiguration.orbFeatureCount
        let descriptorSize = AlgorithmConfiguration.orbDescriptorSize
        
        var matchCount = 0
        var totalFeatures = 0
        
        // Compare each ORB feature descriptor
        for i in 0..<featureCount {
            let startIdx = i * descriptorSize
            let endIdx = startIdx + descriptorSize
            
            // Skip invalid features (all zeros)
            let descriptor1 = Array(orb1[startIdx..<endIdx])
            let descriptor2 = Array(orb2[startIdx..<endIdx])
            
            if isValidORBDescriptor(descriptor1) && isValidORBDescriptor(descriptor2) {
                let similarity = calculateDescriptorSimilarity(descriptor1, descriptor2)
                if similarity > 0.8 { // Threshold for matching features
                    matchCount += 1
                }
                totalFeatures += 1
            }
        }
        
        return totalFeatures > 0 ? Float(matchCount) / Float(totalFeatures) : 0.0
    }
    
    // Perceptual Hash Similarity (using Hamming distance)
    private func calculatePHashSimilarity(pHash1: UInt64, pHash2: UInt64) -> Float {
        let hammingDistance = calculateHammingDistance(pHash1, pHash2)
        let maxDistance = 64 // 64-bit hash
        
        // Convert to similarity score (lower distance = higher similarity)
        let similarity = Float(maxDistance - hammingDistance) / Float(maxDistance)
        return max(0.0, min(1.0, similarity))
    }
    
    // MARK: - Helper Methods
    private func setupCache() {
        similarityCache.countLimit = 1000
        similarityCache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }
    
    private func normalizeHistogram(_ histogram: [Float]) -> [Float] {
        let sum = histogram.reduce(0, +)
        guard sum > 0 else { return histogram }
        
        return histogram.map { $0 / sum }
    }
    
    private func isValidORBDescriptor(_ descriptor: [Float]) -> Bool {
        // Check if descriptor is not all zeros (invalid feature)
        return descriptor.contains { $0 != 0.0 }
    }
    
    private func calculateDescriptorSimilarity(_ desc1: [Float], _ desc2: [Float]) -> Float {
        guard desc1.count == desc2.count else { return 0.0 }
        
        // Calculate normalized correlation coefficient
        let mean1 = desc1.reduce(0, +) / Float(desc1.count)
        let mean2 = desc2.reduce(0, +) / Float(desc2.count)
        
        var numerator: Float = 0.0
        var denom1: Float = 0.0
        var denom2: Float = 0.0
        
        for i in 0..<desc1.count {
            let diff1 = desc1[i] - mean1
            let diff2 = desc2[i] - mean2
            
            numerator += diff1 * diff2
            denom1 += diff1 * diff1
            denom2 += diff2 * diff2
        }
        
        let denominator = sqrt(denom1 * denom2)
        guard denominator > 0 else { return 0.0 }
        
        let correlation = numerator / denominator
        return max(0.0, min(1.0, (correlation + 1.0) / 2.0)) // Normalize to [0,1]
    }
    
    private func calculateHammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        let xor = hash1 ^ hash2
        return xor.nonzeroBitCount
    }
    
    private func extractSimilarityMatrix(from buffer: MTLBuffer, batchSize: Int) throws -> [[Float]] {
        let bufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: batchSize * batchSize)
        var matrix: [[Float]] = []
        
        for i in 0..<batchSize {
            var row: [Float] = []
            for j in 0..<batchSize {
                let index = i * batchSize + j
                row.append(bufferPointer[index])
            }
            matrix.append(row)
        }
        
        return matrix
    }
    
    private func calculateSimilaritiesCPU(features: BatchFeatures) -> [[Float]] {
        let batchSize = features.batchSize
        var similarityMatrix = Array(repeating: Array(repeating: Float(0.0), count: batchSize), count: batchSize)
        
        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "com.rspicture.similarity.cpu", 
                                          qos: .userInitiated, 
                                          attributes: .concurrent)
        
        // Calculate similarities in parallel
        for i in 0..<batchSize {
            for j in i..<batchSize {
                group.enter()
                concurrentQueue.async { [weak self] in
                    defer { group.leave() }
                    
                    if i == j {
                        similarityMatrix[i][j] = 1.0 // Perfect similarity with itself
                    } else {
                        let feature1 = features.features[i]
                        let feature2 = features.features[j]
                        let metrics = self?.calculatePairwiseSimilarity(feature1: feature1, feature2: feature2)
                        
                        let similarity = metrics?.combinedScore ?? 0.0
                        
                        // Matrix is symmetric
                        similarityMatrix[i][j] = similarity
                        similarityMatrix[j][i] = similarity
                    }
                }
            }
        }
        
        group.wait()
        return similarityMatrix
    }
    
    // MARK: - Caching
    private func getCachedSimilarity(for key: String) -> SimilarityMetrics? {
        return cacheQueue.sync {
            guard let cachedValue = similarityCache.object(forKey: key as NSString) else {
                return nil
            }
            
            // For simplicity, we cache only the combined score
            // In a real implementation, you might cache the full metrics
            let score = cachedValue.floatValue
            return SimilarityMetrics(histogram: score, orb: score, pHash: score)
        }
    }
    
    private func cacheSimilarity(_ metrics: SimilarityMetrics, for key: String) {
        cacheQueue.async { [weak self] in
            self?.similarityCache.setObject(NSNumber(value: metrics.combinedScore), 
                                          forKey: key as NSString)
        }
    }
    
    // MARK: - Advanced Similarity Detection
    func findSimilarClusters(from similarities: [[Float]], 
                           threshold: Float = AlgorithmConfiguration.combinedThreshold) -> [[Int]] {
        let count = similarities.count
        var visited = Array(repeating: false, count: count)
        var clusters: [[Int]] = []
        
        for i in 0..<count {
            if !visited[i] {
                let cluster = performDFS(similarities: similarities, 
                                       startIndex: i, 
                                       visited: &visited, 
                                       threshold: threshold)
                if cluster.count > 1 {
                    clusters.append(cluster)
                }
            }
        }
        
        return clusters
    }
    
    private func performDFS(similarities: [[Float]], 
                          startIndex: Int, 
                          visited: inout [Bool], 
                          threshold: Float) -> [Int] {
        var cluster: [Int] = []
        var stack = [startIndex]
        
        while !stack.isEmpty {
            let current = stack.removeLast()
            
            if !visited[current] {
                visited[current] = true
                cluster.append(current)
                
                // Find all similar items
                for i in 0..<similarities.count {
                    if !visited[i] && similarities[current][i] >= threshold {
                        stack.append(i)
                    }
                }
            }
        }
        
        return cluster
    }
    
    // MARK: - Quality Assessment
    func assessSimilarityQuality(metrics: SimilarityMetrics) -> SimilarityQuality {
        let histogram = metrics.histogramSimilarity
        let orb = metrics.orbSimilarity
        let pHash = metrics.pHashSimilarity
        let combined = metrics.combinedScore
        
        // Check agreement between algorithms
        let agreement = calculateAlgorithmAgreement(histogram: histogram, orb: orb, pHash: pHash)
        
        // Determine confidence level
        let confidence: Float
        if agreement > 0.8 && combined > 0.8 {
            confidence = 0.95
        } else if agreement > 0.6 && combined > 0.6 {
            confidence = 0.8
        } else if agreement > 0.4 || combined > 0.5 {
            confidence = 0.6
        } else {
            confidence = 0.3
        }
        
        return SimilarityQuality(
            confidence: confidence,
            agreement: agreement,
            isPotentialMatch: combined >= AlgorithmConfiguration.combinedThreshold,
            strongMatch: combined >= 0.85 && agreement >= 0.7
        )
    }
    
    private func calculateAlgorithmAgreement(histogram: Float, orb: Float, pHash: Float) -> Float {
        let scores = [histogram, orb, pHash]
        let mean = scores.reduce(0, +) / Float(scores.count)
        
        // Calculate standard deviation
        let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Float(scores.count)
        let stdDev = sqrt(variance)
        
        // Lower standard deviation means higher agreement
        return max(0.0, 1.0 - (stdDev * 2.0))
    }
}

// MARK: - Supporting Models
struct SimilarityQuality {
    let confidence: Float
    let agreement: Float
    let isPotentialMatch: Bool
    let strongMatch: Bool
    
    var qualityDescription: String {
        if strongMatch {
            return "Strong Match"
        } else if isPotentialMatch {
            return "Potential Match"
        } else if confidence > 0.5 {
            return "Weak Match"
        } else {
            return "No Match"
        }
    }
} 