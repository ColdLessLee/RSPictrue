import Foundation
import Photos
import UIKit
import RSP

// MARK: - RSP Usage Example
/// 这个示例展示了如何使用RSP统一接口来访问图片处理和资产管理功能

class RSPUsageExample {
    
    // MARK: - Basic Setup
    func setupExample() {
        // 1. 初始化RSP系统
        let config = RSP.Config(
            coreConfiguration: RSPictureConfiguration(
                maxBatchSize: 100,
                similarityThreshold: 0.85,
                useIncrementalProcessing: true
            ),
            enableKingfisherCache: true,
            enableLogging: true
        )
        
        RSP.initialize(with: config)
        
        // 2. 设置日志级别
        RSP.setLogLevel(.info)
        
        print("RSP系统初始化完成")
        print("Metal支持: \(RSP.isMetalAvailable)")
        print("设备内存信息: \(RSP.deviceMemoryInfo)")
    }
    
    // MARK: - Asset Management Examples
    func assetManagementExamples() async {
        do {
            // 1. 获取所有图片资产
            let allImages = try await RSP.fetchAllAssets(for: .image)
            print("总共找到 \(allImages.count) 张图片")
            
            // 2. 分页获取资产
            let pageResult = try await RSP.fetchAssets(for: .image, offset: 0, limit: 20)
            print("分页结果: \(pageResult.assets.count)/\(pageResult.totalCount), 还有更多: \(pageResult.hasMore)")
            
            // 3. 获取高分辨率图片
            let highResImages = try await RSP.getHighResolutionAssets()
            print("高分辨率图片数量: \(highResImages.count)")
            
            // 4. 按日期分组
            let groupedAssets = try await RSP.getAssetsGroupedByDate(for: .image)
            print("按日期分组结果: \(groupedAssets.keys.count) 个日期组")
            
            // 5. 刷新缓存
            let refreshedAssets = try await RSP.refreshAssets(for: .image)
            print("刷新后的资产数量: \(refreshedAssets.count)")
            
        } catch {
            print("资产管理错误: \(error)")
        }
    }
    
    // MARK: - Image Processing Examples
    func imageProcessingExamples() async {
        do {
            // 1. 获取图片资产
            let assets = try await RSP.fetchAllAssets(for: .image)
            guard !assets.isEmpty else {
                print("没有找到图片资产")
                return
            }
            
            // 2. 估算处理时间
            let estimatedTime = RSP.estimateProcessingTime(for: assets)
            print("预估处理时间: \(RSP.formatTimeEstimate(estimatedTime))")
            
            // 3. 检查是否应该使用增量处理
            let shouldUseIncremental = RSP.shouldProcessIncrementally(assetCount: assets.count)
            print("建议使用增量处理: \(shouldUseIncremental)")
            
            // 4. 批量处理图片（带进度监控）
            let processingStream = RSP.batchProcessImages(assets)
            
            for try await progress in processingStream {
                let formattedProgress = RSP.formatProgress(progress)
                print("处理进度: \(formattedProgress)")
                
                // 可以在这里更新UI进度条
                DispatchQueue.main.async {
                    // updateProgressBar(progress.percentage)
                }
            }
            
            // 5. 扫描相似图片
            let similarityResults = try await RSP.scanSimilarImages(from: Array(assets.prefix(50)))
            print("找到 \(similarityResults.count) 组相似图片")
            
            // 6. 快速扫描所有图片
            let allSimilarResults = try await RSP.scanAllImages()
            print("全部扫描结果: \(allSimilarResults.count) 组")
            
        } catch {
            print("图片处理错误: \(error)")
        }
    }
    
    // MARK: - Image Loading Examples
    func imageLoadingExamples() async {
        do {
            // 1. 获取一些图片资产
            let assets = try await RSP.fetchAllAssets(for: .image)
            guard let firstAsset = assets.first else {
                print("没有找到图片资产")
                return
            }
            
            // 2. 加载缩略图
            let thumbnailImage = try await RSP.loadImage(
                from: firstAsset,
                targetSize: CGSize(width: 200, height: 200)
            )
            
            if let thumbnail = thumbnailImage {
                print("成功加载缩略图: \(thumbnail.size)")
            }
            
            // 3. 加载原始尺寸图片
            let originalImage = try await RSP.loadOriginalImage(from: firstAsset)
            
            if let original = originalImage {
                print("成功加载原始图片: \(original.size)")
            }
            
        } catch {
            print("图片加载错误: \(error)")
        }
    }
    
