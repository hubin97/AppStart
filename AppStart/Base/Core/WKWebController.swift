//
//  WKWebController.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/13.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import UIKit
import WebKit
import SnapKit

// MARK: - global var and methods

// MARK: - main class
open class WKWebController: ViewController, WKWebScriptMsgHandleAble {

    // 退出web容器返回回调
    public var exitWebBlock: (() -> Void)?
    
    //
    public var wkMethodName: String?
    public var wkReceiveDataBlock: WKReceiveBlock?

    /// 允许在容器内导航的 URL scheme。
    open var allowedNavigationSchemes: Set<String> {
        ["file", "http", "https"]
    }

    /// 允许导航的远程 host；nil 表示不限制 http/https host。
    ///
    /// 加载第三方内容的业务容器可重写此属性，将页面导航限制在受控域名内。
    open var allowedNavigationHosts: Set<String>? {
        nil
    }

    /// 允许调用 Native bridge 的远程 host；本地 file URL 默认可信。
    ///
    /// 远程页面默认不能调用 bridge，业务容器必须显式提供可信 host。
    open var trustedBridgeHosts: Set<String> {
        []
    }
    
    /// 是否使用web页标题 `仅控制首次加载, 若是页面重定向或者页面跳转, 标题跟随web页变更`
    private var useWebTitle: Bool = true

    private var urlPath: String? {
        didSet {
            if let urlPath = urlPath {
                // print("HTML_PATH>> \(urlPath)")
                self.loadWeb(urlPath: urlPath)
            }
        }
    }
    
    /// 特定配置
    public lazy var wkConfig: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration.init()
        config.preferences = WKPreferences()
        config.preferences.minimumFontSize = 10
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // web页视频内联播放支持必须加上下面两行,这点与Safari不一样
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        //config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let js_source = "document.documentElement.style.webkitTouchCallout='none';" + "document.documentElement.style.webkitUserSelect='none';"
        let userScript = WKUserScript.init(source: js_source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        return config
    }()
    
    /// 容器
    @objc // !!!!: 必要的
    public lazy var wkWebView: WKWebView = {
        let wkWebView = WKWebView(frame: .zero, configuration: self.wkConfig)
        wkWebView.uiDelegate = self
        wkWebView.navigationDelegate = self
        wkWebView.scrollView.delegate = self
        if #available(iOS 11.0, *) {
            wkWebView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            self.automaticallyAdjustsScrollViewInsets = false
        }
#if DEBUG
        // FIXME: debug模式开启webView->Safari调试功能
        if #available(iOS 16.4, *) {
            wkWebView.isInspectable = true
        }
