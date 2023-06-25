//
//  PacketTunnelProvider.swift
//  NEPacketTunnelVPNDemoTunnel
//
//  Created by lxd on 12/8/16.
//  Copyright © 2016 lxd. All rights reserved.
//

import NetworkExtension
import OSLog

@available(macOSApplicationExtension 11.0, *)
class PacketTunnelProvider: NEPacketTunnelProvider {
    var session: NWUDPSession? = nil
    var conf = [String: AnyObject]()
    var pipe: String? = nil

    /*// These 2 are core methods for VPN tunnelling
    //   - read from tun device, encrypt, write to UDP fd
    //   - read from UDP fd, decrypt, write to tun device
    func tunToUDP() {
        os_log("qqq - tunToUDP")
        self.packetFlow.readPackets { (packets: [Data], protocols: [NSNumber]) in
            for packet in packets {
                // This is where encrypt() should reside
                // A comprehensive encryption is not easy and not the point for this demo
                // I just omit it
                self.session?.writeDatagram(packet, completionHandler: { (error: Error?) in
                    if let error = error {
                        print(error)
                        self.setupUDPSession()
                        return
                    }
                })
            }
            // Recursive to keep reading
            self.tunToUDP()
        }
    }

    func udpToTun() {
        os_log("qqq - udpToTun")

        // It's callback here
        session?.setReadHandler({ (_packets: [Data]?, error: Error?) -> Void in
            if let packets = _packets {
                // This is where decrypt() should reside, I just omit it like above
                self.packetFlow.writePackets(packets, withProtocols: [NSNumber](repeating: AF_INET as NSNumber, count: packets.count))
            }
        }, maxDatagrams: NSIntegerMax)
    }

   func setupPacketTunnelNetworkSettings() {
        os_log("qqq - setupPacketTunnelNetworkSettings")
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [conf["ip"] as! String], subnetMasks: [conf["subnet"] as! String])
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        tunnelNetworkSettings.mtu = Int(conf["mtu"] as! String) as NSNumber?
        let dnsSettings = NEDNSSettings(servers: (conf["dns"] as! String).components(separatedBy: ","))
        // This overrides system DNS settings
        dnsSettings.matchDomains = [""]
        tunnelNetworkSettings.dnsSettings = dnsSettings
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            self.udpToTun()
        }
    }
     
     func setupUDPSession() {
        os_log("qqq - setupUDPSession")
        if self.session != nil {
            self.reasserting = true
            self.session = nil
        }
        let serverAddress = self.conf["server"] as! String
        let serverPort = self.conf["port"] as! String
        self.reasserting = false
        self.setTunnelNetworkSettings(nil) { (error: Error?) -> Void in
            if let error = error {
                print(error)
            }
            self.session = self.createUDPSession(to: NWHostEndpoint(hostname: serverAddress, port: serverPort), from: nil)
            self.setupPacketTunnelNetworkSettings()
        }
    }
     */

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("qqq - startTunnel")
        conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as [String : AnyObject]
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4Settings = NEIPv4Settings(addresses: ["192.168.1.2"], subnetMasks: ["255.255.255.0"])
        var includedRoutes: [NEIPv4Route] = []
        includedRoutes.append(NEIPv4Route.default())
        
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        dnsSettings.matchDomains = [""]
        dnsSettings.matchDomainsNoSearch = true
        tunnelNetworkSettings.dnsSettings = dnsSettings
        tunnelNetworkSettings.ipv4Settings = ipv4Settings
        
        setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let applyError = error {
                os_log("QQQ - Failed to apply tunnel settings settings: %{public}@", applyError.localizedDescription)
            }
            os_log("QQQ - settings ok")
            completionHandler(error)
            self.handleflow()
        }
        
        //self.handleflow()

    }
    
    func handleflow(){
        os_log("qqq - intercepted")
        self.packetFlow.readPackets { (packets, protocols) in
            os_log("qqq - inside packet")
            for (i, packet) in packets.enumerated(){
                os_log("qqq protocol - %{public}@", protocols[i])
                os_log("qqq packet - %{public}@", packet.base64EncodedString())
                self.writeToPipe(content: packet)
            }
            self.handleflow()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("qqq - stoptunnel")
        session?.cancel()
        super.stopTunnel(with: reason, completionHandler: completionHandler)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        os_log("qqq - handleAppMessage")
        let messageString = String(data: messageData, encoding: .utf8)
        os_log("qqq - handleAppMessage %{public}@", messageString ?? "no messageString")
        self.pipe = messageString
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    func writeToPipe(content: Data) {
        os_log("QQQ - I'm inside writeToPipe, I'm writing on %{public}@", self.pipe ?? "no self.pipe installed")
        if let pipe = self.pipe{
            do {
                let handler = FileHandle(forWritingAtPath: pipe)
                os_log("qqq url: \(pipe, privacy: .public)")
                os_log("qqq bundle resources url: \(Bundle.main.resourcePath!, privacy: .public)")
                var packet = PipeRs_RawPacket_Packet()
                packet.title = content.base64EncodedString()
                if let serializedPacket = self.serializePacket(packet: packet){
                    try handler?.write(contentsOf: serializedPacket)
                    handler?.closeFile()
                }
           } catch{
               os_log("qqq - fail to write due to \(error, privacy: .public)")
           }
        }
    }
    
    // Serialize and deserialize UDP packets
    func serializePacket(packet: PipeRs_RawPacket_Packet) -> Data? {
        do {
            return try packet.serializedData()
        } catch {
            print("Failed to serialize UDP packet: \(error)")
            return nil
        }
    }

    func deserializePacket(data: Data) -> PipeRs_RawPacket_Packet? {
        do {
            return try PipeRs_RawPacket_Packet(serializedData: data)
        } catch {
            print("Failed to deserialize UDP packet: \(error)")
            return nil
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        os_log("qqq - sleep")
        completionHandler()
    }

    override func wake() {
        os_log("qqq - wake")
    }
}
