import Alamofire
import PromiseKit

public protocol AccessTokenRefresherDelegate {
    
    func tokenRefreshed(_ userCredentials: PSCredentials)
    func refreshTokenIsInvalid(_ error: Error)
}

public class RefreshingWalletAsyncClient: WalletAsyncClient {
    
    var userCredentials: PSCredentials
    private let accessTokenRefresherDelegate: AccessTokenRefresherDelegate
    private let authAsyncClient: OAuthAsyncClient
    private var tokenIsRefreshing = false
    
    
    init(sessionManager: SessionManager,
         userCredentials: PSCredentials,
         authAsyncClient: OAuthAsyncClient,
         publicWalletApiClient: PublicWalletApiClient,
         serverTimeSynchronizationProtocol: ServerTimeSynchronizationProtocol,
         accessTokenRefresherDelegate: AccessTokenRefresherDelegate) {
        
        self.userCredentials = userCredentials
        self.authAsyncClient = authAsyncClient
        self.accessTokenRefresherDelegate = accessTokenRefresherDelegate
        
        super.init(sessionManager: sessionManager,
                   publicWalletApiClient: publicWalletApiClient,
                   serverTimeSynchronizationProtocol: serverTimeSynchronizationProtocol)
    }
    
    override func makeRequest(apiRequest: ApiRequest) {
        let lockQueue = DispatchQueue(label: String(describing: self), attributes: [])
        lockQueue.sync {
            guard !tokenIsRefreshing else {
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
                    if statusCode == 400 && error.isTokenExpired() {
                        self.handleExpiredAccessToken(apiRequest, error)
                        return
                    }
                    
                    apiRequest.pendingPromise.resolver.reject(error)
            }
        }
    }
    
    public func refreshToken(code: String, extensionScopes: [String]) -> Promise<PSCredentials> {
        return refreshToken(code: code, scopes: extensionScopes)
    }
    
    func handleExpiredAccessToken(_ apiRequest: ApiRequest, _ error: PSWalletApiError) {
        let lockQueue = DispatchQueue(label: String(describing: self), attributes: [])
        lockQueue.sync {
            guard !hasRecentlyRefreshed() else {
                self.makeRequest(apiRequest: apiRequest)
                return
            }
            self.requestsQueue.append(apiRequest)
            guard !tokenIsRefreshing else {
                return
            }
            self.tokenIsRefreshing = true
            refreshToken()
        }
    }
    
    private func refreshToken(code: String? = nil, scopes: [String]? = nil) -> Promise<PSCredentials> {
        let lockQueue = DispatchQueue(label: String(describing: self), attributes: [])
        return Promise<PSCredentials> { value in
            lockQueue.sync {
                guard let refreshToken = userCredentials.refreshToken else {
                    value.reject(PSWalletApiError(error: "invalid_refresh_token", description: "refresh token is not provided to user credentials"))
                    return
                }
                authAsyncClient.refreshToken(refreshToken, code: code, scopes: scopes).done { refreshedCredentials in
                        lockQueue.sync {
                            self.updateCredentials(with: refreshedCredentials)
                            self.tokenIsRefreshing = false
                            self.resumeQueue()
                            self.accessTokenRefresherDelegate.tokenRefreshed(self.userCredentials)
                            value.fulfill(refreshedCredentials)
                        }
                    }.catch { error in
                        lockQueue.sync {
                            self.tokenIsRefreshing = false
                            if let walletApiError = error as? PSWalletApiError, walletApiError.isRefreshTokenExpired() {
                                self.accessTokenRefresherDelegate.refreshTokenIsInvalid(error)
                            }
                            self.cancelQueue(error: error)
                            value.reject(error)
                        }
                }
            }
        }
    }
    
    private func hasRecentlyRefreshed() -> Bool {
        guard let validUntil = userCredentials.validUntil,
            let expiresIn = userCredentials.expiresIn else {
                return false
        }
        return abs(expiresIn - validUntil.timeIntervalSinceNow) < 15
    }
    
    private func updateCredentials(with refreshedCredentials: PSCredentials) {
        userCredentials.accessToken = refreshedCredentials.accessToken
        userCredentials.macKey = refreshedCredentials.macKey
        userCredentials.refreshToken = refreshedCredentials.refreshToken
        userCredentials.validUntil = refreshedCredentials.validUntil
    }
}
