//
//  RefreshView.swift
//  AppStart
//
//  Created by hubin.h on 2025/11/18.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation
import MJRefresh
import RxRelay

// MARK: - Global Variables & Functions (if necessary)
public class RefreshHeader: MJRefreshNormalHeader {

    public var headerRefresh = PublishRelay<Void>()
    convenience init() {
        self.init(frame: CGRect.zero)
        self.setupLocalizedStrings()
        self.refreshingBlock = {[weak self] in
            self?.headerRefresh.accept(())
        }
    }
}

public class RefreshFooter: MJRefreshAutoNormalFooter {
    
    public var footerRefresh = PublishRelay<Void>()
    convenience init() {
        self.init(frame: CGRect.zero)
        self.setupLocalizedStrings()
        self.refreshingBlock = {[weak self] in
            self?.footerRefresh.accept(())
        }
    }
}

// MARK: -

/// 下拉刷新
public protocol MJPullRefreshDataProvider: AnyObject {
    associatedtype Element
    
    var mjHeaderView: RefreshHeader { get }
    var dataList: [Element] { get set }
    
    func pullRefresh()
}

extension MJPullRefreshDataProvider {
    public func pullRefresh() {}
}

/// 上拉加载更多
public protocol MJLoadMoreDataProvider: AnyObject {
    associatedtype Element
    
    var mjFooterView: RefreshFooter { get }
//    var pageNum: Int { get set }
//    var pageSize: Int { get }
    var dataList: [Element] { get set }
    
    func loadMoreData()
}

extension MJLoadMoreDataProvider {
    public func loadMoreData() {}
}
