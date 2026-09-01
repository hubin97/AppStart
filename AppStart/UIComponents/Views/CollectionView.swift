//
//  CollectionView.swift
//  AppStart
//
//  Created by hubin.h on 2024/8/20.
//  Copyright © 2020 路特创新. All rights reserved.

import Foundation
import MJRefresh
// @preconcurrency 是 Swift 6 严格并发检查里的 「降级/放宽」标记：告诉编译器——这份 ObjC 或旧 Swift 接口在写并发规则之前就有了，先别用 Swift 6 最严标准来卡我。
// 作用：导入整个模块时，把该模块里暴露的类型/协议，按 「Swift 5 时代的并发假设」 来看待，而不是按 Swift 6 完整规则。
@preconcurrency import DZNEmptyDataSet

/// 1. 扩展下拉刷新, 上拉加载方法
/// 2. 添加通用空白占位控件, 以及点击事件
///
open class CollectionView: UICollectionView {
    
    var mjHeaderView = RefreshHeader()
    var mjFooterView = RefreshFooter()

    /// 点击空页面视图
    public var didTapEmptyViewBlock: (() -> Void)?
    /// `EmptyView`垂直偏移量
    public var verticalOffset: CGFloat = 0
    /// `EmptyView`图片
    public var imageForEmptyDataSet: UIImage?
    /// `EmptyView`标题
    public var titleForEmptyDataSet: NSAttributedString?

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        self.emptyDataSetSource = self
        self.emptyDataSetDelegate = self
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 设置段头下拉刷新
    public func setHeaderRefresh(_ block: @escaping (() -> Void)) {
        self.mj_header = self.mjHeaderView
        self.mj_header?.refreshingBlock = block
    }
    
    /// 设置段头上拉加载
    public func setFooterRefresh(_ block: @escaping (() -> Void)) {
        self.mj_footer = self.mjFooterView
        self.mj_footer?.refreshingBlock = block
    }
}

// 作用：在 你的类型声明遵循协议 时，对这两个 ObjC 协议 再用一次 @preconcurrency。
// 典型场景：Swift 6 会认为：你的 @MainActor 实现去遵循一个「非隔离协议」→ 跨隔离、可能 数据竞赛; 加上 @preconcurrency 后，编译器 暂时接受 这种遵循，不把它当错误。
extension CollectionView: @preconcurrency DZNEmptyDataSetSource, @preconcurrency DZNEmptyDataSetDelegate {
    
    public func image(forEmptyDataSet scrollView: UIScrollView!) -> UIImage! {
        return self.imageForEmptyDataSet ?? Asset.iconNullData.image
    }
    public func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 15), NSAttributedString.Key.foregroundColor: UIColor(hexStr: "#999999")]
        return self.titleForEmptyDataSet ?? NSAttributedString(string: L10n.stringNotRecordYetTips, attributes: attributes)
    }
    public func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        return self.verticalOffset
    }
    public func emptyDataSet(_ scrollView: UIScrollView!, didTap view: UIView!) {
        self.didTapEmptyViewBlock?()
    }
}
