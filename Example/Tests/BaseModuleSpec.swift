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

        describe("recoverable base extensions") {
            it("returns optional dates for calendar arithmetic") {
                let calendar = Calendar.autoupdatingCurrent
                let date = calendar.date(from: DateComponents(year: 2024, month: 5, day: 15, hour: 12))!

                expect(date.lastMonth).toNot(beNil())
                expect(date.nextMonth).toNot(beNil())
                expect(date.lastWeek).toNot(beNil())
                expect(date.nextWeek).toNot(beNil())
                expect(date.lastDay).toNot(beNil())
                expect(date.nextDay).toNot(beNil())
            }

            it("returns nil when an image has no CG backing") {
                expect(UIImage().horizontalFlip()).to(beNil())
                expect(UIImage().verticalFlip()).to(beNil())
            }

            it("flips a CG-backed image") {
                waitUntil { done in
                    Task { @MainActor in
                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
                        let image = renderer.image { context in
                            UIColor.red.setFill()
                            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
                        }

                        expect(image.horizontalFlip()).toNot(beNil())
                        expect(image.verticalFlip()).toNot(beNil())
                        done()
                    }
                }
            }

            it("handles an empty string when extracting pinyin initials") {
                expect("".toPYHead()) == ""
            }

            it("parses fixed date formats with an explicit locale and time zone") {
                let newYork = TimeZone(identifier: "America/New_York")!
                let locale = Locale(identifier: "en_US_POSIX")
                let summer = "2026-07-01 12:00:00".date(timeZone: newYork, locale: locale)
                let winter = "2026-12-01 12:00:00".date(timeZone: newYork, locale: locale)

                expect(summer).toNot(beNil())
                expect(winter).toNot(beNil())
                expect(newYork.secondsFromGMT(for: summer!)) == -4 * 60 * 60
                expect(newYork.secondsFromGMT(for: winter!)) == -5 * 60 * 60
            }

            it("rejects a nonexistent daylight-saving local time") {
                let newYork = TimeZone(identifier: "America/New_York")!
                let date = "2026-03-08 02:30:00".date(timeZone: newYork)

                expect(date).to(beNil())
            }

            it("parses ISO 8601 offsets without daylight-saving ambiguity") {
                let daylightTime = "2026-11-01T01:30:00-04:00".iso8601Date
                let standardTime = "2026-11-01T01:30:00-05:00".iso8601Date
                let fractionalTime = "2026-11-01T01:30:00.123-04:00".iso8601Date

                expect(daylightTime).toNot(beNil())
                expect(standardTime).toNot(beNil())
                expect(fractionalTime).toNot(beNil())
                expect(standardTime!.timeIntervalSince(daylightTime!)) == 60 * 60
            }

            it("formats dates with explicit locale and time zone") {
                let date = "2026-07-01T16:00:00Z".iso8601Date!
                let newYork = TimeZone(identifier: "America/New_York")!

                expect(
                    date.format(
                        timeZone: newYork,
                        locale: Locale(identifier: "en_US_POSIX")
                    )
                ) == "2026-07-01 12:00:00"
            }

            it("reports file creation failures without creating a file") {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let validFile = directory.appendingPathComponent("valid.txt")
                let invalidFile = directory.appendingPathComponent("invalid.txt")
                defer { try? FileManager.default.removeItem(at: directory) }

                expect {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                }.toNot(throwError())
                expect(QuickPaths.createFile(filePath: validFile.path, contents: "content")) == true
                expect(try? String(contentsOf: validFile, encoding: .utf8)) == "content"
                expect(QuickPaths.createFile(filePath: invalidFile.path, contents: NSObject())) == false
                expect(FileManager.default.fileExists(atPath: invalidFile.path)) == false
            }
        }

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
