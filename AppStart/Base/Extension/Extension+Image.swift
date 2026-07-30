//
//  Extension+Image.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

//单元测试 ✅
import UIKit
import ImageIO

//MARK: - global var and methods
fileprivate typealias Extension_Image = UIImage

// MARK: - RTL
extension Extension_Image {
    
    /// 适配RTL布局镜像翻转
    public var adaptRTL: UIImage? {
        return self.imageFlippedForRightToLeftLayoutDirection()
    }
}

// MARK: -
extension Extension_Image {
    
    /// 颜色重绘成图片
    /// - Parameters:
    ///   - color: 颜色
    ///   - size: 尺寸
    public convenience init?(color: UIColor, size: CGSize = CGSize(width: 1.0, height: 1.0)) {
        if size.width <= 0 || size.height <= 0 { return nil }
        UIGraphicsBeginImageContextWithOptions(size, true, UIScreen.main.scale)
        defer {
            UIGraphicsEndImageContext()
        }
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(color.cgColor)
        context?.fill(CGRect(origin: CGPoint.zero, size: size))
        context?.setShouldAntialias(true)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
    
    /// 以base64字符串初始化
    /// - Parameter base64String: base64字符串
    /// - Returns: 图片对象
    public func imageWithBase64(_ base64String: String) -> UIImage? {
        if base64String.isEmpty { return nil }
        guard let data = Data.init(base64Encoded: base64String) else { return nil }
        return UIImage.init(data: data)
    }
    
    /// 转成base64String, 默认png
    /// - Returns: base64字符串
    public func toBase64String() -> String? {
        let data = self.pngData()
        return data?.base64EncodedString()
    }
}

extension Extension_Image {

//    /// 是否有alpha通道
//    func hasAlphaChannel() -> Bool {
//        guard let cgImage = self.cgImage else { return false }
//        let alpha: CGImageAlphaInfo = cgImage.alphaInfo //& CGBitmapInfo.alphaInfoMask
//        return alpha == CGImageAlphaInfo.first || alpha == CGImageAlphaInfo.last || alpha == CGImageAlphaInfo.premultipliedFirst || alpha == CGImageAlphaInfo.premultipliedLast
//    }
    
    /// 水平翻转（即左右镜像）
    /// - Returns: 新Image对象
    public func horizontalFlip() -> UIImage {
        //翻转图片的方向
        let flipImageOrientation = (self.imageOrientation.rawValue + 4) % 8
        //翻转图片
        let flipImage =  UIImage(cgImage: self.cgImage!,
            scale:self.scale,
            orientation:UIImage.Orientation(rawValue: flipImageOrientation)!
        )
        return flipImage
    }
    
    /// 垂直翻转
    /// - Returns: 新Image对象
    public func verticalFlip() -> UIImage {
        //翻转图片的方向
        var flipImageOrientation = (self.imageOrientation.rawValue + 4) % 8
        flipImageOrientation += flipImageOrientation%2==0 ? 1 : -1
        //翻转图片
        let flipImage =  UIImage(cgImage:self.cgImage!,
                                 scale:self.scale,
                                 orientation:UIImage.Orientation(rawValue: flipImageOrientation)!
        )
        return flipImage
    }

    /// 获取位置处颜色
    public func pixelColor(pos: CGPoint) -> UIColor? {
        let pixelData = self.cgImage?.dataProvider?.data
        guard pixelData != nil else { return nil }
        let data:UnsafePointer<UInt8> =  CFDataGetBytePtr(pixelData)
        let pixelInfo: Int = ((Int(self.size.width) * Int(pos.y)) + Int(pos.x)) * 4

        let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
        let g = CGFloat(data[pixelInfo+1]) / CGFloat(255.0)
        let b = CGFloat(data[pixelInfo+2]) / CGFloat(255.0)
        let a = CGFloat(data[pixelInfo+3]) / CGFloat(255.0)
        print(r, g, b, a)
        let corlor = UIColor.init(red: r, green: g, blue: b, alpha: a)
        return corlor
    }
    
