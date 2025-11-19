//
//  LoggerListController.swift
//  AppStart
//
//  Created by hubin.h on 2021/9/30.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import CocoaLumberjack

// MARK: - main class
class LoggerListController: ViewController {

    open lazy var logFiles: [DDLogFileInfo] = {
        return LoggerManager.shared.currentFileLogger.logFileManager.sortedLogFileInfos
    }()
    
    open lazy var listView: UITableView = {
        let listView = UITableView.init(frame: CGRect(x: 0, y: kNavBarAndSafeHeight, width: kScreenW, height: kScreenH - kNavBarAndSafeHeight - kBottomSafeHeight), style: .plain)
        listView.register(UITableViewCell.self, forCellReuseIdentifier: NSStringFromClass(UITableViewCell.self))
        listView.tableFooterView = UIView.init(frame: CGRect.zero)
        listView.dataSource = self
        listView.delegate = self
        listView.rowHeight = 50
        return listView
    }()
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.naviBar.title = L10n.stringLogList
        self.view.addSubview(listView)
        LoggerManager.shared.removeEntrance()
        // DDLogInfo("LoggerManager LogFiles Count:\(logFiles.count)")
    }
    
    deinit {
        LoggerManager.shared.entrance()
    }
}

// MARK: - private mothods
extension LoggerListController {
    
}

// MARK: - call backs
extension LoggerListController {
    
}

// MARK: - delegate or data source
extension LoggerListController: UITableViewDataSource, UITableViewDelegate {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        logFiles.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let file = logFiles[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(UITableViewCell.self), for: indexPath)
        var logdate = (file.creationDate ?? Date()).format()
        if indexPath.row == 0 {
            logdate = L10n.stringLatest + ": " + logdate
        }
        cell.textLabel?.text = logdate
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let detailVc = LoggerDetailController()
        detailVc.file = logFiles[indexPath.row]
        self.navigationController?.pushViewController(detailVc, animated: true)
    }
}

// MARK: - other classes
class LoggerDetailController: ViewController {

    var file: DDLogFileInfo?
    open lazy var logTextView: UITextView = {
        let _logTextView = UITextView.init(frame: CGRect(x: 0, y: kNavBarAndSafeHeight, width: kScreenW, height: kScreenH - kNavBarAndSafeHeight - kBottomSafeHeight))
        _logTextView.isEditable = false
        return _logTextView
    }()
    
    lazy var shareButton: UIButton = {
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.tintColor = .black
        button.addTarget(self, action: #selector(shareFile), for: .touchUpInside)
        return button
    }()
    
    lazy var fileButton: UIButton = {
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 44 + 4, y: 0, width: 44, height: 44)
        button.setImage(UIImage(systemName: "tray.and.arrow.down"), for: .normal)
        button.tintColor = .black
        button.addTarget(self, action: #selector(saveToFile), for: .touchUpInside)
        return button
    }()
    
    lazy var titleView: UIView = {
        let _titleView = UIView(frame: CGRect(x: 0, y: 0, width: 88 + 4, height: 44))
        _titleView.addSubview(shareButton)
        _titleView.addSubview(fileButton)
        return _titleView
    }()

    open override func viewDidLoad() {
        super.viewDidLoad()
        self.naviBar.title = L10n.stringLogDetails
        self.naviBar.setRightView(titleView)
        self.view.addSubview(logTextView)
        if let fpath = file?.filePath, let fdata = try? Data.init(contentsOf: URL.init(fileURLWithPath: fpath)) {
            logTextView.text = String(data: fdata, encoding: .utf8)
        }
    }

    @objc func shareFile() {
        //self.logTextView.scrollRangeToVisible(NSRange(location: self.logTextView.text.count - 1, length: 1))
        guard let fpath = file?.filePath else { return }
        let fUrl = URL(fileURLWithPath: fpath)
        self.shareLogFile(at: fUrl, from: self)
    }

    @objc func saveToFile() {
        guard let fpath = file?.filePath else { return }
        let fUrl = URL(fileURLWithPath: fpath)
        let documentVc: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            documentVc = UIDocumentPickerViewController(forExporting: [fUrl])
        } else {
            documentVc = UIDocumentPickerViewController(url: fUrl, in: .exportToService)
        }
        documentVc.delegate = self
        documentVc.modalPresentationStyle = .pageSheet
        self.navigationController?.present(documentVc, animated: true, completion: nil)
    }
    
    // 文件分享
    func shareLogFile(at fileURL: URL, from viewController: UIViewController) {
        // 准备分享内容
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        // iPad 适配 - 需要弹出源视图
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        // 弹出分享面板
        viewController.present(activityVC, animated: true, completion: nil)
    }
}

extension LoggerDetailController: UIDocumentPickerDelegate {

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let auth = urls.first?.startAccessingSecurityScopedResource(), auth else {
            print("授权失败")
            return
        }
        // 通过文件协调工具来得到新的文件地址，以此得到文件保护功能
        let fileCoordinator = NSFileCoordinator.init()
        var error: NSError?
        fileCoordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { newUrl in
            let fileName = newUrl.lastPathComponent
            print("文件名" + fileName)
        }
        urls.first?.stopAccessingSecurityScopedResource()
    }
}
