//
//  BaseModuleSpec.swift
//  AppStart Tests
//
//  Base：导航、注入、TabBar 边界、Web 策略与活跃扩展回归。

import Quick
import Nimble
import UIKit
@testable import AppStart

private final class DummyScene: SceneProvider {
    let getSegue: UIViewController?
    init(_ viewController: UIViewController?) {
        getSegue = viewController
    }
}

private final class InjectedViewModel: ViewModel {
    let token: String
    init(token: String) {
        self.token = token
        super.init()
    }
    required init() {
        self.token = "default"
        super.init()
    }
}

@MainActor
private final class DummyProvider: ViewModelProvider {
    typealias ViewModelType = InjectedViewModel
    var viewModel: ViewModel?
}

class BaseModuleSpec: QuickSpec {

    override class func spec() {

        describe("UIColor hex") {
            it("parses prefixed and bare 6-digit values") {
                expect(UIColor(strictHexStr: "#FF0000")).toNot(beNil())
                expect(UIColor(strictHexStr: "0x00FF00")).toNot(beNil())
                expect(UIColor(strictHexStr: "0000FF")).toNot(beNil())
            }

            it("rejects invalid input on the strict initializer") {
                expect(UIColor(strictHexStr: "FFF")).to(beNil())
                expect(UIColor(strictHexStr: "not-a-color")).to(beNil())
                expect(UIColor(strictHexStr: "#GG0000")).to(beNil())
            }

            it("keeps the compatibility initializer for existing constants") {
                expect(UIColor(hexStr: "#112233")).toNot(beNil())
            }
        }

        describe("typed table dequeue") {
            it("returns the registered cell for the requested index path") {
                waitUntil { done in
                    Task { @MainActor in
                        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), style: .plain)
                        tableView.registerCell(UITableViewCell.self)
                        let cell = tableView.getReusableCell(IndexPath(row: 0, section: 0), UITableViewCell.self)
                        expect(cell).to(beAKindOf(UITableViewCell.self))
                        done()
                    }
                }
            }
        }

        describe("ViewModelProvider") {
            it("returns the injected view model") {
                waitUntil { done in
                    Task { @MainActor in
                        let provider = DummyProvider()
                        let viewModel = InjectedViewModel(token: "injected")
                        provider.viewModel = viewModel
                        expect(provider.vm.token) == "injected"
                        done()
                    }
                }
            }

            it("fails when the injected view model type is wrong") {
                waitUntil { done in
                    Task { @MainActor in
                        let provider = DummyProvider()
                        provider.viewModel = ViewModel()
                        expect { _ = provider.vm }.to(throwAssertion())
                        done()
                    }
                }
            }
        }

        describe("TabBarController addChildVcs") {
            it("rejects mismatched image arrays") {
                waitUntil { done in
                    Task { @MainActor in
                        let tabBar = TabBarController()
                        tabBar.addChildVcs(
                            naviVcs: [UIViewController(), UIViewController()],
                            titles: ["A", "B"],
                            normalImages: [nil],
                            selectImages: [nil]
                        )
                        expect(tabBar.viewControllers).to(beNil())
                        done()
                    }
                }
            }

            it("accepts title-only tabs") {
                waitUntil { done in
                    Task { @MainActor in
                        let first = UIViewController()
                        let second = UIViewController()
                        let tabBar = TabBarController()
                        tabBar.addChildVcs(
                            naviVcs: [first, second],
                            titles: ["A", "B"],
                            normalImages: [],
                            selectImages: []
                        )
                        expect(tabBar.viewControllers?.count) == 2
                        expect(first.tabBarItem.title) == "A"
                        done()
                    }
                }
            }
        }

        describe("Navigator") {
            it("sets presentation style on the alert target") {
                waitUntil { done in
                    Task { @MainActor in
                        let sender = UIViewController()
                        sender.modalPresentationStyle = .fullScreen
                        let target = UIViewController()
                        Navigator.default.show(
                            provider: DummyScene(target),
                            sender: sender,
                            transition: .alert(type: .formSheet)
                        )
                        expect(target.modalPresentationStyle) == .formSheet
                        expect(sender.modalPresentationStyle) == .fullScreen
                        done()
                    }
                }
            }

            it("pushes synchronously onto a navigation stack") {
                waitUntil { done in
                    Task { @MainActor in
                        let root = ViewController()
                        let navigation = NavigationController(rootViewController: root)
                        let target = ViewController()
                        Navigator.default.show(
                            provider: DummyScene(target),
                            sender: navigation,
                            transition: .navigation
                        )
                        expect(navigation.topViewController) === target
                        done()
                    }
                }
            }
        }

        describe("WKWebController navigation policy") {
            it("allows file http and https by default") {
                waitUntil { done in
                    Task { @MainActor in
                        let web = WKWebController()
                        expect(web.shouldAllowNavigation(to: URL(string: "https://example.com")!)) == true
                        expect(web.shouldAllowNavigation(to: URL(string: "http://example.com")!)) == true
                        expect(web.shouldAllowNavigation(to: URL(fileURLWithPath: "/tmp/index.html"))) == true
                        done()
                    }
                }
            }

            it("cancels custom schemes and untrusted hosts") {
                waitUntil { done in
                    Task { @MainActor in
                        let web = RestrictedWebController()
                        expect(web.shouldAllowNavigation(to: URL(string: "my-app://open")!)) == false
                        expect(web.shouldAllowNavigation(to: URL(string: "https://evil.example")!)) == false
                        expect(web.shouldAllowNavigation(to: URL(string: "https://trusted.example")!)) == true
                        done()
                    }
                }
            }

            it("rejects remote bridge messages unless the host is trusted") {
                waitUntil { done in
                    Task { @MainActor in
                        let web = RestrictedWebController()
                        expect(web.shouldAcceptBridgeMessage(from: URL(fileURLWithPath: "/tmp/index.html"))) == true
                        expect(web.shouldAcceptBridgeMessage(from: URL(string: "https://trusted.example")!)) == true
                        expect(web.shouldAcceptBridgeMessage(from: URL(string: "https://evil.example")!)) == false
                        expect(web.shouldAcceptBridgeMessage(from: nil)) == false
                        done()
                    }
                }
            }

            it("parses object and JSON string bridge bodies") {
                waitUntil { done in
                    Task { @MainActor in
                        let web = JSWebController(viewModel: JSWebViewModel(symbol: "LUTE_NATIVE"))
                        let object = web.bridgeMessage(from: ["method": "ping", "params": "1"])
                        let json = web.bridgeMessage(from: #"{"method":"pong","params":{"a":1}}"#)
                        expect(object?["method"] as? String) == "ping"
                        expect(json?["method"] as? String) == "pong"
                        expect(web.bridgeMessage(from: "not-json")).to(beNil())
                        done()
                    }
                }
            }

            it("keeps web delegates after disappearing") {
                waitUntil { done in
                    Task { @MainActor in
                        let web = WKWebController()
                        web.loadViewIfNeeded()
                        expect(web.wkWebView.navigationDelegate).toNot(beNil())
                        web.viewWillDisappear(false)
                        expect(web.wkWebView.navigationDelegate).toNot(beNil())
                        expect(web.wkWebView.uiDelegate).toNot(beNil())
                        done()
                    }
                }
            }
        }
    }
}

@MainActor
private final class RestrictedWebController: WKWebController {
    override var allowedNavigationHosts: Set<String>? {
        ["trusted.example"]
    }

    override var trustedBridgeHosts: Set<String> {
        ["trusted.example"]
    }
}