#endif
        return wkWebView
    }()
    
    /// 是否隐藏导航栏左侧视图(`返回按钮`), 注意仅首个页面有效(即`self.wkWebView.backForwardList.backList.isEmpty`)
    public var isHideLeftView: Bool = false
    
    // ----
    /// 是否显示进度条
    public var showProgress: Bool = true
    /// 进度条背景色
    public var progressViewBackColor: UIColor? {
        didSet {
            progressView.trackTintColor = progressViewBackColor
        }
    }
    /// 进度条填充色
    public var progressViewTintColor: UIColor? {
        didSet {
            progressView.tintColor = progressViewTintColor
        }
    }
    /// 进度条高度
    public var progressViewHeight: CGFloat? {
        didSet {
            if let height = progressViewHeight {
                progressViewHeightConstraint?.update(offset: height)
            }
        }
    }
    
    fileprivate lazy var progressView: UIProgressView = {
        ///UIProgressView的高度设置无效, 且 iOS14高度还有变化
        let _progressView = UIProgressView(progressViewStyle: .bar)
        _progressView.progressViewStyle = .bar
        _progressView.tintColor = .systemBlue
        _progressView.backgroundColor = .lightGray
        _progressView.isHidden = true
        return _progressView
    }()
    
    var titleObervation: NSKeyValueObservation?
    var progressObervation: NSKeyValueObservation?
    private var progressViewHeightConstraint: Constraint?

    lazy var backButton: UIButton = {
        let _backButton = UIButton(type: .custom)
        _backButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        _backButton.setImage(Asset.iconLeftBlack.image.adaptRTL, for: .normal)
        _backButton.addTarget(self, action: #selector(backAction(_:)), for: .touchUpInside)
        return _backButton
    }()
  
    lazy var naviLeftView: UIView = {
        let _backButton = UIButton(type: .custom)
        _backButton.setImage(Asset.iconLeftBlack.image.adaptRTL, for: .normal)
        _backButton.addTarget(self, action: #selector(backAction(_:)), for: .touchUpInside)

        let _closeButton = UIButton(type: .custom)
        _closeButton.setImage(Asset.iconCloseBlack.image.adaptRTL, for: .normal)
        _closeButton.addTarget(self, action: #selector(closeAction(_:)), for: .touchUpInside)

        let _naviLeftView = UIView(frame: CGRect(x: 10, y: 0, width: 88, height: 44))
        _naviLeftView.addSubview(_backButton)
        _naviLeftView.addSubview(_closeButton)
        _backButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.height.equalTo(44)
        }
        _closeButton.snp.makeConstraints { make in
            make.leading.equalTo(_backButton.snp.trailing)
            make.top.bottom.trailing.equalToSuperview()
            make.width.height.equalTo(44)
        }
        return _naviLeftView
    }()
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.naviBar.setLeftView(self.backButton)
        self.view.addSubview(self.wkWebView)
        self.view.addSubview(self.progressView)

        self.wkWebView.snp.makeConstraints { make in
            make.top.equalTo(self.naviBar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        self.progressView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(self.wkWebView)
            self.progressViewHeightConstraint = make.height.equalTo(self.progressViewHeight ?? 1).constraint
        }
        
        self.view.backgroundColor = .white
        self.wkWebView.navigationDelegate = self
        self.progressViewHeight = 1
        self.progressViewTintColor = .systemBlue
        
        self.addObserver()
    }
    
    @objc open func backAction(_ sender: UIButton) {
        if self.wkWebView.canGoBack {
            self.wkWebView.goBack()
            // 规避毒瘤页面无法返回的问题 (始终返回 canGoBack:true)
            self.updateBackForwardState()
        } else {
            super.backAction()
            self.exitWebBlock?()
        }
    }
    
    @objc open func closeAction(_ sender: UIButton) {
        super.backAction()
        self.exitWebBlock?()
    }
    
    open override func popGestureAction() {
        self.exitWebBlock?()
    }
    
    // 如果返回历史记录不为空, 则显示关闭按钮
    // https://www.facebook.com/groups/momcozyusercenter?utm_source=user+center&utm_medium=app&utm_campaign=app-banner&Language=zh-CN
    func updateBackForwardState() {
        let isLast = self.wkWebView.backForwardList.backList.isEmpty
        if isHideLeftView && isLast {
            self.naviBar.leftView?.isHidden = true
        } else {
            self.naviBar.setLeftView(isLast ? backButton: naviLeftView)
        }
    }

    /// 判断 WebView 是否允许导航到指定 URL。
    ///
    /// 默认允许 file/http/https；业务容器可通过 allowedNavigationHosts 限制远程域名。
    open func shouldAllowNavigation(to url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              allowedNavigationSchemes.contains(scheme) else {
            return false
        }
        guard scheme == "http" || scheme == "https",
              let allowedNavigationHosts else {
            return true
        }
        guard let host = url.host?.lowercased() else { return false }
        return allowedNavigationHosts.contains { $0.lowercased() == host }
    }

    /// 判断当前页面是否允许向 Native bridge 发送消息。
    open func shouldAcceptBridgeMessage(from url: URL?) -> Bool {
        guard let url else { return false }
        if url.isFileURL { return true }
        guard let host = url.host?.lowercased() else { return false }
        return trustedBridgeHosts.contains { $0.lowercased() == host }
    }
}

// MARK: - private mothods
extension WKWebController {
    
    func addObserver() {
        self.progressObervation = self.observe(\.wkWebView.estimatedProgress, options: [.old, .new]) { (_, change) in
            let newValue: Float = Float(change.newValue ?? 0)
            let oldValue: Float = Float(change.oldValue ?? 0)
            Task { @MainActor [weak self] in
                guard let self, newValue > oldValue && newValue > 0.1 else { return }
                print("newValue>>\(newValue)")
                self.progressView.isHidden = false
                self.progressView.setProgress(newValue, animated: true)
                if newValue >= 1.0 {
                    UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseInOut) {
                        self.progressView.isHidden = true
                    } completion: { finish in
                        if finish {
                            self.progressView.setProgress(0.0, animated: false)
                        }
                    }
                }
            }
        }
        
        self.titleObervation = self.observe(\.wkWebView.title, options: [.old, .new], changeHandler: { [weak self] (_, change) in
            guard let title = change.newValue else { return }
            print("Title changed: \(title ?? "")")
            Task { @MainActor [weak self] in
                guard let self, self.useWebTitle else { return }
                self.naviBar.title = title
            }
        })
    }
    
    /// 安全加载网页，本地或远程
    /// - Parameters:
    ///   - urlPath: 本地文件名（带扩展）或远程 URL
    ///   - isLocal: 是否本地 HTML 文件
    ///   - cachePolicy: 远程 URL 请求缓存策略
    ///   - timeout: 远程 URL 超时时间
    /// - Returns: 实际加载的 URL，如果失败返回 nil
    @discardableResult
    public func loadWeb(urlPath: String,
                        isLocal: Bool = false,
                        cachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy,
                        timeout: TimeInterval = 20.0) -> URL? {
        
        print("LOAD_WEB_PATH >> \(urlPath)")
        
        if isLocal {
            // 尝试从主工程 Bundle 找
            let mainBundle = Bundle.main
            let fileName = (urlPath as NSString).deletingPathExtension
            let fileExtension = (urlPath as NSString).pathExtension
            
            guard let fileURL = mainBundle.url(forResource: fileName, withExtension: fileExtension) else {
                print("❌ 本地文件未找到：\(urlPath)")
                return nil
            }
            
            // 授权 WKWebView 访问同一目录，支持子目录资源
            let readAccessURL = fileURL.deletingLastPathComponent()
            
            // 避免加载空白或沙盒错误，确保 URL 有效
            wkWebView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
            return fileURL
            
        } else {
            // 远程 URL
            guard let url = URL(string: urlPath) else {
                print("❌ 无效远程 URL：\(urlPath)")
                return nil
            }
            let request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeout)
            wkWebView.load(request)
            return url
        }
    }
    
    public func setUrlPath(_ urlPath: String) {
        self.urlPath = urlPath
    }
    
    public func setTitle(_ title: String?) {
        if let title = title {
            self.useWebTitle = false
            self.naviBar.title = title
        }
    }
}

