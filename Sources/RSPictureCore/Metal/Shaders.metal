#include <metal_stdlib>
using namespace metal;

// Constants - 保持与Swift代码一致
constant int HISTOGRAM_BINS = 256;  // 每个颜色通道的直方图bins数量
constant int HISTOGRAM_SIZE = HISTOGRAM_BINS * 3;  // RGB三通道总直方图大小 (768)
constant int ORB_FEATURE_COUNT = 500;
constant int ORB_DESCRIPTOR_SIZE = 32;

// Color Histogram Computation
kernel void compute_color_histogram(texture2d<float, access::read> inputTexture [[texture(0)]],
                                   device float* histogram [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    float4 color = inputTexture.read(gid);
    
    uint r = uint(color.r * 255.0);
    uint g = uint(color.g * 255.0);
    uint b = uint(color.b * 255.0);
    
    r = min(r, uint(HISTOGRAM_BINS - 1));
    g = min(g, uint(HISTOGRAM_BINS - 1));
    b = min(b, uint(HISTOGRAM_BINS - 1));
    
    atomic_fetch_add_explicit((device atomic_uint*)&histogram[r], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&histogram[HISTOGRAM_BINS + g], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&histogram[HISTOGRAM_BINS * 2 + b], 1, memory_order_relaxed);
}

// ORB Feature Detection
kernel void compute_orb_features(texture2d<float, access::read> inputTexture [[texture(0)]],
                                device float* orbFeatures [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    float4 color = inputTexture.read(gid);
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    float2 texCoord = float2(gid) / float2(inputTexture.get_width(), inputTexture.get_height());
    
    float center = gray;
    float responses[8];
    
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * M_PI_F / 4.0;
        float2 offset = float2(cos(angle), sin(angle)) * 0.01;
        
        uint2 samplePos = uint2((texCoord + offset) * float2(inputTexture.get_width(), inputTexture.get_height()));
        samplePos = clamp(samplePos, uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
        
        float4 sampleColor = inputTexture.read(samplePos);
        responses[i] = dot(sampleColor.rgb, float3(0.299, 0.587, 0.114));
    }
    
    float cornerResponse = 0.0;
    for (int i = 0; i < 8; i++) {
        cornerResponse += abs(responses[i] - center);
    }
    
    if (cornerResponse > 0.1) {
        uint featureIndex = gid.y * inputTexture.get_width() + gid.x;
        if (featureIndex < ORB_FEATURE_COUNT) {
            orbFeatures[featureIndex * ORB_DESCRIPTOR_SIZE + 0] = float(gid.x);
            orbFeatures[featureIndex * ORB_DESCRIPTOR_SIZE + 1] = float(gid.y);
            orbFeatures[featureIndex * ORB_DESCRIPTOR_SIZE + 2] = cornerResponse;
            
            for (int i = 3; i < ORB_DESCRIPTOR_SIZE; i++) {
                float angle = float(i - 3) * M_PI_F / float(ORB_DESCRIPTOR_SIZE - 3);
                float2 offset = float2(cos(angle), sin(angle)) * 0.02;
                
                uint2 samplePos = uint2((texCoord + offset) * float2(inputTexture.get_width(), inputTexture.get_height()));
                samplePos = clamp(samplePos, uint2(0), uint2(inputTexture.get_width() - 1, inputTexture.get_height() - 1));
                
                float4 sampleColor = inputTexture.read(samplePos);
                float sampleGray = dot(sampleColor.rgb, float3(0.299, 0.587, 0.114));
                
                orbFeatures[featureIndex * ORB_DESCRIPTOR_SIZE + i] = (sampleGray > center) ? 1.0 : 0.0;
            }
        }
    }
}

// PHash Computation
kernel void compute_phash(texture2d<float, access::read> inputTexture [[texture(0)]],
                         device uint64_t* pHashResult [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= 8 || gid.y >= 8) {
        return;
    }
    
    uint2 scaledPos = uint2(
        (gid.x * inputTexture.get_width()) / 8,
        (gid.y * inputTexture.get_height()) / 8
    );
    
    float4 color = inputTexture.read(scaledPos);
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    threadgroup float sharedData[64];
    uint linearIndex = gid.y * 8 + gid.x;
    sharedData[linearIndex] = gray;
    
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    if (gid.x == 0 && gid.y == 0) {
        float dctValues[64];
        
        for (int u = 0; u < 8; u++) {
            for (int v = 0; v < 8; v++) {
                float sum = 0.0;
                for (int x = 0; x < 8; x++) {
                    for (int y = 0; y < 8; y++) {
                        float cosU = cos((2 * x + 1) * u * M_PI_F / 16.0);
                        float cosV = cos((2 * y + 1) * v * M_PI_F / 16.0);
                        sum += sharedData[y * 8 + x] * cosU * cosV;
                    }
                }
                
                float alpha = (u == 0) ? 1.0 / sqrt(2.0) : 1.0;
                float beta = (v == 0) ? 1.0 / sqrt(2.0) : 1.0;
                dctValues[u * 8 + v] = 0.25 * alpha * beta * sum;
            }
        }
        
        float average = 0.0;
        for (int i = 1; i < 64; i++) {
            average += dctValues[i];
        }
        average /= 63.0;
        
        uint64_t hash = 0;
        for (int i = 0; i < 64; i++) {
            if (dctValues[i] > average) {
                hash |= (1ULL << i);
            }
        }
        
        *pHashResult = hash;
    }
}

// Similarity Computation
kernel void compute_similarity(device const float* featureData [[buffer(0)]],
                              device float* similarityMatrix [[buffer(1)]],
                              constant uint& batchSize [[buffer(2)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= batchSize || gid.y >= batchSize) {
        return;
    }
    
    uint i = gid.x;
    uint j = gid.y;
    
    if (i > j) {
        return;
    }
    
    if (i == j) {
        similarityMatrix[i * batchSize + j] = 1.0;
        return;
    }
    
    const int histogramSize = HISTOGRAM_SIZE;  // 使用常量而非硬编码
    const int orbSize = ORB_FEATURE_COUNT * ORB_DESCRIPTOR_SIZE;  // 使用常量计算
    const int featureSize = histogramSize + orbSize + 2; // +2 for pHash (stored as 2 floats)
    
    device const float* features1 = &featureData[i * featureSize];
    device const float* features2 = &featureData[j * featureSize];
    
    // Histogram similarity
    float histogramSim = 0.0;
    float sum1 = 0.0, sum2 = 0.0;
    
    for (int k = 0; k < histogramSize; k++) {
        sum1 += features1[k];
        sum2 += features2[k];
    }
    
    if (sum1 > 0.0 && sum2 > 0.0) {
        for (int k = 0; k < histogramSize; k++) {
            float norm1 = features1[k] / sum1;
            float norm2 = features2[k] / sum2;
            histogramSim += sqrt(norm1 * norm2);
        }
    }
    
    // ORB similarity
    float orbSim = 0.0;
    int validFeatures = 0;
    
    for (int f = 0; f < ORB_FEATURE_COUNT; f++) {
        int baseIdx = histogramSize + f * ORB_DESCRIPTOR_SIZE;
        
        bool valid1 = false, valid2 = false;
        for (int k = 0; k < ORB_DESCRIPTOR_SIZE; k++) {
            if (features1[baseIdx + k] != 0.0) valid1 = true;
            if (features2[baseIdx + k] != 0.0) valid2 = true;
        }
        
        if (valid1 && valid2) {
            float correlation = 0.0;
            float mean1 = 0.0, mean2 = 0.0;
            
            for (int k = 0; k < ORB_DESCRIPTOR_SIZE; k++) {
                mean1 += features1[baseIdx + k];
                mean2 += features2[baseIdx + k];
            }
            mean1 /= ORB_DESCRIPTOR_SIZE;
            mean2 /= ORB_DESCRIPTOR_SIZE;
            
            float numerator = 0.0, denom1 = 0.0, denom2 = 0.0;
            for (int k = 0; k < ORB_DESCRIPTOR_SIZE; k++) {
                float diff1 = features1[baseIdx + k] - mean1;
                float diff2 = features2[baseIdx + k] - mean2;
                numerator += diff1 * diff2;
                denom1 += diff1 * diff1;
                denom2 += diff2 * diff2;
            }
            
            float denominator = sqrt(denom1 * denom2);
            if (denominator > 0.0) {
                correlation = (numerator / denominator + 1.0) / 2.0;
                if (correlation > 0.8) {
                    orbSim += 1.0;
                }
            }
            validFeatures++;
        }
    }
    
    orbSim = (validFeatures > 0) ? (orbSim / validFeatures) : 0.0;
    
    // PHash similarity
    // pHash is stored as two consecutive floats (64 bits total)
    uint32_t pHash1_low = as_type<uint32_t>(features1[histogramSize + orbSize]);
    uint32_t pHash1_high = as_type<uint32_t>(features1[histogramSize + orbSize + 1]);
    uint64_t pHash1 = (uint64_t(pHash1_high) << 32) | uint64_t(pHash1_low);
    
    uint32_t pHash2_low = as_type<uint32_t>(features2[histogramSize + orbSize]);
    uint32_t pHash2_high = as_type<uint32_t>(features2[histogramSize + orbSize + 1]);
    uint64_t pHash2 = (uint64_t(pHash2_high) << 32) | uint64_t(pHash2_low);
    
    uint64_t xorResult = pHash1 ^ pHash2;
    int hammingDistance = popcount(xorResult);
    float pHashSim = float(64 - hammingDistance) / 64.0;
    
    // Combined similarity
    float combinedSimilarity = (histogramSim * 0.3) + (orbSim * 0.5) + (pHashSim * 0.2);
    
    similarityMatrix[i * batchSize + j] = combinedSimilarity;
    similarityMatrix[j * batchSize + i] = combinedSimilarity;
} 
