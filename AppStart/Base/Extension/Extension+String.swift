//
//  Extension+String.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

//单元测试 ✅
import Foundation
import CoreFoundation
import CommonCrypto
import CryptoKit

//MARK: - global var and methods
fileprivate typealias Extension_String = String

//MARK: - main class
extension Extension_String {
    
    //MARK: - 全半角转换
    /** 测试代码段
     let string1 = "ａｂｃｄｅｆｇ，。"
     let string2 = "abcdefg,."
     let str1 = string1.fullwidthToHalfwidth()
     let str2 = string2.halfwidthToFullwidth()
     print("str1:\(str1)\nstr2:\(str2)")
     */
    /// 全角转半角
    /// - Returns: 半角字符串
    public func fullwidthToHalfwidth() -> String {
        let srcStr = self.replacingOccurrences(of: "。", with: ".")
        let cfstr = NSMutableString(string: srcStr) as CFMutableString
        var range = CFRangeMake(0, CFStringGetLength(cfstr))
        CFStringTransform(cfstr, &range, kCFStringTransformFullwidthHalfwidth, false)
        return cfstr as String
    }
    
    /// 半角转全角
    /// - Returns: 全角字符串
    public func halfwidthToFullwidth() -> String {
        let srcStr = self.replacingOccurrences(of: ".", with: "。")
        let cfstr = NSMutableString(string: srcStr) as CFMutableString
        var range = CFRangeMake(0, CFStringGetLength(cfstr))
        CFStringTransform(cfstr, &range, kCFStringTransformFullwidthHalfwidth, true)
        return cfstr as String
    }
    
    //MARK: - RTL转换
    /// 将阿拉伯数字及小数点转换为英文数字0~9.显示
    public var arabicToEnglishDigits: String {
        let arabicToEnglishDigits: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "٫": ".", ",": "."
        ]
        
        var convertedText = self
        for (arabicDigit, englishDigit) in arabicToEnglishDigits {
            convertedText = convertedText.replacingOccurrences(of: String(arabicDigit), with: String(englishDigit))
        }
        
