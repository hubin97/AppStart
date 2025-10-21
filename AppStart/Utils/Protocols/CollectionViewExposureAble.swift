//
//  CollectionViewExposureAble.swift
//  Momcozy
//
//  Created by hubin.h on 2024/11/19.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

import Foundation
import RxRelay

/**
 使用示例: 同 `TableViewExposureAble`
*/

/// CollectionView曝光协议
public protocol CollectionViewExposureAble: AnyObject {
    /// 关联的TableView
    var collectionView: CollectionView { get }
    /// 是否开启cell曝光
    var isCellExposureEnabled: Bool { get set }
    /// 上次曝光消息序列
    var lastExposureIndexPaths: [IndexPath] { get set }
    /// 曝光消息序列
    var exposureIndexPathsRelay: BehaviorRelay<[IndexPath]?> { get }
    
    /// 更新曝光消息序列
    func updateCollectionViewExposure()
}

// MARK: - call backs
extension CollectionViewExposureAble {
    
    /// 更新曝光消息序列
    /// 1.下拉刷新时, 重置曝光消息序列
    /// 2.scrollViewDidScroll时, 更新曝光消息序列
    public func updateCollectionViewExposure() {
        guard isCellExposureEnabled else { return }

        let visibleCells = self.collectionView.visibleCells
        
        var fullyVisibleIndexPaths: [IndexPath] = []
        for cell in visibleCells {
            if let indexPath = self.collectionView.indexPath(for: cell) {
                let cellRect = self.collectionView.layoutAttributesForItem(at: indexPath)!.frame
                let visibleRect = self.collectionView.bounds
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
