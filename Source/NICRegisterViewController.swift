import UIKit
import WebKit
import Foundation

extension URL {
    func asyncDownload(completion: @escaping (_ data: Data?, _ response: URLResponse?, _ error: Error?) -> ()) {
        URLSession.shared.dataTask(with: self) {
            completion($0, $1, $2)
        }.resume()
    }
}

@objc class SSORegisterViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler  {

    typealias Environment =  OEXAnalyticsProvider & OEXConfigProvider & OEXSessionProvider & OEXStylesProvider & OEXRouterProvider & ReachabilityProvider & DataManagerProvider & NetworkManagerProvider & OEXInterfaceProvider
    fileprivate let environment: Environment
    let config = OEXRouter.shared().environment.config

    init(environment: Environment) {
        self.environment = environment
        super.init(nibName: nil, bundle :nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var webView: WKWebView!
    let userContentController = WKUserContentController()

    func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }

    override func loadView() {
        super.loadView()

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        self.webView = WKWebView(frame: self.view.bounds, configuration: config)
        self.webView.navigationDelegate = self
        userContentController.add(self, name: "sendTokenToApplication")

        self.view = self.webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let apiHostURL = config.apiHostURL()!.absoluteString
        let oauthClientID = config.oauthClientID()!
        let oauthClientSecret = config.oauthClientSecret()!
        let stringUrl = URL(string: "\(apiHostURL)/oauth2/authorize/?scope=openid+profile+email+permissions&state=xyz&redirect_uri=\(apiHostURL)/api/mobile/v0.5/?app=ios&response_type=code&client_id=\(oauthClientID)")!
        webView.load(URLRequest(url: stringUrl))
        webView.allowsBackForwardNavigationGestures = true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else { return completionHandler(.useCredential, nil) }
        let exceptions = SecTrustCopyExceptions(serverTrust)
        SecTrustSetExceptions(serverTrust, exceptions)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func getAsyncRequest(oauthCode: String, completion:  @escaping ([String: Any]) -> ()) {

        let apiHostURL = config.apiHostURL()!.absoluteString
        let oauthClientID = config.oauthClientID()!
        let oauthClientSecret = config.oauthClientSecret()!
        let oauthTokenPath =  "/oauth2/access_token"
        let url = URL(string: apiHostURL + oauthTokenPath)!
        var request = URLRequest(url: url)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        let postString = "client_id=\(oauthClientID)&client_secret=\(oauthClientSecret)&grant_type=authorization_code&code=\(oauthCode)"
        request.httpBody = postString.data(using: .utf8)

        let task: URLSessionDataTask = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  error == nil else {
                return
            }
            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                return
            }
            completion(dict)
        }
        task.resume()

    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
        let urlRequestResult = "\(navigationAction.request)"
        if urlRequestResult.range(of: "code=") != nil {
            let oauthCode = "\(navigationAction.request)".components(separatedBy: "code=")[1]
            getAsyncRequest(oauthCode: oauthCode) { responseData in
                var token = OEXAccessToken(tokenDetails: responseData)
                OEXAuthentication.handleSuccessfulLogin(with: token, completionHandler: {responseData, response, error in })
            }
            self.present(ForwardingNavigationController(rootViewController: EnrolledTabBarViewController(environment:self.environment)), animated: true, completion: nil)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let headers = (navigationResponse.response as! HTTPURLResponse).allHeaderFields
        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Inject controller into webview
    }

}

