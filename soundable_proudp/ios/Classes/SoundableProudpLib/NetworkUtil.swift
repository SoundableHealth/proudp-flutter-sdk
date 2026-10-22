//
//  NetworkUtil.swift
//
//
//  Created by Tony Kim on 11/1/24.
//

import Foundation
import UIKit


class NetworkUtil: NSObject {
    static var shared = NetworkUtil()
    func uploadAudioFile(fileUrl: URL, apiKey: String, apiUrl: String, fileUploadOk:@escaping ()-> (), fileUploadFail:@escaping (_:Int)-> ()) {
        let fileName = fileUrl.lastPathComponent
        let headers: Dictionary = [
            "Content-Type": "audio/m4a",
            "fileName": fileName,
            "X-api-key": apiKey,
        ]
        
        guard let url = URL(string: apiUrl + "upload") else {
            print("[Error]cannot create post url")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.allHTTPHeaderFields = headers
        
        let task = URLSession(configuration: URLSessionConfiguration.default).uploadTask(with: urlRequest, fromFile: fileUrl) { (data, response, error) in
            if (error != nil) {
                print("[Error]upload: ", error!)
            } else {
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("upload ok : \(fileName)")
                        DispatchQueue.main.async(){
                            fileUploadOk()
                        }
                    } else {
                        print("upload fail:", httpResponse.statusCode, fileName)
                        DispatchQueue.main.async(){
                            fileUploadFail(httpResponse.statusCode)
                        }
                    }
                }
            }
        }
        task.resume()
    }
}
