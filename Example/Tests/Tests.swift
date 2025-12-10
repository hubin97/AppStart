// https://github.com/Quick/Quick

import Quick
import Nimble
import AppStart

class TableOfContentsSpec: QuickSpec {
    
    override class func spec() {
        
        describe("these will fail") {

            it("can do maths") {
                expect(1) == 2
            }

            it("can read") {
                expect("number") == "string"
            }

            // 异步回调
            // toEventually 会给异步代码 缓冲时间（默认 1 秒，可配置）, 1s后再执行
            it("will eventually fail") {
                expect("time").toEventually( equal("done") )
            }
            
            // NSValue 在 Swift 中不是纯粹的 ObjC 对象，Nimble 的桥接转换不稳定。
            var testValue: NSArray!
            beforeEach {
                testValue = NSArray()
            }
            
            it("class check") {
                expect(testValue).to(beAKindOf(NSArray.self))
            }
            
            context("these will pass") {

                it("can do maths") {
                    expect(23) == 23
                }

                it("can read") {
                    expect("🐮") == "🐮"
                }

                it("will eventually pass") {
                    var time = "passing"

                    DispatchQueue.main.async {
                        time = "done"
                    }

                    waitUntil { done in
                        Thread.sleep(forTimeInterval: 0.5)
                        expect(time) == "done"

                        done()
                    }
                }
            }
        }
    }
}
