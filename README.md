# RspictureCore

一个高性能的Swift图像相似性检测Package，专为iOS应用设计，利用GPU并行运算提供批量多图片比对功能。

## 🚀 核心特性

- **GPU加速处理**: 利用Metal框架进行并行运算，大幅提升处理性能
- **多算法融合**: 结合颜色直方图、ORB特征和PHash算法，提供精确的相似性检测
- **智能批处理**: 自动优化批次大小，支持增量处理大量图片
- **单例模式管理**: 统一的接口设计，内置缓存和线程安全机制
- **流式输出**: 实时进度报告，支持流式结果输出
- **内存优化**: 智能内存管理，适配不同设备性能
- **线程安全**: 基于GCD的多线程设计，不阻塞主线程

## 📋 系统要求

- iOS 14.0+
- Xcode 14.0+
- Swift 5.8+
- 支持Metal的设备

## 📦 安装

### Swift Package Manager

在Xcode中添加Package依赖：

```
https://github.com/yourname/RspictureCore.git
```

或在Package.swift中添加：

```swift
dependencies: [
    .package(url: "https://github.com/yourname/RspictureCore.git", from: "1.0.0")
]
```

## 🔧 基本使用

### 1. 导入框架

```swift
import RspictureCore
import Photos
```

### 2. 请求相册权限

```swift
PHPhotoLibrary.requestAuthorization { status in
    if status == .authorized {
        // 开始处理图片
    }
}
```

### 3. 获取图片资源

```swift
let fetchOptions = PHFetchOptions()
fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

var assets: [PHAsset] = []
fetchResult.enumerateObjects { asset, _, _ in
    assets.append(asset)
}
```

### 4. 配置和启动扫描

```swift
class YourViewController: UIViewController, RspictureDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupRspicture()
    }
    
    private func setupRspicture() {
        let manager = RspictureManager.shared
        manager.setDelegate(self)
        
        // 可选：自定义配置
        let config = RspictureConfiguration(
            maxBatchSize: 50,
            memoryBudget: 100 * 1024 * 1024, // 100MB
            similarityThreshold: 0.8,
            useIncrementalProcessing: true,
            cacheSize: 50
        )
        manager.configure(with: config)
    }
    
    private func startScanning(assets: [PHAsset]) {
        RspictureManager.shared.findSimilarImages(from: assets)
    }
    
    // MARK: - RspictureDelegate
    
    func rspictureDidUpdateProgress(_ result: SimilarityResult) {
        // 更新进度UI
        let progress = result.progress.percentage
        let groups = result.similarGroups
        
        DispatchQueue.main.async {
            // 更新进度条和结果显示
        }
    }
    
    func rspictureDidComplete(_ finalResult: SimilarityResult) {
        // 处理最终结果
        let similarGroups = finalResult.similarGroups
        
        DispatchQueue.main.async {
            // 显示完成状态和结果
        }
    }
    
    func rspictureDidEncounterError(_ error: Error) {
        // 处理错误
        print("扫描出错: \(error.localizedDescription)")
    }
}
```

## 🔄 高级功能

### 增量处理

对于大量图片（>500张），系统自动启用增量处理：

```swift
let manager = RspictureManager.shared

// 检查是否建议增量处理
if manager.shouldProcessIncrementally(assetCount: assets.count) {
    print("建议使用增量处理")
}

// 预估处理时间
let estimatedTime = manager.estimateProcessingTime(for: assets)
print("预估处理时间: \(RspictureUtils.formatTimeEstimate(estimatedTime))")
```

### 设备能力检测

```swift
// 检查Metal支持
if RspictureUtils.isMetalAvailable {
    print("设备支持Metal加速")
}

// 获取内存信息
let memoryInfo = RspictureUtils.deviceMemoryInfo
print("设备内存: \(memoryInfo.totalMemoryMB)MB")
if memoryInfo.isMemoryConstrained {
    print("设备内存受限，将使用优化策略")
}
```

### 图片资源分析

```swift
// 获取高分辨率图片
let highResAssets = assets.highResolutionAssets
print("高分辨率图片: \(highResAssets.count)张")

// 按日期分组
let groupedAssets = assets.groupedByCreationDate
print("按日期分组: \(groupedAssets.keys.count)组")

// 计算总像素数
let totalPixels = assets.totalPixels
print("总像素数: \(totalPixels)")
```

### 自定义配置

```swift
let customConfig = RspictureConfiguration(
    maxBatchSize: 30,                    // 较小批次，适合低性能设备
    memoryBudget: 50 * 1024 * 1024,     // 50MB内存限制
    similarityThreshold: 0.85,           // 更严格的相似性阈值
    useIncrementalProcessing: true,      // 启用增量处理
    cacheSize: 30                        // 30MB缓存
)

RspictureManager.shared.configure(with: customConfig)
```

### 日志和调试

```swift
// 启用日志
RspictureLogger.isEnabled = true
RspictureLogger.logLevel = .info

// 手动记录日志
RspictureLogger.log("开始处理图片", level: .info)
```

## 📊 算法详解

### 颜色直方图算法
- 计算RGB三通道各256个bin的直方图
- 使用Bhattacharyya系数进行相似性比较
- 权重占比：30%

### ORB特征算法
- 检测图像关键点和二进制描述符
- 支持500个特征点，每个32字节描述符
- 使用汉明距离计算相似性
- 权重占比：50%

### PHash算法
- 64位感知哈希，基于DCT变换
- 通过汉明距离计算相似性
- 权重占比：20%

## 🎯 性能优化

### GPU加速
- 利用Metal compute shader进行并行计算
- 支持同时处理多张图片的特征提取
- 相似性矩阵计算完全在GPU上完成

### 内存管理
- 智能缓存机制，支持LRU淘汰策略
- 根据设备内存动态调整批次大小
- 及时释放不需要的图像数据

### 线程优化
- 主线程不被阻塞，所有计算在后台进行
- 使用GCD进行任务调度和并发控制
- 结果通过delegate在主线程回调

## ⚠️ 注意事项

1. **相册权限**: 必须获得相册访问权限才能使用
2. **Metal支持**: 需要支持Metal的设备，旧设备会自动降级到CPU处理
3. **内存使用**: 大量高分辨率图片可能消耗较多内存
4. **处理时间**: 图片数量和分辨率直接影响处理时间
5. **单例限制**: 同时只能有一个扫描任务，新任务会覆盖旧任务

## 🔧 故障排除

### 常见问题

**Q: 扫描速度很慢？**
A: 检查设备是否支持Metal，降低批次大小，或使用增量处理。

**Q: 内存不足错误？**
A: 减小内存预算配置，降低批次大小，或清理缓存。

**Q: 找不到相似图片？**
A: 调整相似性阈值，检查图片质量是否过低。

**Q: Metal相关错误？**
A: 确保设备支持Metal，检查着色器文件是否正确包含。

### 错误码说明

- `alreadyProcessing`: 已有扫描任务在进行
- `metalNotSupported`: 设备不支持Metal
- `imageProcessingFailed`: 图像处理失败
- `cacheError`: 缓存操作失败


*本Package专为iOS平台优化，充分利用了Metal框架的GPU加速能力，为大规模图像相似性检测提供了高效的解决方案。* 