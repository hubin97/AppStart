#
# Be sure to run `pod lib lint AppStart.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
# ✗ pod spec lint AppStart.podspec --allow-warnings --verbose
# ✗ pod trunk push AppStart.podspec --verbose --allow-warnings

Pod::Spec.new do |s|
  s.name             = 'AppStart'
  s.version          = '0.1.1'
  s.summary     = "A foundational component library for customizable app development."
  s.description = <<-DESC
  基础组件库，用于高效构建和定制相关应用。
  A foundational component library for efficient development and customization of related applications.
  DESC

  s.homepage         = 'https://github.com/hubin97/AppStart'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'hubin.h' => '970216474@qq.com' }
  s.source           = { :git => 'https://github.com/hubin97/AppStart.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '14.0'
  s.swift_versions = ['5.0']
  
  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  # 子模块：Base
  s.subspec 'Base' do |base|
      # 使用 Ruby 数组简化多个依赖的定义
      # 扩展自定义Hud;  pod 'ProgressHUD', :git => 'https://github.com/hubin97/ProgressHUD.git'
      ['SnapKit', 'Kingfisher', 'Toast-Swift', 'ProgressHUD', 'PromiseKit'].each do |dd|
          base.dependency dd
      end
      
      #base.dependency 'Hero', '~> 1.6.3' # 确保使用支持 iOS 13 的版本
      base.subspec 'Core' do |ss|
          ss.framework = "Foundation", "UIKit"
          ss.source_files = 'AppStart/Base/Core/**/*.swift'
      end
      
      base.subspec 'UI' do |ss|
          ss.source_files = 'AppStart/Base/UI/*.swift'
          ss.dependency 'AppStart/Base/Core'
      end
      
  end
  
  # 子模块：Utils
  s.subspec 'Utils' do |other|
      ['Toast-Swift', 'Kingfisher', 'CocoaLumberjack', 'RxSwift', 'RxGesture'].each do |dd|
          other.dependency dd
      end
      
      other.subspec 'AuthStatus' do |auth|
          auth.source_files = 'AppStart/Utils/AuthStatus'
          auth.dependency 'AppStart/Base/Core'
      end
      
      other.subspec 'Helpers' do |utils|
          utils.source_files = 'AppStart/Utils/Helpers'
          utils.dependency 'Toast-Swift'
          utils.dependency 'Kingfisher'
          utils.dependency 'AppStart/Base/Core'
      end
      
      other.subspec 'LoggerManager' do |log|
          log.source_files = 'AppStart/Utils/LoggerManager'
          log.dependency 'RxSwift'
          log.dependency 'CocoaLumberjack'
          log.dependency 'AppStart/Base'
          log.dependency 'AppStart/Utils/Helpers'
      end
      
      other.subspec 'Rx' do |rx|
          rx.source_files = 'AppStart/Utils/Rx/**/*.{swift}'
          rx.dependency 'RxGesture'
      end

      other.subspec 'UIKit' do |ui|
          ui.source_files = 'AppStart/Utils/UIKit/**/*.{swift}'
          ui.dependency 'AppStart/Base/Core'
      end
  end
  
  # 子模块：Network
  s.subspec 'Network' do |http|
      ['RxSwift', 'RxRelay', 'Moya', 'ObjectMapper', 'PromiseKit', 'ProgressHUD'].each do |dd|
          http.dependency dd
      end
      
      http.subspec 'Core' do |ss|
          ss.source_files = 'AppStart/Network/Core/*.swift'
          ss.dependency 'AppStart/Utils'
      end
      
      http.subspec 'Utils' do |ss|
          ss.source_files = 'AppStart/Network/Utils/*.swift'
          ss.framework = "Foundation", "CoreTelephony"
      end
  end
  
  # 子模块：BLE
  s.subspec 'BLE' do |ble|
      ['RxSwift', 'RxCocoa', 'NSObject+Rx'].each do |dd|
          ble.dependency dd
      end
      
      ble.source_files = 'AppStart/BLE/**/*.swift'
  end
  
  # ――― Resources ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.resource     = 'AppStart/Resources.bundle'

  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  s.requires_arc = true
end
