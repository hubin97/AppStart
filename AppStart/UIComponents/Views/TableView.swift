//
//  TableView.swift
//  AppStart
//
//  Created by hubin.h on 2024/8/13.
//  Copyright © 2020 路特创新. All rights reserved.

import Foundation
import MJRefresh
import DZNEmptyDataSet

/// 1. 扩展下拉刷新, 上拉加载方法
/// 2. 添加通用空白占位控件, 以及点击事件
///
open class TableView: UITableView {
    
    enum BackgroundMode {
        case fill       // 铺满（可能拉伸/裁剪）
        case tile       // 平铺（保持纹理原始大小）
        case center     // 居中（不拉伸）
    }
    
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
    /// `EmptyView`是否显示条件
    public var emptyDataSetShouldDisplay: Bool = true
    
    /// `EmptyView`标题默认属性
    public var atattributesForTitle = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 15), NSAttributedString.Key.foregroundColor: UIColor(hexStr: "#999999")]

    public override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
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
extension TableView: DZNEmptyDataSetSource, DZNEmptyDataSetDelegate {
    
    public func image(forEmptyDataSet scrollView: UIScrollView!) -> UIImage! {
        return self.imageForEmptyDataSet ?? Asset.iconNullData.image
    }
    public func title(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        return self.titleForEmptyDataSet ?? NSAttributedString(string: L10n.stringNotRecordYetTips, attributes: atattributesForTitle)
    }
    public func verticalOffset(forEmptyDataSet scrollView: UIScrollView!) -> CGFloat {
        return self.verticalOffset
    }
    public func emptyDataSet(_ scrollView: UIScrollView!, didTap view: UIView!) {
        self.didTapEmptyViewBlock?()
    }
    public func emptyDataSetShouldDisplay(_ scrollView: UIScrollView!) -> Bool {
        return emptyDataSetShouldDisplay
    }
}

extension UITableView {
    
    // 设置列表背景图, 或者纹理铺满 (注意, 此方案的背景为静态的, 不会跟随列表滚动)
    func setBackground(image: UIImage?, mode: TableView.BackgroundMode) {
        switch mode {
        case .fill:
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            backgroundView = imageView
            
        case .tile:
            let view = UIView()
            view.backgroundColor = UIColor(patternImage: image ?? UIImage())
            backgroundView = view
            
        case .center:
            let imageView = UIImageView(image: image)
            imageView.contentMode = .center
            backgroundView = imageView
        }
        
        // 保证背景随 tableView 大小变化
        backgroundView?.frame = bounds
        backgroundView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}
