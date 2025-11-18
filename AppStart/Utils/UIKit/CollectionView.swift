//
//  CollectionView.swift
//  Momcozy
//
//  Created by hubin.h on 2024/8/20.
//  Copyright © 2020 路特创新. All rights reserved.

import Foundation
import DZNEmptyDataSet
import RxRelay
import MJRefresh

/// 1. 扩展下拉刷新, 上拉加载方法
/// 2. 添加通用空白占位控件, 以及点击事件
///
open class CollectionView: UICollectionView {
    
    var mjHeaderView = LTRefreshHeader()
    var mjFooterView = LTRefreshFooter()

    /// 点击空页面视图
    public let didTapEmptyView: PublishRelay = PublishRelay<Void>()
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

// MARK: - other classes
extension CollectionView: DZNEmptyDataSetSource, DZNEmptyDataSetDelegate {
    
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
        self.didTapEmptyView.accept(())
    }
}
