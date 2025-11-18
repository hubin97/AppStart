//
//  TableViewExposureAble.swift
//  Momcozy
//
//  Created by hubin.h on 2024/11/14.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation
import RxRelay

/**
 使用示例:
 // 是否开启cell曝光
 var isCellExposureEnabled: Bool = false
 // 上次曝光消息序列
 var lastExposureIndexPaths: [IndexPath] = []
 // 曝光消息序列,
 var exposureIndexPathsRelay = BehaviorRelay<[IndexPath]?>(value: nil)
 
 // `UIScrollViewDelegate`
 func scrollViewDidScroll(_ scrollView: UIScrollView) {
     guard scrollView == tableView else { return }
     if isCellExposureEnabled {
         self.updateTableViewExposure()
     }
 }
 
 // 订阅曝光, 回调 indexPaths
 exposureIndexPathsRelay
     .asDriver(onErrorJustReturn: nil)
     .drive(onNext: {[weak self] indexPaths in
         guard let self, let indexPaths, !indexPaths.isEmpty else { return }
         // do something
         // 打印 exposureIndexPathsRelay...
     }).disposed(by: rx.disposeBag)

 //
 exposureIndexPathsRelay: [0, 1, 2] ["2024 Mother\'s day Gift", "礼盒35", "大撒大撒"]
 exposureIndexPathsRelay: [3] ["礼盒34"]
 exposureIndexPathsRelay: [4] ["礼盒9"]
 exposureIndexPathsRelay: [5] ["测试礼盒32"]
 exposureIndexPathsRelay: [6] ["礼盒7"]
 exposureIndexPathsRelay: [7] ["礼盒ys4"]
 exposureIndexPathsRelay: [8] ["礼盒ys3"]
 exposureIndexPathsRelay: [9] ["礼盒ys2"]
 exposureIndexPathsRelay: [10] ["礼盒配置ys"]
 */

/// TableView曝光协议
public protocol TableViewExposureAble: AnyObject {
    /// 关联的TableView
    var tableView: TableView { get }
    /// 是否开启cell曝光
    var isCellExposureEnabled: Bool { get set }
    /// 上次曝光消息序列
    var lastExposureIndexPaths: [IndexPath] { get set }
    /// 曝光消息序列
    var exposureIndexPathsRelay: BehaviorRelay<[IndexPath]?> { get }
    
    /// 更新曝光消息序列
    func updateTableViewExposure()
}

// MARK: - call backs
extension TableViewExposureAble {
    
    /// 更新曝光消息序列
    /// 1.下拉刷新时, 重置曝光消息序列
    /// 2.scrollViewDidScroll时, 更新曝光消息序列
    public func updateTableViewExposure() {
        guard isCellExposureEnabled else { return }
        
        let visibleCells = self.tableView.visibleCells
        
        var fullyVisibleIndexPaths: [IndexPath] = []
        for cell in visibleCells {
            if let indexPath = self.tableView.indexPath(for: cell) {
                let cellRect = self.tableView.rectForRow(at: indexPath)
                let visibleRect = self.tableView.bounds
                // 检查单元格是否完全在可见区域内
                if visibleRect.contains(cellRect) {
                    fullyVisibleIndexPaths.append(indexPath)
                }
            }
        }
        // 曝光消息序列
        if fullyVisibleIndexPaths.count > 0 {
            // 比较当前可见模型数组和上一次可见模型数组, 去掉重复的
            if lastExposureIndexPaths.count > 0 {
                let newIndexPaths = fullyVisibleIndexPaths.filter { !lastExposureIndexPaths.contains($0) }
                if newIndexPaths.count > 0 {
                    lastExposureIndexPaths = fullyVisibleIndexPaths
                    exposureIndexPathsRelay.accept(newIndexPaths)
                }
            } else {
                lastExposureIndexPaths = fullyVisibleIndexPaths
                exposureIndexPathsRelay.accept(fullyVisibleIndexPaths)
            }
        }
    }
}
