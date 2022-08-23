# Repeat if with delay Combine publisher
I tried to implement repeat if with delay custom publisher for Swift Combine. It is not working consistently. I needed to implement repeat if with delay custom publisher for Swift Combine. The purpose of it is to repeatedly poll backend endpoint with delay set from previous response. It could be long polling (max 5min. with 3 - 6sec time period). I tried to use recursive approach, but it is not working consistelty. It makes from 20 to 200 repeats randomly, and then there is fired finished on the former/first subsciption and rest of the subscrptions are finished also. Count of repeats probably depends on memory situation etc.. Any coments or hints how to implement described functionality in reactive way are welcome.

# Different working approach with usage of (CurentValueSubject):

```
func retryRequestWithDelay(url: URL) -> AnyPublisher<Response>, AppError> {
        let pollPublisher = CurrentValueSubject<Int, AppError>(0)
        return pollPublisher.compactMap { [weak self] delay in
            return self?.networkingService.request(url)
                .delay(for: .seconds(delay), scheduler: DispatchQueue.global())
        }
        .switchToLatest()
        .receive(on: DispatchQueue.main)
        .handleEvents(receiveOutput: { [weak self] (response: Response) in
            guard let self = self else { return }
            if response.status == .pending {
                self.pollPublisher.send(response.pollPeriod)
            } else {
                self.pollPublisher.send(completion: .finished)
            }
        })
        .filter { (response: Response) in
            guard response.data.status == .pending else { return true }
            return false
        }
        .eraseToAnyPublisher()
  }
```
