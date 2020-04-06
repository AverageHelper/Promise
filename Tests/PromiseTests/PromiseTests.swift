import XCTest
import Promise

final class PromiseTests: XCTestCase {

    static var allTests: [(String, (PromiseTests) -> () -> ())] = [
        ("testThen", testThen),
        ("testCatch", testCatch)
    ]
    
    func testThen() {
        let result = 5
        let promise = Promise<Int, Never> { (fulfill) in
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(400)) {
                fulfill(.success(result))
            }
        }
        
        let fulfills = expectation(description: "Promise fulfills")
        promise.then { r in
            fulfills.fulfill()
            XCTAssertEqual(r, result)
        }
        wait(for: [fulfills], timeout: 2)
    }
    
    enum Catchable: Error {
        case thing
        case otherThing
    }
    
    func testCatch() {
        let result = Catchable.thing
        let promise = Promise<Never, Catchable> { (fulfill) in
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(400)) {
                fulfill(.failure(result))
            }
        }
        
        let fulfills = expectation(description: "Promise fulfills")
        promise.catch { e in
            fulfills.fulfill()
            XCTAssertEqual(e, result)
        }
        wait(for: [fulfills], timeout: 2)
    }
    
}
