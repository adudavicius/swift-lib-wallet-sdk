import Alamofire
import ObjectMapper
import PromiseKit

public class BaseAsyncClient {
    
    let sessionManager: SessionManager
    let publicWalletApiClient: PublicWalletApiClient?
    let serverTimeSynchronizationProtocol: ServerTimeSynchronizationProtocol?
    
    var requestsQueue = [ApiRequest]()
    var timeIsSyncing = false
    
    init(sessionManager: SessionManager,
         publicWalletApiClient: PublicWalletApiClient? = nil,
         serverTimeSynchronizationProtocol: ServerTimeSynchronizationProtocol? = nil) {
        
        self.sessionManager = sessionManager
        self.publicWalletApiClient = publicWalletApiClient
        self.serverTimeSynchronizationProtocol = serverTimeSynchronizationProtocol
    }
    
    public func cancelAllOperations() {
        sessionManager.session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
    
    func createRequest<T: ApiRequest, R: URLRequestConvertible>(_ endpoint: R) -> T {
        return T.init(pendingPromise: Promise<String>.pending(),
                      requestEndPoint: endpoint
        )
    }
    
    func createPromise<T: Mappable>(jsonString: String) -> Promise<T> {
        
        guard let object = Mapper<T>().map(JSONString: jsonString) else {
            return Promise(error: mapError(jsonString: jsonString, statusCode: nil))
        }
        return Promise.value(object)
    }
    
    private func createPromiseWithArrayResult<T: Mappable>(jsonString: String) -> Promise<[T]> {
        guard let objects = Mapper<T>().mapArray(JSONString: jsonString) else {
            return Promise(error: mapError(jsonString: jsonString, statusCode: nil))
        }
        return Promise.value(objects)
    }
    
    func createPromise(body: Any) -> Promise<String> {
        return Promise.value(body as! String)
    }
    
    func doRequest<RC: URLRequestConvertible, E: Mappable>(requestRouter: RC) -> Promise<[E]> {
        let request = createRequest(requestRouter)
        makeRequest(apiRequest: request)
        
        return request
            .pendingPromise
            .promise
            .then(createPromiseWithArrayResult)
    }
    
    func doRequest<RC: URLRequestConvertible, E: Mappable>(requestRouter: RC) -> Promise<E> {
        let request = createRequest(requestRouter)
        makeRequest(apiRequest: request)
        
        return request
            .pendingPromise
            .promise
            .then(createPromise)
    }
    
    func makeRequest(apiRequest: ApiRequest) {
        let lockQueue = DispatchQueue(label: String(describing: self), attributes: [])
        lockQueue.sync {
            guard !timeIsSyncing else {
                requestsQueue.append(apiRequest)
                return
            }
            sessionManager
                .request(apiRequest.requestEndPoint)
                .responseData { response in
                    
                    if let error = response.error, error.isCancelled {
                        apiRequest.pendingPromise.resolver.reject(PSWalletApiError.cancelled())
                        return
                    }
                    let responseString: String! = String(data: response.data ?? Data(), encoding: .utf8)
                    
                    guard let statusCode = response.response?.statusCode else {
                        let error = self.mapError(jsonString: responseString, statusCode: response.response?.statusCode)
                        apiRequest.pendingPromise.resolver.reject(error)
                        return
                    }
                    if statusCode >= 200 && statusCode < 300 {
                        apiRequest.pendingPromise.resolver.fulfill(responseString)
                        return
                    }
                    let error = self.mapError(jsonString: responseString, statusCode: response.response?.statusCode)
                    if statusCode == 401 && error.isInvalidTimestamp() {
                        self.syncTimestamp(apiRequest, error)
                        return
                    }
                    apiRequest.pendingPromise.resolver.reject(error)
            }
        }
        
    }
    
    func syncTimestamp(_ apiRequest: ApiRequest, _ error: PSWalletApiError) {
        let lockQueue = DispatchQueue(label: String(describing: self), attributes: [])
        lockQueue.sync {
            requestsQueue.append(apiRequest)
            guard !timeIsSyncing else {
                return
            }
            guard let publicWalletApiClient = self.publicWalletApiClient else {
                apiRequest.pendingPromise.resolver.reject(error)
                return
            }
            timeIsSyncing = true
            
            publicWalletApiClient
                .getServerInformation()
                .done { serverInformation in
                    self.serverTimeSynchronizationProtocol?.serverTimeDifferenceRefreshed(diff: serverInformation.timeDiff)
                    lockQueue.sync {
                        self.timeIsSyncing = false
                        self.resumeQueue()
                    }
                }.catch { error in
                    lockQueue.sync {
                        self.timeIsSyncing = false
                        self.cancelQueue(error: error)
                    }
            }
        }
    }
    
    func resumeQueue() {
        for request in requestsQueue {
            makeRequest(apiRequest: request)
        }
        requestsQueue.removeAll()
    }
    
    func cancelQueue(error: Error) {
        for requests in requestsQueue {
            requests.pendingPromise.resolver.reject(error)
        }
        requestsQueue.removeAll()
    }
    
    func mapError(jsonString: String, statusCode: Int?) -> PSWalletApiError {
        
        if let apiError = Mapper<PSWalletApiError>().map(JSONString: jsonString) {
            apiError.statusCode = statusCode
            return apiError
        }
        return PSWalletApiError.mapping()
    }
}
