//
//  Extension+TableView.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

//单元测试 ✅
import Foundation

//MARK: - global var and methods
fileprivate typealias Extension_TableView = UITableView

//MARK: - main class
extension Extension_TableView {

    /// 根据cell子视图获取IndexPath?
    /// - Parameter subView: 子视图
    /// - Returns: IndexPath?
    public func indexPath(subView: UIView) -> IndexPath? {
        return self.indexPathForRow(at: subView.convert(CGPoint.zero, to: self))
    }
    
    ///  清空所有选中行状态.
    /// - Parameter animated: defalut true
    public func clearSelectedRowsAnimated(_ animated: Bool = true) {
        let indexs = self.indexPathsForSelectedRows
        indexs?.forEach({ (path) in
            self.deselectRow(at: path, animated: animated)
        })
    }
    
    /// 根据cell子视图获取当前UITableViewCell?
    /// - Parameter subView: 子视图
    /// - Returns: UITableViewCell?
    public func getCell(subView: UIView) -> UITableViewCell? {
        guard let indexPath = self.indexPath(subView: subView) else { return nil }
        return self.cellForRow(at: indexPath)
    }
    
    /// 便捷注册cell
    /// - Parameter type: cell类
    public func registerCell<T: UITableViewCell>(_ type: T.Type) {
        self.register(T.self, forCellReuseIdentifier: NSStringFromClass(T.self))
    }
    
    /// 获取复用cell(legacy)
    /// - Parameters:
    ///   - type: cell类
    /// - Returns: 复用cell
    @available(*, deprecated, message: "Use getReusableCell(_:_) with indexPath in cellForRowAt; Apple 在 cellForRowAt 里推荐 for: indexPath 版本：和复用池、预取、高度计算等机制一致；无 indexPath 的版本更适合 legacy 场景，不是 dataSource 首选")
    public func getReusableCell<T: UITableViewCell>(_ type: T.Type) -> T {
        let identifier = NSStringFromClass(T.self)
        guard let cell = self.dequeueReusableCell(withIdentifier: identifier) as? T else {
            preconditionFailure("Expected \(T.self) for table cell identifier \(identifier). Check the registered cell type.")
        }
        return cell
    }

    /// 获取复用cell
    /// - Parameters:
    ///   - indexPath: cell位置
    ///   - type: cell类
    /// - Returns: 复用cell
    public func getReusableCell<T: UITableViewCell>(_ indexPath: IndexPath, _ type: T.Type) -> T {
        let identifier = NSStringFromClass(T.self)
        // FIXME: Apple 在 cellForRowAt 里推荐 for: indexPath 版本：和复用池、预取、高度计算等机制一致；无 indexPath 的版本更适合 legacy 场景，不是 dataSource 首选。
        guard let cell = self.dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? T else {
            preconditionFailure("Expected \(T.self) for table cell identifier \(identifier). Check the registered cell type.")
        }
        return cell
    }

    /// 便捷注册段头/尾视图
    public func registerView<T: UITableViewHeaderFooterView>(_ type: T.Type) {
        self.register(T.self, forHeaderFooterViewReuseIdentifier: NSStringFromClass(T.self))
    }

    /// 获取复用段头/尾视图
    public func getReusableView<T: UITableViewHeaderFooterView>( _ type: T.Type) -> T {
        let identifier = NSStringFromClass(T.self)
        guard let view = self.dequeueReusableHeaderFooterView(withIdentifier: identifier) as? T else {
            preconditionFailure("Expected \(T.self) for table header/footer identifier \(identifier). Check the registered view type.")
        }
        return view
    }
}

//MARK: - call backs
extension Extension_TableView {
    
}

//MARK: - delegate or data source
extension Extension_TableView {
    
}

//MARK: - other classes
//MARK: - UICollectionView复用注入
extension UICollectionView {

    /// 段头/尾复用标识
    public enum ReusableKind {
        case header //= elementKindSectionHeader
        case footer //= .elementKindSectionFooter
        var rawValue: String {
            switch self {
            case .header:
                return UICollectionView.elementKindSectionHeader
            case .footer:
                return UICollectionView.elementKindSectionFooter
            }
        }
    }

    /// 便捷注册cell
    /// - Parameter type: cell类
    public func registerCell<T: UICollectionViewCell>(_ type: T.Type) {
        self.register(T.self, forCellWithReuseIdentifier: NSStringFromClass(T.self))
    }
    
    /// 获取复用cell
    /// - Parameter type: cell类
    /// - Returns: 复用cell
    public func getReusableCell<T: UICollectionViewCell>(_ indexPath: IndexPath, _ type: T.Type) -> T {
        let identifier = NSStringFromClass(T.self)
        guard let cell = self.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath) as? T else {
            preconditionFailure("Expected \(T.self) for collection cell identifier \(identifier). Check the registered cell type.")
        }
        return cell
    }

    /// 便捷注册段头/尾视图
    public func registerView<T: UICollectionReusableView>(_ kind: UICollectionView.ReusableKind, _ type: T.Type) {
        self.register(T.self, forSupplementaryViewOfKind: kind.rawValue, withReuseIdentifier: NSStringFromClass(T.self))
    }

    /// 获取复用段头/尾视图
    public func getReusableView<T: UICollectionReusableView>(_ kind: UICollectionView.ReusableKind, _ indexPath: IndexPath, _ type: T.Type) -> T {
        let identifier = NSStringFromClass(T.self)
        guard let view = self.dequeueReusableSupplementaryView(ofKind: kind.rawValue, withReuseIdentifier: identifier, for: indexPath) as? T else {
            preconditionFailure("Expected \(T.self) for collection supplementary identifier \(identifier) of kind \(kind.rawValue). Check the registered view type.")
        }
        return view
    }
}
