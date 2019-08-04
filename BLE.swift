//
//  BleHandle.swift
//  BLEDemo
//
//  Created by Shaw on 2019/7/11.
//  Copyright © 2019 JDHealth. All rights reserved.
//

import UIKit
import CoreBluetooth

//处理蓝牙交互的类----- 单例
@objcMembers
class BLE: NSObject {
    
    //MARK:- public
    static var shared = BLE()
    public var state:CBManagerState = .unknown
    public var timeOut = 8 //默认连接时间8s
    public var allowDuplicate = true //允许重复
    public var serviceUuidArr:[CBUUID]? = nil //指定相关服务号
    public var characterUuidArr:[CBUUID]? = nil //指定相关特征号

    @objc func register(delegate:BleDelegate){//注册代理，实现响应代理方法后会触发。不再使用后，需要移除代理
        delegates.add(delegate)
    }
    
    @objc func unregister(delegate:BleDelegate){//注销代理
        if delegates.contains(delegate) {
            delegates.remove(delegate)
        }
    }
    
    @objc func scan(){//扫描设备
        self.centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey:allowDuplicate])
        //重复搜索会提高用电量
    }
    
    @objc func stop(){//停止扫描设备
        self.centralManager.stopScan()
    }
    
    @objc func connect(peri:CBPeripheral){//连接设备
        
        self.centralManager.connect(peri, options: nil)
        
        let timer = Timer.scheduledTimer(timeInterval: TimeInterval(timeOut), target: self, selector: #selector(connectTimeOutCheck(timer:)), userInfo: peri, repeats: false)
        self.timerDict[peri.identifier.uuidString] =  timer
        timer.fireDate = Date.init(timeIntervalSinceNow: TimeInterval(timeOut))
    }
    
    @objc func disconnect(peri:CBPeripheral){//断开设备连接
        self.centralManager.cancelPeripheralConnection(peri)
    }
    
    @objc func writeData(peri:CBPeripheral,char:CBCharacteristic,data:Data) {//向xxx特征号写入xxx数据
        peri.writeValue(data, for: char, type: CBCharacteristicWriteType.withResponse)
    }
    
    @objc func readChar(peri:CBPeripheral,char:CBCharacteristic) {//读取xxx特征号的值
        peri.readValue(for: char)
    }
    
    @objc func setNotify(peri:CBPeripheral,char:CBCharacteristic,state:Bool){//打开或关闭某特征号的通知属性
        peri.setNotifyValue(state, for: char)
    }
    
    @objc func retrievePeris() -> [CBPeripheral]? {//恢复上次连接过的设备
        if restoreDict != nil && restoreDict!.values.count > 0 {
            var peris = [CBPeripheral]()
            peris.append(contentsOf: restoreDict!.values)
            return peris
        }
        return nil
    }
    
    @objc func retrieveConnectedPeris() -> [CBPeripheral]? {//回复上次已连接的设备
 
        return self.centralManager.retrieveConnectedPeripherals(withServices:(self.services() != nil  ? self.services()! : [CBUUID.init()]) )
    }
    
    
    @objc func preload(){//调动搜索，获取蓝牙状态
        self.scan()
        
        DispatchQueue.global().asyncAfter(deadline:  .now() + 0.1, execute: {
            self.stop()
        })
    }

    
    @objc public func Log(state:Bool){
        self.showLog = state
    }
 
    //MARK:- private
    private var showLog = false
    private var timerDict = NSMutableDictionary.init()
    private var restoreDict:Dictionary<String, CBPeripheral>?
    fileprivate var delegates = NSHashTable<BleDelegate>.weakObjects()
    private lazy var centralManager:CBCentralManager = {
        let c = CBCentralManager.init(delegate: self, queue: DispatchQueue(label: "com.app.ble", qos: DispatchQoS.background, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil) ,options: [CBCentralManagerOptionRestoreIdentifierKey:"com.app.Identifier"])
        c.delegate = self
        return c
    }()
    
    
    private override init() {
         super.init()
    }
    
    deinit {
        print(" deinit BLE")
    }
    
    func JLog<T>(msg: T,file: String = #file,method: String = #function,line: Int = #line){
        if showLog == true {
            print("\(method): \(msg)")
        }
    }
    
    
    @objc func connectTimeOutCheck(timer:Timer){ //连接超时处理方法
        let peri = timer.userInfo as?  CBPeripheral
        if peri != nil && peri!.isKind(of: CBPeripheral.self) && peri!.state == .connecting {
            
            for delegate in delegates.allObjects {
                if delegate.responds(to: #selector(BleDelegate.connectFailed(peri:err:))) {
                    delegate.connectFailed?(peri: peri!, err:nil)
                }
            }
            
            self.centralManager.cancelPeripheralConnection(peri!)
            self.invalidTimer(peri: peri!)
        }
    }
    
    @objc func invalidTimer(peri:CBPeripheral){
        var timer = self.timerDict.value(forKey: peri.identifier.uuidString) as? Timer
        if timer != nil  {
            timer?.invalidate()
            timer = nil
            self.timerDict.removeObject(forKey: peri.identifier.uuidString)
        }
    }
    
    
    @objc func services() -> [CBUUID]?{
        
        if self.serviceUuidArr?.isEmpty == false {
            return self.serviceUuidArr!
        } else {
            return nil
        }
    }

    @objc func characters() -> [CBUUID]?{
      
        if self.characterUuidArr?.isEmpty == false {
            return self.characterUuidArr!
        } else {
            return nil
        }
    }
}