    /// 灰度滤镜
    /// 转换为黑白图片, 将图像转换为灰度。
    public func grayscale() -> UIImage? {
        // 创建黑白滤镜
        guard let ciImage = CIImage(image: self) else { return nil }
        
        let blackAndWhiteFilter = CIFilter(name: "CIPhotoEffectMono")
        blackAndWhiteFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        guard let outputImage = blackAndWhiteFilter?.outputImage else { return nil }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
    ///MARK: 人脸检测, 识别人脸数统计
    /// 若处理人脸截图居中, 使用 #pod 'FaceAware'
    /// - Returns: 人脸数
    public func foundFaces() -> Int? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyLow])
        if let features = detector?.features(in: ciImage), features.count > 0 {
            //print("found \(features.count) faces")
            return features.count
        }
        return nil
    }
    
//    public static func systemShare(activityItems: [UIImage], excludedTypes: [UIActivity.ActivityType]? = nil, completeHandle:((_ isFinish: Bool) -> Void)? = nil) {
//        let activityVc = UIActivityViewController.init(activityItems: activityItems as [Any], applicationActivities: nil)
//        if let excludedTypes = excludedTypes {
//            //activityVc.excludedActivityTypes = [.postToFacebook, .postToTwitter, .postToWeibo, .message, .mail, .print, .copyToPasteboard, .assignToContact, .saveToCameraRoll, .addToReadingList, .postToFlickr, .postToVimeo, .postToTencentWeibo, .airDrop, .openInIBooks]
//            activityVc.excludedActivityTypes = excludedTypes
//        }
//        stackTopViewController()?.present(activityVc, animated: true, completion: nil)
//        activityVc.completionWithItemsHandler = {(activityType, completed, items, error) -> Void in
//            if completed == true {
//                print("分享成功")
//                completeHandle?(true)
//            }
//            // 不能少
//            activityVc.completionWithItemsHandler = nil
//        }
//    }
}

//MARK: - 图片压缩处理

/// 图片压缩参数：ImageIO 降采样 + JPEG 质量/体积控制。
public struct ImageCompressionOptions: Sendable {

    /// 最长边像素上限（默认 1440）。
    public var maxPixelSize: Int
    /// 目标体积（字节）；`nil` 表示仅按 `initialQuality` 输出。
    public var maxByteCount: Int?
    /// JPEG 起始质量；设 `maxByteCount` 时由二分压缩覆盖。
    public var initialQuality: CGFloat
    /// 压缩后体积不小于原图时返回原图数据。
    public var passthroughIfLarger: Bool

    public init(
        maxPixelSize: Int = 1440,
        maxByteCount: Int? = nil,
        initialQuality: CGFloat = 0.85,
        passthroughIfLarger: Bool = true
    ) {
        self.maxPixelSize = maxPixelSize
        self.maxByteCount = maxByteCount
        self.initialQuality = initialQuality
        self.passthroughIfLarger = passthroughIfLarger
    }
}

extension Extension_Image {

    // MARK: - 图片压缩（对外）

    /// 按最长边像素上限等比缩小；优先 ImageIO 降采样，失败则 Renderer 重绘。
    public func resize(maxPixelSize: Int) -> UIImage {
        downsample(maxPixelSize: maxPixelSize, sourceData: encodedSourceData())
    }

    /// 不改变尺寸，仅按 JPEG 质量二分压缩至不超过 `maxBytes`。
    public func compress(maxBytes: Int) -> Data? {
        Self.jpegData(from: self, maxBytes: maxBytes)
    }

    /// 降采样 + JPEG 输出；参数见 `ImageCompressionOptions`。
    public func compress(using options: ImageCompressionOptions = .init()) -> Data? {
        let sourceData = encodedSourceData()
        let image = downsample(maxPixelSize: options.maxPixelSize, sourceData: sourceData)
        let data = Self.jpegData(
            from: image,
            maxByteCount: options.maxByteCount,
            initialQuality: options.initialQuality
        )

        guard let data else { return sourceData }

        if options.passthroughIfLarger, let sourceData, data.count >= sourceData.count {
            return sourceData
        }
        return data
    }

    // MARK: - 图片压缩（内部）

