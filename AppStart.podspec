#
# Be sure to run `pod lib lint AppStart.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
# > 本地校验
#  s.source = { :path => '../' }
# > 本地校验（Xcode 15+ 须加 modular headers + static libs，否则三方 Pod 会触发 libarclite 错误）
# ✗ pod spec lint AppStart.podspec --allow-warnings --use-modular-headers --use-libraries
# > 发布到 Trunk（Trunk 不支持 --use-modular-headers，本地 spec lint 通过后用 skip-tests 发布）
# ✗ pod trunk push AppStart.podspec --verbose --allow-warnings --skip-tests

Pod::Spec.new do |s|
  s.name             = 'AppStart'
  s.version          = '0.2.0'
  s.summary     = "A foundational component library for customizable app development."
  s.description = <<-DESC
  基础组件库，用于高效构建和定制相关应用。
  A foundational component library for efficient development and customization of related applications.
  DESC
  
  s.homepage         = 'https://github.com/hubin97/AppStart'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'hubin.h' => '970216474@qq.com' }
  #s.source = { :path => '../' }
  s.source           = { :git => 'https://github.com/hubin97/AppStart.git', :tag => s.version.to_s }
  
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'
  
  s.ios.deployment_target = '14.0'
  s.swift_versions = ['5.0']
  # 仅约束 AppStart 自身 Pod target；勿用 user_target_xcconfig 写入宿主 App，
  # 否则会与宿主工程里更高的 IPHONEOS_DEPLOYMENT_TARGET 冲突并触发 pod install 警告。
  s.pod_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '14.0' }

  # 模块 README（Connectivity / HTTP / BLE 等）仅保留在 Pod 目录，不参与编译
  s.preserve_paths = 'AppStart/**/*.md', 'README.md'
  
  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  
  # 子模块：ProgressHUD
  s.subspec 'ProgressHUD' do |hud|
    hud.source_files = 'AppStart/ProgressHUD/**/*.swift'
  end
  
  # 子模块：Base
  s.subspec 'Base' do |base|
    base.subspec 'Global' do |global|
      global.source_files = 'AppStart/Base/Global/*.swift'
    end
    
    base.subspec 'Extension' do |ex|
      ex.source_files = 'AppStart/Base/Extension/*.swift'
      ex.dependency 'AppStart/Base/Global'
    end
    
    base.subspec 'Core' do |core|
      core.source_files = 'AppStart/Base/Core/*.swift'
      core.dependency 'AppStart/Sources'
      core.dependency 'AppStart/Base/Global'
      core.dependency 'AppStart/Base/Extension'
      core.dependency 'SnapKit'
    end
  end
  
  # 子模块：UIComponents
  s.subspec 'UIComponents' do |ui|
    ui.subspec 'AlertView' do |view|
      view.source_files = 'AppStart/UIComponents/AlertView/*.swift'
      view.dependency 'AppStart/Base'
    end
    
    ui.subspec 'Views' do |view|
      view.source_files = 'AppStart/UIComponents/Views/*.swift'
      view.dependency 'AppStart/Base'
      view.dependency 'AppStart/Utils/Toolkit'
      view.dependency 'RxRelay'
      view.dependency 'PromiseKit'
      view.dependency 'Toast-Swift'
      view.dependency 'Kingfisher'
      view.dependency 'DZNEmptyDataSet'
      view.dependency 'MJRefresh'
    end
    
    ui.subspec 'Protocols' do |pr|
      pr.source_files = 'AppStart/UIComponents/Protocols/*.swift'
      pr.dependency 'AppStart/Base'
      pr.dependency 'AppStart/Sources'
      pr.dependency 'AppStart/UIComponents/Views'
      pr.dependency 'RxRelay'
      pr.dependency 'MJRefresh'
      pr.dependency 'DZNEmptyDataSet'
    end
  end
  
  # 子模块：Utils
  s.subspec 'Utils' do |utils|
    utils.subspec 'AuthStatus' do |au|
      au.source_files = 'AppStart/Utils/AuthStatus'
      au.ios.deployment_target = '14.0'
      au.dependency 'AppStart/Base'
    end
    
    utils.subspec 'Toolkit' do |tool|
      tool.source_files = 'AppStart/Utils/Toolkit'
      tool.dependency 'AppStart/Base'
      tool.dependency 'PromiseKit'
      tool.dependency 'Toast-Swift'
      tool.dependency 'Kingfisher'
    end
    
    utils.subspec 'Logger' do |log|
      log.source_files = 'AppStart/Utils/Logger'
      log.dependency 'AppStart/Base'
      log.dependency 'AppStart/Sources'
      log.dependency 'AppStart/Utils/Toolkit'
      log.dependency 'RxSwift'
      log.dependency 'CocoaLumberjack'
    end
    
    utils.subspec 'Reactive' do |rx|
      rx.source_files = 'AppStart/Utils/Reactive/**/*.swift'
      rx.dependency 'RxSwift'
      rx.dependency 'RxRelay'
      rx.dependency 'RxGesture'
      rx.dependency 'Kingfisher'
    end
  end
  
  # 子模块：Network
  s.subspec 'Network' do |http|
    ['RxSwift', 'RxRelay', 'Moya', 'ObjectMapper', 'PromiseKit'].each do |dd|
      http.dependency dd
    end

    http.subspec 'Connectivity' do |conn|
      conn.source_files = 'AppStart/Network/Connectivity/*.swift'
      conn.frameworks = 'Network', 'CoreTelephony'
      conn.ios.deployment_target = '14.0'
    end
    
    http.subspec 'Core' do |ss|
      ss.source_files = 'AppStart/Network/Core/*.swift'
      ss.dependency 'AppStart/Utils'
      ss.dependency 'AppStart/Sources'
      ss.dependency 'AppStart/ProgressHUD'
    end
    
    http.subspec 'Utils' do |ss|
      ss.source_files = 'AppStart/Network/Utils/*.swift'
      ss.framework = "Foundation", "CoreTelephony"
    end
  end
  
  # 子模块：Ble
  s.subspec 'Ble' do |ble|
    ble.source_files = 'AppStart/Ble/**/*.swift'
    ble.dependency 'AppStart/Utils/Logger'
  end
  
  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.requires_arc = true
  
  # ――― Resources ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.resources = [
    'AppStart/Resources/**/*.{xcassets,strings,xcprivacy}',
  ]
  
  # --- SwiftGen began ---
  s.subspec 'Sources' do |ss|
    ss.source_files = 'AppStart/Sources/Generated/*'
  end
  # --- SwiftGen end ---
  
end