        return convertedText
    }
    
    //MARK: - 中文转拼音
    // 参考：https://blog.csdn.net/yao1500/article/details/106032904
    /// 中文转拼音
    /// - Parameter withTone: 是否带音调, 默认不带音调
    /// - Returns: 拼音字符串
    public func toPinyin(withTone: Bool = false) -> String {
        let mutableString = NSMutableString(string: self)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        if !withTone {
            CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        }
       return String(mutableString)
    }
    
    /// 提取拼音首字母
    /// - Returns: 字符串
    public func toPYHead() -> String {
        let pinyinArray = self.toPinyin().components(separatedBy: " ")
        let initials = pinyinArray.compactMap { token -> String? in
            guard let first = token.utf8.first else { return nil }
            return String(format: "%c", first)
        }
        return initials.joined().uppercased()
    }
    
    //MARK: - 字符转日期
    /// 按指定格式转为 `Date`。
    ///
    /// `timeZone` 默认跟随系统。解析海外当地时间时，应传入地区时区，
    /// 例如 `TimeZone(identifier: "America/New_York")`，系统会按日期应用夏令时规则。
    ///
    /// - Parameters:
    ///   - format: 日期格式。
    ///   - timeZone: 日期字符串所属时区。
    ///   - locale: 解析规则，默认 `en_US_POSIX`，避免用户地区设置改变固定格式含义。
    /// - Returns: 解析成功时返回日期；格式错误或遇到不存在的当地时间时返回 `nil`。
    public func date(
        with format: String = "yyyy-MM-dd HH:mm:ss",
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = format
        dateFormatter.isLenient = false
        return dateFormatter.date(from: self)
    }

    /// 按 ISO 8601 格式转为 `Date`，支持 `Z` 或明确的 UTC 偏移量。
    ///
    /// 同时兼容带与不带小数秒的常见服务端时间格式。
    public var iso8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: self) {
            return date
        }

        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: self)
    }

    /// SwifterSwift: Check if string contains one or more emojis.
    ///
    ///        "Hello 😀".containEmoji -> true
    ///
    public var containEmoji: Bool {
        // http://stackoverflow.com/questions/30757193/find-out-if-character-in-string-is-emoji
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x1F600...0x1F64F, // Emoticons
                 0x1F300...0x1F5FF, // Misc Symbols and Pictographs
                 0x1F680...0x1F6FF, // Transport and Map
                 0x1F1E6...0x1F1FF, // Regional country flags
                 0x2600...0x26FF, // Misc symbols
                 0x2700...0x27BF, // Dingbats
                 0xE0020...0xE007F, // Tags
                 0xFE00...0xFE0F, // Variation Selectors
                 0x1F900...0x1F9FF, // Supplemental Symbols and Pictographs
                 127_000...127_600, // Various asian characters
                 65024...65039, // Variation selector
                 9100...9300, // Misc items
                 8400...8447: // Combining Diacritical Marks for Symbols
                return true
            default:
                continue
            }
        }
        return false
    }
    
    //MARK: - Encoded/ Decoded
    /// SwifterSwift: Readable string from a URL string.
    ///
    ///        "it's%20easy%20to%20decode%20strings".urlDecoded -> "it's easy to decode strings"
    ///
    public var urlDecoded: String {
        return removingPercentEncoding ?? self
    }
    
    /// SwifterSwift: URL escaped string.
    ///
    ///        "it's easy to encode strings".urlEncoded -> "it's%20easy%20to%20encode%20strings"
    /// ???  .urlQueryAllowed
    public var urlEncoded: String {
        if isURLEncoded { return self }
        return addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    /// 使用正则表达式检测 URL 中是否存在百分比编码
    public var isURLEncoded: Bool {
        let percentEncodedPattern = "%[0-9A-Fa-f]{2}"
        if let _ = range(of: percentEncodedPattern, options: .regularExpression) {
            return true
        }
        return false
    }

    /// 转Data
    public var data: Data? {
        return self.data(using: String.Encoding.utf8)
    }

    /// md5加密, 不安全, 不推荐
    /// - Returns: 加密后的字符串
//    public func md5() -> String {
//        let str = self.cString(using: String.Encoding.utf8)
//        let strLen = CUnsignedInt(self.lengthOfBytes(using: String.Encoding.utf8))
//        let digestLen = Int(CC_MD5_DIGEST_LENGTH)
//        let result = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
//        CC_MD5(str!, strLen, result)
//        let hash = NSMutableString()
//        for i in 0 ..< digestLen {
//            hash.appendFormat("%02x", result[i])
//        }
//        free(result)
//        return String(format: hash as String)
//    }
    public var md5: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// SHA256加密
    /// import CommonCrypto
    /// SHA 是 Secure Hash Algorithm 的缩写，即安全哈希算法。
    /// SHA256 也称为 SHA2，它是从SHA1进化而来，目前没有发现SHA256被破坏，但随着计算机计算能力越来越强大，它肯定会被破坏，所以SHA3已经在路上了。
//    public func sha256() -> String {
//        let utf8 = cString(using: .utf8)
//        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
//        CC_SHA256(utf8, CC_LONG(utf8!.count - 1), &digest)
//        return digest.reduce("") { $0 + String(format:"%02x", $1) }
//    }
    
    public var sha1: String {
        let data = Data(self.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 相比 sha1, 推荐 sha256
    public var sha256: String {
        let data = Data(self.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// base64编码
    /// - Returns:
    public func base64Encode() -> String? {
        if let data = self.data(using: String.Encoding.utf8) {
            return data.base64EncodedString(options: .lineLength64Characters)
        }
        return nil
    }

    /// base64解码
    public func base64Decode() -> String? {
        if let data = Data.init(base64Encoded: self, options: .ignoreUnknownCharacters) {
            return String(data: data, encoding: String.Encoding.utf8)
        }
        return nil
    }

    /// 字符串转Bytes
    public func toBytes() -> [UInt8] {
        guard let data = self.data(using: String.Encoding.utf8) else { return [] }
        return [UInt8](data)
    }

    //MARK: - NSRange usage
    /// 截取NSRange范围的子字符串
    public func subString(with range: NSRange) -> String {
        let text = self as NSString
        let subStr = text.substring(with: range) as String
        return subStr
    }
    
    /// 获取子字符串的范围NSRange
    /// - Parameter subString: 子字符串
    /// - Returns: NSRange
    public func nsRange(of subString: String) -> NSRange {
        let text = self as NSString
        return text.range(of: subString)
    }

    public func toNSRange(_ range: Range<String.Index>) -> NSRange {
        guard let from = range.lowerBound.samePosition(in: utf16), let to = range.upperBound.samePosition(in: utf16) else {
            return NSMakeRange(0, 0)
        }
        return NSMakeRange(utf16.distance(from: utf16.startIndex, to: from), utf16.distance(from: from, to: to))
    }

    public func toRange(_ range: NSRange) -> Range<String.Index>? {
        guard let from16 = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex) else { return nil }
        guard let to16 = utf16.index(from16, offsetBy: range.length, limitedBy: utf16.endIndex) else { return nil }
        guard let from = String.Index(from16, within: self) else { return nil }
        guard let to = String.Index(to16, within: self) else { return nil }
        return from ..< to
    }

    /// 谓词匹配(正则表达式匹配)
    /// - Parameter regex: 正则表达式
    /// - Returns: 是否匹配
    public func predicateMatch(regex: String) -> Bool {
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: self)
    }
}

extension Extension_String {
    
    /// 字符串转富文本
    /// - Returns: 富文本对象
    public func toAttributedString() -> NSMutableAttributedString {
        return NSMutableAttributedString(string: self)
    }

    /// 计算文本段落的尺寸(默认字号17, 行距5)
    /// - Parameters:
    ///   - maxSize: 最大尺寸
    ///   - attributes: 属性
    ///   - font: 字号. 仅attributes =nil时生效
    ///   - lineSpacing: 行距. 仅attributes =nil时生效
    /// - Returns: 预计尺寸
    public func estimatedSize(maxSize: CGSize, attributes: [NSAttributedString.Key : Any]? = nil, font: UIFont = UIFont.systemFont(ofSize: 17), lineSpacing: CGFloat = 5) -> CGSize {
        guard let attributes = attributes else {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = lineSpacing - (font.lineHeight - font.pointSize)
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byCharWrapping
            let attributes_def = [NSAttributedString.Key.font: font, NSAttributedString.Key.paragraphStyle: paragraphStyle]
            return NSString(string: self).boundingRect(with: maxSize, options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: attributes_def, context: nil).size
        }
        return NSString(string: self).boundingRect(with: maxSize, options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: attributes, context: nil).size
    }
    
    // MARK: - 计算文本尺寸
    private func boundingRect(ofAttributes attributes: [NSAttributedString.Key: Any], size: CGSize) -> CGRect {
        let boundingBox = boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return boundingBox
    }
    
    /// 计算文本尺寸
    /// - Parameters:
    ///   - attributes: 属性
    ///   - maxWidth: 最大宽度
    ///   - maxHeight: 最大高度
    /// - Returns: 尺寸
    public func size(ofAttributes attributes: [NSAttributedString.Key: Any], maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        boundingRect(ofAttributes: attributes, size: .init(width: maxWidth, height: maxHeight)).size
    }
    
    ///  计算文本尺寸
    /// - Parameters:
    ///   - font: 字体
    ///   - maxWidth: 最大宽度
    ///   - maxHeight: 最大高度
    /// - Returns: 尺寸
    public func size(ofFont font: UIFont, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let constraintRect = CGSize(width: maxWidth, height: maxHeight)
        let boundingBox = boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return boundingBox.size
    }
    
    /// 计算文本宽度
    /// - Parameters:
    ///   - size: 字体大小
    ///   - maxHeight: 最大高度
    /// - Returns: 宽度
    public func width(ofSize size: CGFloat, maxHeight: CGFloat) -> CGFloat {
        width(
            ofFont: UIFont.systemFont(ofSize: size),
            maxHeight: maxHeight
        )
    }
    
    /// 计算文本宽度
    /// - Parameters:
    ///   - font: 字体
    ///   - maxHeight: 最大高度
    /// - Returns: 宽度
    public func width(ofFont font: UIFont, maxHeight: CGFloat) -> CGFloat {
        size(
            ofAttributes: [NSAttributedString.Key.font: font],
            maxWidth: CGFloat(MAXFLOAT),
            maxHeight: maxHeight
        ).width
    }
    
    /// 计算文本高度
    /// - Parameters:
    ///   - size: 字体大小
    ///   - maxWidth: 最大宽度
    /// - Returns: 高度
    public func height(ofSize size: CGFloat, maxWidth: CGFloat) -> CGFloat {
        height(
            ofFont: UIFont.systemFont(ofSize: size),
            maxWidth: maxWidth
        )
    }
    
    /// 计算文本高度
    /// - Parameters:
    ///   - font: 字体
    ///   - maxWidth: 最大宽度
    /// - Returns: 高度
    public func height(ofFont font: UIFont, maxWidth: CGFloat) -> CGFloat {
        size(
            ofAttributes: [NSAttributedString.Key.font: font],
            maxWidth: maxWidth,
            maxHeight: CGFloat(MAXFLOAT)
        ).height
    }
}

extension Extension_String {

    /// URL参数拼接 在 URL 中追加 query 参数（自动处理 ? & 和 #fragment）
    ///
    ///  let baseUrl = "https://xxx.com/pages/member-flash-sale#2"
    ///  let url = baseUrl
    ///        .appendingQueryItem(name: "Language", value: "en-US")
    ///        .appendingQueryItem(name: "openSource", value: "App")
    ///        .appendingQueryItem(name: "APPTOKEN", value: "123456")
    ///        .appendingQueryItem(name: "globalEnv", value: "NA")
    ///        .appendingQueryItem(name: "appVersion", value: "2.1.1")
    ///
    ///    https://xxx.com/pages/member-flash-sale?Language=en-US&openSource=App&APPTOKEN=123456&globalEnv=NA&appVersion=2.1.1#2
    ///
    /// - Parameters:
    ///   - name: 键
    ///   - value: 值
    /// - Returns: 拼接结果
    public func appendingQueryItem(name: String, value: String) -> String {
        guard var components = URLComponents(string: self) else { return self }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.string ?? self
    }
    
    /// 字符串转Html
    public func toHtml() -> String {
//        let styleStr: String = String(format: "<head><style>img{max-width:%ldpx !important;}ul {margin:0; padding:0; text-align:left;}</style><head>", kScreenW  * 0.95)
//        let styleStr: String = String(format: "<head><style>body, div, span, a, dl, dt, dd, ul, ol, li, h1, h2, h3, h4, h5, h6, p, th, td, pre, form, fieldset, legend, input, button, textarea, select {margin:0;padding:5;}img{max-width:%ldpx !important;}li {list-style:none;}</style><head>", kScreenW  * 0.95)
        var str: String = self
        let scaner: Scanner = Scanner.init(string: self)
        let dict = ["&amp;":"&", "&lt;":"<", "&gt;":">", "&nbsp;":"", "&quot;":"\"", "width":"wid"]
        while scaner.isAtEnd == false {
            for (key, value) in dict {
                scaner.scanUpTo(key, into: nil)
                str = str.replacingOccurrences(of: key, with: value)
            }
        }
        return str
    }

    /// Html转字符串
    public var htmlToString: String? {
        guard let data = data(using: .utf8) else { return nil }
        return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding:String.Encoding.utf8.rawValue], documentAttributes: nil).string
    }

//    /// 转化为char * (待测试验证)
//    public func toCharPtr() -> UnsafeMutablePointer<Int8> {
//        let charArray = self.cString(using: .utf8)!
//        let length = charArray.count
//        let pointer = UnsafeMutablePointer<Int8>.allocate(capacity: length)
//        for i in 0..<length {
//            pointer[i] = charArray[i]
//        }
//        return pointer
//    }
}
