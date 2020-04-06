//
//  Promise.swift
//  Promise
//
//  Created by James Robinson on 12/27/19.
//

import Dispatch

#if swift(<5.0)
/* If we don't have Result, we define it here. It can be a real simple enum. */
public enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}
#endif

/// An object which symbolizes a future value or error.
public final class Promise<Value, Failure: Error> {
    
    /// A closure that is called on the main thread when the promise's value is requested for the first time.
    ///
    /// You may dispatch onto any other thread in this closure. The result you provide is always handled on the main thread.
    ///
    /// - Parameter result: The result of the promise.
    public typealias Fulfill = (_ result: Result<Value, Failure>) -> Void
    
    /// A closure that is called on the main thread if the promise resolves to success.
    /// - Parameter value: The promised value.
    public typealias Then = (_ value: Value) -> Void
    
    /// A closure that is called on the main thread if the promise resolves to failure
    /// - Parameter failure: The error provided on failure.
    public typealias Catch = (_ failure: Failure) -> Void
    
    private var isFulfilling = false
    private var fulfill: ((@escaping Fulfill) -> Void)?
    private var result: Result<Value, Failure>?
    private var thenClosures = [Then]()
    private var catchClosures = [Catch]()
    
    /// Creates a new `Promise` with the given closure.
    ///
    /// Call the provided `Fulfill` closure in your handler to generate the promised value.
    public init(_ fulfill: @escaping (@escaping Fulfill) -> Void) {
        self.fulfill = fulfill
    }
    
    /// Calls the `fulfill` closure to generate the value if it is still `nil`.
    /// Then calls `dispatch()` to send appropriate messages.
    private func beginFulfillment() {
        DispatchQueue.main.async {
            guard self.result == nil else { return self.dispatch() }
            
            guard !self.isFulfilling else { return } // already fulfilling
            self.isFulfilling = true
            
            guard let fulfill = self.fulfill else { return self.dispatch() }
            self.fulfill = nil
            
            fulfill { result in
                DispatchQueue.main.async {
                    self.result = result
                    self.isFulfilling = false
                    self.dispatch()
                }
            }
        }
    }
    
    /// Sends `then` or `catch` messages, depending upon the result.
    private func dispatch() {
        guard let result = self.result else {
            return beginFulfillment()
        }
        
        switch result {
        case .success: dispatchValue()
        case .failure: dispatchFailure()
        }
    }
    
    /// Sends `then` messages, then releases the closures.
    private func dispatchValue() {
        guard case .success(let value) = result else { return }
        
        DispatchQueue.main.async {
            let closures = self.thenClosures
            self.thenClosures.removeAll()
            self.catchClosures.removeAll()
            for then in closures {
                then(value)
            }
        }
    }
    
    /// Sends `catch` messages, then releases the closures.
    private func dispatchFailure() {
        guard case .failure(let error) = result else { return }
        
        DispatchQueue.main.async {
            let closures = self.catchClosures
            self.catchClosures.removeAll()
            self.thenClosures.removeAll()
            for `catch` in closures {
                `catch`(error)
            }
        }
    }
}

extension Promise {
    
    /// Attaches a closure to the promise, to be called on the main thread if the promise succeeds.
    /// - Note: The closure will not be called if the promise resolves to an error.
    /// - Parameter onSuccess: A closure to be called if the promise succeeds.
    @discardableResult
    public func then(onSuccess: @escaping Then) -> Self {
        thenClosures.append(onSuccess)
        dispatch()
        return self
    }
    
    /// Returns a new promise mapping the receiver's values to a different promise.
    @discardableResult
    public func then<T>(onSuccess: @escaping (Value) throws -> T) -> Promise<T, Failure> {
        Promise<T, Failure> { fulfill in
            self.then { (value) in
                do {
                    let newValue = try onSuccess(value)
                    fulfill(.success(newValue))
                } catch {
                    // swiftlint:disable:next force_cast
                    fulfill(.failure(error as! Failure))
                }
            }
        }
    }
    
    /// Returns a new promise mapping the receiver's values to a different promise.
    @discardableResult
    public func then<T>(onSuccess: @escaping (Value) -> Promise<T, Failure>) -> Promise<T, Failure> {
        Promise<T, Failure> { fulfill in
            self.then { (value) in
                onSuccess(value)
                    .then(onSuccess: { fulfill(.success($0)) })
                    .catch(onFailure: { fulfill(.failure($0)) })
            }
        }
    }
    
    /// Attaches a closure to the promise, to be called on the main thread if the promise fails.
    /// - Note: The closure will not be called if the promise resolves to success.
    /// - Parameter onFailure: A closure to be called if the promise fails.
    @discardableResult
    public func `catch`(onFailure: @escaping Catch) -> Self {
        catchClosures.append(onFailure)
        dispatch()
        return self
    }
    
    /// Returns a new promise mapping the receiver's errors to a different promise.
    @discardableResult
    public func `catch`<F>(onFailure: @escaping (Failure) -> Promise<Value, F>) -> Promise<Value, F> {
        Promise<Value, F> { fulfill in
            self.catch { (value) in
                onFailure(value)
                    .then(onSuccess: { fulfill(.success($0)) })
                    .catch(onFailure: { fulfill(.failure($0)) })
            }
        }
    }
    
    /// Blocks the current thread until the promise resolves.
    ///
    /// - Note: A not at all performant way of doing things.
    ///
    /// - Returns: The resolution of the Promise.
    public func await() -> Result<Value, Failure> {
        dispatch()
        while result == nil { /* loop */ }
        return result!
    }
    
}

extension Promise where Failure == Never {
    
    /// Creates a promise already fulfilled with the provided value.
    public convenience init(fulfilled value: Value) {
        self.init { fulfill in
            fulfill(Result<Value, Failure>.success(value))
        }
    }
    
}

extension Promise where Value == Never {
    
    /// Creates a promise already fulfilled with the given error.
    public convenience init(fulfilled error: Failure) {
        self.init { fulfill in
            fulfill(Result<Value, Failure>.failure(error))
        }
    }
    
}

// MARK: - Combine

#if canImport(Combine)
import Combine

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Promise: Publisher {
    
    public typealias Output = Value
    
    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Value == S.Input {
        let subscription = PromiseSubscription(subscriber: subscriber, promise: self)
        subscriber.receive(subscription: subscription)
    }
    
}

/// A publisher that sends a value when the `Promise` resolves.
@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class PromiseSubscription<SubscriberType, Value, Failure>: Subscription
    where SubscriberType: Subscriber,
    SubscriberType.Input == Value,
    SubscriberType.Failure == Failure {
    
    private var subscriber: SubscriberType?
    private var promise: Promise<Value, Failure>
    
    /// Creates a subscription to the given promise, attaching listeners to its value and failure callbacks.
    public init(subscriber: SubscriberType, promise: Promise<Value, Failure>) {
        self.subscriber = subscriber
        self.promise = promise
    }
    
    public func request(_ demand: Subscribers.Demand) {
        promise
            .then { [weak self] value in
                _ = self?.subscriber?.receive(value)
                self?.subscriber?.receive(completion: .finished)
                self?.subscriber = nil
            }
            .catch { [weak self] error in
                self?.subscriber?.receive(completion: .failure(error))
                self?.subscriber = nil
            }
    }
    
    public func cancel() {
        subscriber = nil
    }
    
}
#endif
