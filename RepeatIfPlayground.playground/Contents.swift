import UIKit
import Combine
import PlaygroundSupport

enum TestFailureCondition: Error {
    case invalidServerResponse
}

struct TestResponse {
    let uuid = UUID()
    let poll: Int = Int.random(in: 1..<3)
}

var backgroundQueue: DispatchQueue = DispatchQueue(label: "backgroundQueue")

var testPublisher: AnyPublisher<TestResponse, Error> {
    Deferred {
        Future<TestResponse, Error> { promise in
            print("TestPublihser: Attempt to call test networking ")
            backgroundQueue.asyncAfter(deadline: .now() + Double.random(in: 1..<3)) {
                //promise(.failure(TestFailureCondition.invalidServerResponse))
                promise(.success(TestResponse()))
            }
        }
    }
    .eraseToAnyPublisher()
}

extension Publisher {
    func repeatIf(
        _ shouldRepeat: @escaping (Output) -> Bool,
        withDelay: @escaping (Output) -> Int) -> CustomPublishers.RepeatIf<Self> {
        return .init(upstream: self, shouldRepeat: shouldRepeat, withDelay: withDelay)
    }
}

extension Subscribers {
    final public class Forever<Upstream: Publisher>: Subscriber, Cancellable, CustomStringConvertible {
        public typealias Input = Upstream.Output
        public typealias Failure = Upstream.Failure
        
        private var subscription: Subscription? = nil
        private let receiveCompletion: (Subscribers.Completion<Failure>) -> Void
        private let receiveValue: (Input) -> Void
        
        public var hasSubscription: Bool { subscription != nil }
        public var description: String {
            "Subscribers.Forever(\(combineIdentifier), \(hasSubscription ? "has subscription" : "not yet subscribed"))"
        }
        
        public init(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                    receiveValue: @escaping (Input) -> Void) {
            self.receiveCompletion = receiveCompletion
            self.receiveValue = receiveValue
        }

        public func receive(_ input: Input) -> Subscribers.Demand {
            print("Subscribers.Forever: receive input")
            receiveValue(input)
            return .unlimited
        }
        
        public func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            print("Subscribers.Forever: receive completion")
            receiveCompletion(completion)
        }
        
        public func receive(subscription: Subscription) {
            guard self.subscription == nil else { return subscription.cancel() }
            print("Subscribers.Forever: receive subscription")
            self.subscription = subscription
            subscription.request(.unlimited)
        }
        
        public func cancel() {
            print("Subscribers.Forever: cancel subscription")
            subscription?.cancel()
            self.subscription = nil
        }
    }
}

extension Publisher {
    func foreverSink(
        receiveCompletion: @escaping (Subscribers.Completion<Self.Failure>) -> Void,
        receiveValue: @escaping (Self.Output) -> Void) -> AnyCancellable {
            let sink = Subscribers.Forever<AnyPublisher<Self.Output, Self.Failure>>(
                receiveCompletion: receiveCompletion,
                receiveValue: receiveValue
            )
            self.subscribe(sink)
            return AnyCancellable(sink)
        }
}

enum CustomPublishers { }

extension CustomPublishers {
    struct RepeatIf<Upstream: Publisher>: Publisher {
        typealias Output = Upstream.Output
        typealias Failure = Upstream.Failure

        init(
            upstream: Upstream, shouldRepeat: @escaping (Upstream.Output) -> Bool,
            withDelay: @escaping (Upstream.Output) -> Int
        ) {
            self.upstream = upstream
            self.shouldRepeat = shouldRepeat
            self.withDelay = withDelay
        }

        var upstream: Upstream
        var shouldRepeat: (Upstream.Output) -> Bool
        var withDelay: (Upstream.Output) -> Int

        func receive<Downstream: Subscriber>(subscriber: Downstream) where Failure == Downstream.Failure, Output == Downstream.Input {
            upstream
                .print("CustomPublishers.RepeatIf(1)>")
                .flatMap { output in
                    Just((output)).setFailureType(to: Downstream.Failure.self)
                        .delay(for: .seconds(withDelay(output)),
                               scheduler: DispatchQueue.global())
                }
                .flatMap { output in
                    shouldRepeat(output)
                    ? Self(upstream: upstream, shouldRepeat: shouldRepeat, withDelay: self.withDelay)
                        .eraseToAnyPublisher()
                    : Just((output)).setFailureType(to: Downstream.Failure.self)
                        .eraseToAnyPublisher()
                }
                .catch { (error: Upstream.Failure) -> AnyPublisher<Output, Failure> in
                    return Fail(error: error).eraseToAnyPublisher()
                }
                .print("CustomPublishers.RepeatIf(2)>")
                .receive(subscriber: subscriber)
        }
    }
}


let cancellable = testPublisher
.print("(1)>")
.repeatIf({ response in
    true
}, withDelay: { response in
    return response.poll
})
.print("(2)>")
.foreverSink(receiveCompletion: { completion in
    print("Publisher.foreverSink: received the completion:", String(describing: completion))
    PlaygroundPage.current.finishExecution()
}, receiveValue: { response in
    print("Publisher.foreverSink: received \(response.poll)")
})

PlaygroundPage.current.needsIndefiniteExecution = true
