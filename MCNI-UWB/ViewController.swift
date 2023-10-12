//
//  ViewController.swift
//  MCNI-UWB
//
//  Created by 中村海斗 on 2023/10/12.
//

import UIKit
import MultipeerConnectivity
import NearbyInteraction

class ViewController: UIViewController {
    // MARK: NI variables
    var niSessions:[MCPeerID:NISession]=[:]
    var myTokenData:Data?
    
    //MARK: MC variables
    var mcSession:MCSession?
    var mcAdvertiser: MCNearbyServiceAdvertiser?
    var mcBrowserViewController: MCBrowserViewController?
    var mcBrowser: MCNearbyServiceBrowser!
    let mcServiceType = "kaito-uwb"
    let centralDevice = "iPhone12"
    let periferalDevice = "iPhone11"
    lazy var mcPeerID: MCPeerID = {
        return MCPeerID(displayName: centralDevice)
    }()
    struct PeerState {
        var isConnected: Bool
        var lastReceivedData: Data?
        var latency: TimeInterval?
        // その他必要なプロパティ
    }
    var connectedPeers: [MCPeerID: PeerState] = [:]
    
    //MARK :CSV instances
    var file:File!
    
    // MARK: IBOutlet instances

    @IBOutlet weak var connectedDeviceNameLabel: UILabel!
    
    @IBOutlet weak var mcStatusLabel: UILabel!
    

    // MARK: Main
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        print("viewDidAppear called")
        setupMultipeerConnectivity()
        
        file = File.shared
    }

    func setupNearbyInteraction(for peerID:MCPeerID) {
        //MCSessionの再接続時に邪魔しそう
        if niSessions[peerID] != nil {
            //return
            niSessions[peerID] = nil
         }
        
        // Set the NISession.
        let newSession = NISession()
        newSession.delegate = self
        // 辞書に保存
        niSessions[peerID] = newSession
        // Create a token and change Data type.
        guard let token = newSession.discoveryToken else {
            return
        }
        myTokenData = try! NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
    
    func setupMultipeerConnectivity() {
        // Set the MCSession for the advertiser.
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: mcPeerID, discoveryInfo: nil, serviceType: mcServiceType)
        mcAdvertiser?.delegate = self
        mcAdvertiser?.startAdvertisingPeer()
        
        // Set the MCSession for the browser.
        mcSession = MCSession(peer: mcPeerID)
        mcSession?.delegate = self
        
        // Initializing and starting the browser
        mcBrowser = MCNearbyServiceBrowser(peer: mcPeerID, serviceType: mcServiceType)
        mcBrowser.delegate = self
        mcBrowser.startBrowsingForPeers()
    }
    
}
// MARK: - NISessionDelegate
//NI計測プロセス
extension ViewController: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        print("NISession updated with nearby objects: \(nearbyObjects)")
        for accessory in nearbyObjects {
                var stringData = ""
            guard let peerID = niSessions.first(where: { $1 == session })?.key else {
                return
            }
                // デバイス名を追加（例として、ここではmcPeerIDを使用）
                stringData += "\(peerID.displayName),"

                // 距離データ
                if let distance = accessory.distance {
                    stringData += distance.description
                } else {
                    stringData += "-"
                }
                stringData += ","
                
                // 方向データ
                if let direction = accessory.direction {
                    stringData += "\(direction.x),\(direction.y),\(direction.z)"
                } else {
                    stringData += "-,-,-"
                }
                
                stringData += "\n"
                
                // CSVファイルにデータを書き込む
                file.addDataToFile(rowString: stringData)
            }
        }
}
// MARK: - MCNearbyServiceAdvertiserDelegate
//待機状態プロセス
extension ViewController: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer: \(peerID)")
        invitationHandler(true, mcSession)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
    }
}

// MARK: - MCSessionDelegate
//MC接続プロセス　-切断後再接続プロセス- -NI接続の実行- を含む
extension ViewController: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("MCSession state changed to: \(state) for peer: \(peerID)")
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.mcStatusLabel.text = "Connected"
            case .connecting:
                self?.mcStatusLabel.text = "Connecting"
            case .notConnected:
                self?.mcStatusLabel.text = "Not Connected"
            @unknown default:
                self?.mcStatusLabel.text = "Unknown State"
            }
        }
        switch state {
        case .connected:
            setupNearbyInteraction(for: peerID)
            connectedPeers[peerID] = PeerState(isConnected: true, lastReceivedData: nil, latency: nil)
            
            do {
                try session.send(myTokenData!, toPeers: session.connectedPeers, with: .reliable)

            } catch {
                print(error.localizedDescription)
            }
            
            DispatchQueue.main.async {
                self.mcBrowserViewController?.dismiss(animated: true, completion: nil)
                self.connectedDeviceNameLabel.text = peerID.displayName
//                self.mcStatusLabel.text = "\(state)"
                

            }
        case .notConnected:
            // The peer has disconnected or connection failed to establish.
            // Trying to reconnect automatically without user intervention
            DispatchQueue.global(qos: .background).async {
                self.attemptReconnectTo(peerID: peerID)
            }
//            DispatchQueue.main.async {
//                self.mcStatusLabel.text = "\(state)"
//            }
        default:
            print("MCSession state is \(state)")
        }
    }
    // MARK: LoopMCSession
    func attemptReconnectTo(peerID: MCPeerID) {

        mcAdvertiser?.startAdvertisingPeer()
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in

            
            do {
                let someData = "Test message for reconnection".data(using: .utf8)!
                try self.mcSession?.send(someData, toPeers: [peerID], with: .reliable)
                // If the send is successful, stop the timer.
                timer.invalidate()
            } catch {
                print("Failed to send data for reconnection: \(error)")

            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("Received data from peer: \(peerID)")
        guard let peerDiscoverToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            print("Failed to decode data.")
            return }
        
        guard let niSessionForPeer = niSessions[peerID] else {
            print("No NISession found for this peer.")
            return
        }
        
        let config = NINearbyPeerConfiguration(peerToken: peerDiscoverToken)
        niSessionForPeer.run(config)
        
        file.createFile(connectedDeviceName: peerID.displayName)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
    }
}


//MARK: - MCNearbyServiceBrowserDelegate
//MC接続自動化プロセス
extension ViewController: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Check the displayName of peer if you want to connect with specific peer
        if peerID.displayName == periferalDevice {
            if let mcSessionUnwrapped = mcSession {
                browser.invitePeer(peerID, to: mcSessionUnwrapped, withContext: nil, timeout: 10)
            } else {
                print("mcSessionはnilです")
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Handle lost peer
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        // Handle error
    }
}
