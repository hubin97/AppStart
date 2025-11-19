//
//  TableViewCell.swift
//  AppStart
//
//  Created by hubin.h on 2024/9/23.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

// MARK: - global var and methods
open class TableViewCellViewModel: NSObject {}

/// 自定义next Cell
open class TableViewCell: UITableViewCell {
    
    // 默认箭头边距
    public var arrowMargin: CGFloat = 5 {
        didSet { setNeedsLayout() }
    }
    // 默认箭头大小
    public var arrowWidth: CGFloat = 35 {
        didSet { setNeedsLayout() }
    }
    
    // 右箭头 ">"
    public lazy var arrowView: UIImageView = {
        let _nextImgView = UIImageView(image: Asset.iconRightBlack.image.adaptRTL)
        _nextImgView.frame = CGRect(x: 0, y: 0, width: arrowWidth, height: arrowWidth)
        _nextImgView.contentMode = .scaleAspectFit
        return _nextImgView
    }()
    
    // 固定accessoryView位置
    open override func layoutSubviews() {
        super.layoutSubviews()
        if let accessoryView = self.accessoryView {
            let accessoryViewX = isRTL ? arrowMargin: bounds.width - arrowWidth - arrowMargin
            let accessoryViewY = (bounds.height - arrowWidth) / 2
            accessoryView.frame = CGRect(x: accessoryViewX, y: accessoryViewY, width: arrowWidth, height: arrowWidth)
        }
    }
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.accessoryView = arrowView
        self.backgroundColor = .white
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func bind(to viewModel: TableViewCellViewModel) {}
}