// MARK: - call backs
extension WKWebController: UIScrollViewDelegate {
    
    // 调整webview滚动速率
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollView.decelerationRate = .normal //.fast 惯性变小
        //print("wkWebView#scrollViewWillBeginDragging--")
    }
}

// MARK: - WKWebScriptMsgHandleAble
extension WKWebController {
    
    open func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let methodName = self.wkMethodName, methodName.isEmpty == false && methodName == message.name else { return }
        self.wkReceiveDataBlock?(methodName, message.body)
    }
}

// MARK: - delegate or data source
extension WKWebController: WKUIDelegate, WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if self.useWebTitle {
            self.naviBar.title = webView.title
        }
        self.updateBackForwardState()
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.progressView.isHidden = true
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 本地加载时会打印, 可以忽略 ?
        print("webView:didFailProvisionalNavigation: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              shouldAllowNavigation(to: url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
    
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
    
    // FIXME: 有些链接可能尝试在新窗口打开(即"_blank")，需要特别处理：
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            // LogM.debug("开启新标签窗口")
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - Weak wrapper
@MainActor
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - WKWebScriptMsgHandleAble
@MainActor
public protocol WKWebScriptMsgHandleAble: WKScriptMessageHandler {
    
    typealias WKReceiveBlock = ((_ action: String, _ param: Any) -> Void)
    
    /// Web容器
    var wkWebView: WKWebView { get set }
    /// 特定配置
    var wkConfig: WKWebViewConfiguration { get set }
    
    /// 指定需要监听的脚本方法名
    var wkMethodName: String? { get set }
    /// 实现方法监听, 通过Block回调
    var wkReceiveDataBlock: WKReceiveBlock? { get set }
}

extension WKWebScriptMsgHandleAble {

    /// JS注入回调
    /// - Parameters:
    ///   - jsCode: js代码字符串
    ///   - completeBlock: 回调
    /// - Returns: block
    public func evaluateJs(jsCode: String, completeBlock: ((_ result: Any?, _ error: Error?) -> Void)?) {
        self.wkWebView.evaluateJavaScript(jsCode) { (result, error) in
            completeBlock?(result, error)
        }
    }
    
    /// 建议只注册一个标识, 通过配置的参数体区分调用即可
//    public func addMethod(name: String) {
//        self.wkMethodName = name
//        self.wkConfig.userContentController.add(self, name: name)
//    }
    
    /// 自动用 WeakScriptMessageHandler 包装，避免循环引用
    public func addMethod(name: String) {
        if let currentName = self.wkMethodName {
            self.wkConfig.userContentController.removeScriptMessageHandler(forName: currentName)
        }
        self.wkMethodName = name
        self.wkConfig.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: name
        )
    }
    
    /// 回调到外部 message.body可以固定格式: {"action":"xxx","param":{}}
    public func addMethod(name: String, completeBlock: ((_ action: String, _ param: Any) -> Void)?) {
        self.wkReceiveDataBlock = completeBlock
        self.addMethod(name: name)
    }
    
    public func removeMethod(name: String) {
        self.wkConfig.userContentController.removeScriptMessageHandler(forName: name)
        if self.wkMethodName == name {
            self.wkMethodName = nil
            self.wkReceiveDataBlock = nil
        }
    }
    
    public func removeAllMethods() {
        guard let methodName = self.wkMethodName else { return }
        self.removeMethod(name: methodName)
    }

    /// 移除通过配置注入的全部 user script。
    public func removeAllUserScripts() {
        self.wkConfig.userContentController.removeAllUserScripts()
    }
}
