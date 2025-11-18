//
//  MJRefreshLocalizedProvider.swift
//  Momcozy
//
//  Created by hubin.h on 2024/6/20.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation
import MJRefresh
import RxRelay

private struct MJRefreshLocalizedProviderKeys {
    static var mjHeaderDateFormat = 0
}

// MARK: - MJRefreshLocalizedProvider
protocol MJRefreshLocalizedProvider {
    /// 时间格式 默认 `defaultDataFormat`
    var mjHeaderDateFormat: String { get set }
    /// 多语言设置
    func setupLocalizedStrings()
}

extension MJRefreshLocalizedProvider {
    
    public var mjHeaderDateFormat: String {
        get {
            objc_getAssociatedObject(self, &MJRefreshLocalizedProviderKeys.mjHeaderDateFormat) as? String ?? defaultDataFormat
        }
        set {
            objc_setAssociatedObject(self, &MJRefreshLocalizedProviderKeys.mjHeaderDateFormat, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
    
    /// 默认格式
    private var defaultDataFormat: String {
        let lng = LocalizedUtils.LanguageCode(rawValue: LocalizedUtils.currentLanguage())
        switch lng {
        case .cn:
            return "yyyy/MM/dd HH:mm"
        case .ar:
            return "HH:mm yyyy/MM/dd"
        default:
            return "MM/dd/yyyy HH:mm"
        }
    }
    
    /// 多语言设置
    public func setupLocalizedStrings() {
        if let header = self as? MJRefreshNormalHeader {
            header.setTitle(L10n.mjHeaderRefresh, for: .idle)
            header.setTitle(L10n.mjHeaderRelease, for: .pulling)
            header.setTitle(L10n.mjHeaderLoading, for: .refreshing)
            
            header.lastUpdatedTimeText = { lastUpdatedTime in
                guard let lastUpdatedTime = lastUpdatedTime else {
                    return L10n.mjHeaderNorecord
                }
                
                let calendar = Calendar.current
                if calendar.isDateInToday(lastUpdatedTime) {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "HH:mm"
                    let time = dateFormatter.string(from: lastUpdatedTime)
                    return String(format: "%@: %@ %@", L10n.mjHeaderLastupdate, L10n.mjHeaderToday, time)
                } else {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = mjHeaderDateFormat
                    let time = dateFormatter.string(from: lastUpdatedTime)
                    return String(format: "%@: %@", L10n.mjHeaderLastupdate, time)
                }
            }
        }
        
        if let footer = self as? MJRefreshAutoNormalFooter {
            footer.setTitle(L10n.mjFooterRefresh, for: .idle)
            footer.setTitle(L10n.mjFooterLoading, for: .refreshing)
            footer.setTitle(L10n.mjFooterNodata, for: .noMoreData)
        }
    }
}

// MARK: - MJRefreshComponent
extension MJRefreshComponent: MJRefreshLocalizedProvider {}
