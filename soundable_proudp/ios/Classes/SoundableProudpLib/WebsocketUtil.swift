//
//  WebsocketUtil.swift
//
//
//  Created by Tony Kim on 11/1/24.
//

import Foundation


@available(iOS 13.0, *)
class WebsocketUtil: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate{
    static let shared = WebsocketUtil()
    private var webSocket:URLSessionWebSocketTask?
    private var isConnected:Bool = false
    private var socketTimer: DispatchSourceTimer!
    
    
    func connectSocket(user_id:String, webSocketUrl:String) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        let url = URL(string: webSocketUrl)
        
        var urlRequest = URLRequest(url: url!)
        urlRequest.setValue(user_id, forHTTPHeaderField: "user_id")
        
        webSocket = session.webSocketTask(with: urlRequest)
        webSocket?.resume()
        isConnected = true
    }
    
    func checkSocketSessionAliveAndTryReconnect(user_id:String, webSocketUrl:String){
        if let socket = webSocket{
            if(socket.state == .running){
                print("SOCKET RUNNING!!!")
                return
            }
        }
        connectSocket(user_id: user_id, webSocketUrl: webSocketUrl)
        // TODO, How long do you have to wait for the result after websocket connection?
        // If it is longer than that time, it shows a "not ok" result.
    }

    
    func close() {
        socketTimer.cancel()
        webSocket?.cancel()
    }
    
    func send() {
        webSocket?.send(.string("ping"), completionHandler: { error in
            if let error = error {
                print("send message error: \(error)")
            }
        })
    }
    
    func receive() {
        webSocket?.receive(completionHandler: { result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    print("receive data: \(data)")
                case .string(let str):
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("SoundableProudpLib"), object: nil, userInfo: ["result": str])
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                print("receive error: \(error)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("SoundableProudpLib"), object: nil, userInfo: ["result": error.localizedDescription])
                }
            }
            self.close()
        })
    }
    
    // If we do not receive a result within 1 minute, we will cancel the websocket connection.
    private func setTimer() {
        var time: Int = 0
        if self.socketTimer == nil || self.socketTimer!.isCancelled {
            self.socketTimer = DispatchSource.makeTimerSource()
            self.socketTimer?.schedule(deadline: .now(), repeating: .seconds(1))
            self.socketTimer?.setEventHandler {
                print("conn time:", time)
                time += 1
                if time % 60 == 0 && time > 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("SoundableProudpLib"), object: nil, userInfo: ["result": "Socket Connnection Error"])
                    }
                    self.close()
                }
            }
        }
    }
    
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("Websocket connected")
        isConnected = true
        receive()
        setTimer()
        socketTimer.resume()
    }
    
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("Websocket disconnected")
        self.webSocket = nil
        isConnected = false
    }
}
