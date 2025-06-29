Pod::Spec.new do |spec|
  spec.name          = "RSPictrue"
  spec.version       = "1.0.0"
  spec.summary       = "A powerful Swift package for image similarity detection and asset management"
  spec.description   = <<-DESC
                       RSPictrue is a comprehensive Swift package that provides advanced image similarity 
                       detection using Metal performance shaders, along with powerful photo library asset 
                       management capabilities. The package includes three main components:
                       
                       - RspictureCore: Core image processing and similarity detection
                       - AssetsService: Photo library asset management and operations
                       - RSP: Unified static interface for easy access to all functionality
                       DESC

  spec.homepage      = "https://github.com/your-username/rspictrue"
  spec.license       = { :type => "MIT", :file => "LICENSE" }
  spec.author        = { "Your Name" => "your.email@example.com" }

  spec.ios.deployment_target = "14.0"
  spec.swift_version = "5.8"

  spec.source        = { :git => "https://github.com/your-username/rspictrue.git", :tag => "#{spec.version}" }
  spec.source_files  = "Sources/**/*.swift"
  spec.resources     = "Sources/RspictureCore/Metal/**/*.metal"
  
  # Framework dependencies
  spec.frameworks    = "Foundation", "Photos", "UIKit", "Metal", "MetalKit", "AVFoundation"
  
  # Optional Kingfisher support
  spec.dependency "Kingfisher", "~> 7.0"
  
  # Subspecs for individual components
  spec.subspec 'Core' do |core|
    core.source_files = "Sources/RspictureCore/**/*.swift"
    core.resources    = "Sources/RspictureCore/Metal/**/*.metal"
    core.frameworks   = "Foundation", "Photos", "UIKit", "Metal", "MetalKit"
  end
  
  spec.subspec 'AssetsService' do |assets|
    assets.source_files = "Sources/AssetsService/**/*.swift"
    assets.dependency "RSPictrue/Core"
    assets.frameworks = "Foundation", "Photos", "UIKit", "AVFoundation"
  end
  
  spec.subspec 'RSP' do |rsp|
    rsp.source_files = "Sources/RSP/**/*.swift"
    rsp.dependency "RSPictrue/Core"
    rsp.dependency "RSPictrue/AssetsService"
    rsp.frameworks = "Foundation", "Photos", "UIKit"
  end
  
  # Default subspecs
  spec.default_subspecs = 'RSP'
  
  # Build settings
  spec.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.8',
    'OTHER_SWIFT_FLAGS' => '-Xfrontend -enable-experimental-concurrency'
  }
  
  # Exclude files if needed
  spec.exclude_files = "Tests/**/*", "Examples/**/*"
  
  # Documentation
  spec.documentation_url = "https://github.com/your-username/rspictrue/blob/main/README.md"
end 