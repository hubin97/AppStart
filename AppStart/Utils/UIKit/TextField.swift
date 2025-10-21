//
//  TextField.swift
//  Momcozy
//
//  Created by hubin.h on 2024/8/13.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation

// MARK: - global var and methods

/// 1. 规避智能插入删除, 自动纠正, 拼写检查
///
open class TextField: UITextField {
    
    /// 设置边距
    public var textPadding = UIEdgeInsets.zero
    public var allowCut: Bool = true
    public var allowCopy: Bool = true
    public var allowPast: Bool = true
    public var allowSelect: Bool = true

    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        // FIXME: 修正编辑输入时, 会默认选中多个字符
        /// 关闭智能插入删除
        self.smartInsertDeleteType = .no
        /// 关闭自动纠正
        self.autocorrectionType = .no
        /// 关闭拼写检查
        self.spellCheckingType = .no
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: textPadding)
    }
    
    open override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: textPadding)
    }
    
    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 禁用复制（copy）、选择（select）和全选（selectAll）
        if action == #selector(copy(_:)) && !allowCopy {
            return false
        }
        // 禁用剪切
        if action == #selector(cut(_:)) && !allowCut {
            return false
        }
        // 禁用选择
        if (action == #selector(select(_:)) || action == #selector(selectAll(_:))) && !allowSelect {
            return false
        }
        // 禁用粘贴操作
        if action == #selector(paste(_:)) && !allowPast {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
