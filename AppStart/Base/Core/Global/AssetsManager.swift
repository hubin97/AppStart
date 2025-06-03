//
//  AssetsManager.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
//

import UIKit
import Foundation

/// 参考 R.swift https://github.com/mac-cain13/R.swift
public enum Assets {
    
    enum image {
        static var appIcon = UIImage(named: "iotc")
    }
    
    enum font {
        static func left_menu_logo(_ size: CGFloat) ->UIFont {
            UIFont(name: "Zapfino", size: size)!
        }
    }
    
    enum color {
        static var theme = UIColor.lightGray
    }
}
