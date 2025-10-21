//
//  TableViewCell.swift
//  Momcozy
//
//  Created by hubin.h on 2024/9/23.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation

// MARK: - global var and methods
open class TableViewCellViewModel: NSObject {}

/// 自定义next Cell
open class TableViewCell: UITableViewCell {
    
    // 右箭头 ">"
    public lazy var arrowView: UIImageView = {
        let _nextImgView = UIImageView(image: UIImage.bundleImage(named: "icon_arrow")?.adaptRTL)
        _nextImgView.frame = CGRect(x: 0, y: 0, width: 15, height: 15)
        _nextImgView.contentMode = .scaleAspectFit
        return _nextImgView
    }()
    
    // 固定accessoryView位置
    open override func layoutSubviews() {
        super.layoutSubviews()
        if let accessoryView = self.accessoryView {
            var tFrame = accessoryView.frame
            tFrame.origin.x = isRTL ? 15: frame.size.width - 30
            accessoryView.frame = tFrame
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