    private func encodedSourceData() -> Data? {
        jpegData(compressionQuality: 1.0) ?? pngData()
    }

    private func downsample(maxPixelSize: Int, sourceData: Data?) -> UIImage {
        guard maxPixelSize > 0 else { return self }
        let data = sourceData ?? encodedSourceData()
        if let data, let downsampled = Self.downsampledImage(from: data, maxPixelSize: maxPixelSize) {
            return downsampled
        }
        return renderScaled(maxPixelSize: maxPixelSize)
    }

    private func renderScaled(maxPixelSize: Int) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longestEdge = max(pixelWidth, pixelHeight)
        guard longestEdge > CGFloat(maxPixelSize) else { return self }

        let ratio = CGFloat(maxPixelSize) / longestEdge
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func jpegData(from image: UIImage, maxByteCount: Int?, initialQuality: CGFloat) -> Data? {
        let quality = min(max(initialQuality, 0), 1)
        if let maxByteCount {
            return jpegData(from: image, maxBytes: maxByteCount)
        }
        return image.jpegData(compressionQuality: quality)
    }

    /// JPEG 质量二分（最多 6 次）；`data.count` 与磁盘体积可能略有差异。
    private static func jpegData(from image: UIImage, maxBytes: Int) -> Data? {
        guard var data = image.jpegData(compressionQuality: 0.9) else { return nil }
        if data.count <= maxBytes { return data }

        var maxQuality: CGFloat = 1
        var minQuality: CGFloat = 0
        for _ in 0..<6 {
            let compression = (maxQuality + minQuality) / 2
            guard let next = image.jpegData(compressionQuality: compression) else { break }
            data = next
            if data.count < maxBytes {
                minQuality = compression
            } else if data.count > maxBytes {
                maxQuality = compression
            } else {
                break
            }
        }
        return data
    }

    /// ImageIO 按最长边降采样并应用 EXIF 方向；不全尺寸解码，省内存。
    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

//MARK: - private mothods
class AssetsClass { }
extension Extension_Image {
    
    /// 获取bundle资源
//    public static func bundleImage(named: String) -> UIImage? {
//        let bundlePath = "\(Bundle(for: AssetsClass.self).bundlePath)" + "/Resources.bundle"
//        let bundle = Bundle(path: bundlePath)
//        return UIImage(named: named, in: bundle, compatibleWith: nil)
//    }
    
//    //对Extension_Data -> ImageType 补充
//    // 参考YYKit->YYImage/NSBundle+YYAdd.h
//    func preferredScales() -> [Int] {
//        let screenScale = UIScreen.main.scale
//        var scales = [3, 2, 1]
//        if (screenScale <= 1) {
//            scales = [1, 2, 3]
//        } else if (screenScale <= 2) {
//            scales = [2, 3, 1]
//        }
//        return scales
//    }
//
//    /**
//     https://blog.csdn.net/weixin_34268843/article/details/87977961?utm_medium=distribute.pc_relevant.none-task-blog-baidujs_title-0&spm=1001.2101.3001.4242
//     var count: UInt32 = 0
//     let ivars = class_copyIvarList(UIImageAsset.self, &count)!
//     for i in 0..<count {
//         let namePoint = ivar_getName(ivars[Int(i)])!
//         let name = String(cString: namePoint)
//         print(name)
//     }
//     */
//    public func imageExtensionName() -> String? {
//        // If no extension, guess by system supported (same as UIImage). -> png
//        guard let imageAsset = self.imageAsset, let imgName = imageAsset.value(forKeyPath: "_assetName") as? String else { return nil }
//        let res = NSString(string: imgName)
//        let name = res.deletingPathExtension
//        let ext = res.pathExtension
//        let exts = ext.isEmpty == false ? [ext] : ["", "png", "jpeg", "jpg", "gif", "webp", "apng"]
//        let scales = self.preferredScales()
//        for scale in scales {
//            let scaledName = name + ((scale > 1) ? "@\(scale)x": "")
//            for e in exts {
//                if let path = Bundle.main.path(forResource: scaledName, ofType: e), path.isEmpty == false {
//                    return e
//                }
//            }
//        }
//        return nil
//    }
}