    // MARK: - Batch Operations Examples
    func batchOperationsExamples() async {
        do {
            // 1. 获取一些资产
            let assets = try await RSP.fetchAllAssets(for: .image)
            let assetIds = Array(assets.prefix(5)).map { $0.localIdentifier }
            
            guard !assetIds.isEmpty else {
                print("没有找到资产ID")
                return
            }
            
            // 2. 通过ID获取资产
            let fetchResult = try await RSP.fetchAssets(withIds: assetIds)
            print("成功获取: \(fetchResult.successfulIds.count), 失败: \(fetchResult.failedIds.count)")
            
            // 3. 批量收藏（需要用户授权）
            let favoriteResult = try await RSP.favoriteAssets(withIds: assetIds)
            print("收藏结果 - 成功: \(favoriteResult.successfulIds.count), 失败: \(favoriteResult.failedIds.count)")
            
            // 4. 批量取消收藏
            let unfavoriteResult = try await RSP.unfavoriteAssets(withIds: assetIds)
            print("取消收藏结果 - 成功: \(unfavoriteResult.successfulIds.count), 失败: \(unfavoriteResult.failedIds.count)")
            
            // 注意：删除操作需要谨慎使用
            // let deleteResult = try await RSP.deleteAssets(withIds: assetIds)
            
        } catch {
            print("批量操作错误: \(error)")
        }
    }
    
    // MARK: - Progress Delegate Example
    class ProgressDelegate: RSPictureDelegate {
        func rspictureDidStart(_ manager: RSPictureManager) {
            print("扫描开始")
        }
        
        func rspicture(_ manager: RSPictureManager, didUpdateProgress progress: ScanProgress) {
            let formatted = RSP.formatProgress(progress)
            print("扫描进度更新: \(formatted)")
        }
        
        func rspicture(_ manager: RSPictureManager, didFindSimilarGroup group: SimilarityResult) {
            print("发现相似组: \(group.assets.count) 张图片")
        }
        
        func rspictureDidComplete(_ manager: RSPictureManager, results: [SimilarityResult]) {
            print("扫描完成，共找到 \(results.count) 组相似图片")
        }
        
        func rspicture(_ manager: RSPictureManager, didFailWithError error: Error) {
            print("扫描失败: \(error)")
        }
    }
    
    func delegateExample() async {
        do {
            let assets = try await RSP.fetchAllAssets(for: .image)
            let delegate = ProgressDelegate()
            
            let results = try await RSP.scanSimilarImages(from: assets, delegate: delegate)
            print("最终结果: \(results.count) 组相似图片")
            
        } catch {
            print("代理示例错误: \(error)")
        }
    }
    
    // MARK: - Complete Example
    func runCompleteExample() async {
        print("=== RSP 完整使用示例 ===")
        
        // 1. 设置
        setupExample()
        
        // 2. 资产管理
        print("\n--- 资产管理示例 ---")
        await assetManagementExamples()
        
        // 3. 图片处理
        print("\n--- 图片处理示例 ---")
        await imageProcessingExamples()
        
        // 4. 图片加载
        print("\n--- 图片加载示例 ---")
        await imageLoadingExamples()
        
        // 5. 批量操作
        print("\n--- 批量操作示例 ---")
        await batchOperationsExamples()
        
        // 6. 代理示例
        print("\n--- 代理示例 ---")
        await delegateExample()
        
        print("\n=== 示例完成 ===")
    }
}

// MARK: - Usage in SwiftUI View
import SwiftUI

struct RSPExampleView: View {
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var statusMessage = "准备就绪"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("RSP 示例应用")
                .font(.title)
                .fontWeight(.bold)
            
            VStack {
                Text(statusMessage)
                    .foregroundColor(.secondary)
                
                if isProcessing {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            .padding()
            
            Button("开始扫描相似图片") {
                Task {
                    await startSimilarityScanning()
                }
            }
            .disabled(isProcessing)
            
            Button("运行完整示例") {
                Task {
                    await runFullExample()
                }
            }
            .disabled(isProcessing)
        }
        .padding()
        .onAppear {
            setupRSP()
        }
    }
    
    private func setupRSP() {
        RSP.initialize()
        statusMessage = "RSP 已初始化"
    }
    
    private func startSimilarityScanning() async {
        isProcessing = true
        statusMessage = "正在扫描..."
        
        do {
            let assets = try await RSP.fetchAllAssets(for: .image)
            
            // 使用批量处理来监控进度
            let processingStream = RSP.batchProcessImages(assets)
            
            for try await scanProgress in processingStream {
                await MainActor.run {
                    progress = Double(scanProgress.percentage)
                    statusMessage = RSP.formatProgress(scanProgress)
                }
            }
            
            await MainActor.run {
                statusMessage = "扫描完成"
                isProcessing = false
            }
            
        } catch {
            await MainActor.run {
                statusMessage = "扫描失败: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    private func runFullExample() async {
        let example = RSPUsageExample()
        await example.runCompleteExample()
    }
} 