extension BLE : CBCentralManagerDelegate {
    
   internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        JLog(msg: central.state)
        self.state = central.state
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.managerStateUpdate(state:))) {
                delegate.managerStateUpdate?(state: central.state)
            }
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        JLog(msg: peripheral)
        JLog(msg: Date.init(timeIntervalSinceNow: 0))
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.connectSuccess(peri:))) {
                delegate.connectSuccess?(peri: peripheral)
            }
        }
        peripheral.delegate = self
        peripheral.discoverServices(self.services())
        self.invalidTimer(peri: peripheral)
    }
    
   internal func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        restoreDict = dict as? Dictionary<String, CBPeripheral>
        JLog(msg: dict)
        /*
             ▿ 0 : 2 elements
             - key : "kCBRestoredPeripherals"
             ▿ value : 1 element
             - 0 : <CBPeripheral: 0x283b57200, identifier = 33C067E3-F82B-1610-4BA0-XXXXXXXX, name = XXXXXX, state = connected>
        */
    }
    
    
    internal func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        JLog(msg: peripheral)
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.connectFailed(peri:err:))) {
                delegate.connectFailed?(peri: peripheral, err: error)
            }
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        JLog(msg: peripheral)
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.disconnected(peri:err:))) {
                delegate.disconnected?(peri: peripheral, err: error)
            }
        }
    }
    
    internal func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        JLog(msg: peripheral)
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.discovered(peri:rssi:advertisementData:))) {
                delegate.discovered?(peri: peripheral, rssi: RSSI, advertisementData: advertisementData)
            }
        }
    }
}

extension BLE: CBPeripheralDelegate {
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if peripheral.services != nil  {
            for ser in peripheral.services! {
                if self.services() == nil || self.services()!.contains(ser.uuid) {
                    peripheral.discoverCharacteristics(nil, for: ser)
                }
                JLog(msg:"\(ser.uuid.uuidString)")
            }
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        JLog(msg: descriptor.value)
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        JLog(msg: peripheral)
        JLog(msg: service)
        if service.characteristics != nil {
            for char in service.characteristics! {
                
                if self.characters() == nil || self.characters()!.contains(char.uuid) {
                    peripheral.discoverDescriptors(for: char);
                    peripheral.readValue(for: char)
                }
                
                JLog(msg: char)
                
                if char.properties.contains(CBCharacteristicProperties.notify){ //设备含通知的特征号
                    peripheral.setNotifyValue(true, for: char)
                }
                
                for delegate in delegates.allObjects {
                    if delegate.responds(to: #selector(BleDelegate.discoverCharacteristic(peri:char:err:))) {
                        delegate.discoverCharacteristic?(peri: peripheral, char: char, err: error)
                    }
                }
            }
        }
        
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        JLog(msg: characteristic)
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.characteristicNotifyUpdate(peri:char:err:))) {
                delegate.characteristicNotifyUpdate?(peri: peripheral, char: characteristic,err: error)
            }
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        JLog(msg: peripheral)
        for delegate in delegates.allObjects {
            if delegate.responds(to: #selector(BleDelegate.characteristicValueUpdate(peri:char:err:))) {
                delegate.characteristicValueUpdate?(peri: peripheral, char: characteristic, err: error)
            }
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
//        JLog(msg: characteristic)
        if characteristic.descriptors != nil {
            for des in characteristic.descriptors! {
                peripheral.readValue(for: des)
            }
        }
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {}
    
}


@objc(BleDelegate) protocol BleDelegate:NSObjectProtocol {
    
    //CentralManager
    @objc optional func managerStateUpdate(state:CBManagerState)

    @objc optional func discovered(peri:CBPeripheral,rssi:NSNumber,advertisementData:Dictionary<String, Any>)
    
    @objc optional func connectSuccess(peri:CBPeripheral)

    @objc optional func connectFailed(peri:CBPeripheral,err:Error?)

    @objc optional func disconnected(peri:CBPeripheral,err:Error?)

    
    //Peripheral
    @objc optional func discoverCharacteristic(peri:CBPeripheral,char:CBCharacteristic,err:Error?)
    
    @objc optional func characteristicValueUpdate(peri:CBPeripheral,char:CBCharacteristic,err:Error?)

    @objc optional func characteristicNotifyUpdate(peri:CBPeripheral,char:CBCharacteristic,err:Error?)

}
