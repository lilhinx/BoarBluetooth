//
//  DeviceDiscoveryManager.swift
//  Ergometrics
//
//  Created by Chris Hinkle on 10/3/20.
//

import Combine
import CoreBluetooth
import os.log
import CBGATT

extension CBManagerState:CustomStringConvertible
{
    public var description:String
    {
        switch self
        {
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        case .resetting:
            return "resetting"
        case .unauthorized:
            return "unauthorized"
        case .unknown:
            return "unknown"
        case .unsupported:
            return "unsupported"
        @unknown default:
            return "unknown"
        }
    }
}




open class GATTDeviceManager<Services,Characteristics>:NSObject,ObservableObject,CBCentralManagerDelegate where Services:ServiceDefinition,Characteristics:CharacteristicDefinition
{
    private let log:OSLog = .init( subsystem:"BoarBluetooth", category:"GATTDeviceManager" )
    private let queue:DispatchQueue = .init( label:"boar.bluetooth.gatt-device-manager" )
    
    private lazy var central:CBCentralManager =
    {
        return CBCentralManager.init( delegate:self, queue:queue, options:[ : ] )
    }( )
    
    
    let readConfiguration:GATTReadConfiguration<Characteristics>
    public init( readConfiguration:GATTReadConfiguration<Characteristics> )
    {
        self.readConfiguration = readConfiguration
    }
    
    @Published public var isReady:Bool = false
    @Published public var isScanning:Bool = false
    @Published public var discoveredPeripherals:[CBPeripheral] = [ ]
    @Published public var selectedDevice:GATTDevice<Services,Characteristics>?
    {
        didSet
        {
            lastKnownPeripheralIdentifier = selectedDevice?.peripheral.identifier
        }
    }
    
    public var deviceSelected:Bool
    {
        return selectedDevice != nil
    }
    
    var lastKnownPeripheralIdentifier:UUID?
    {
        get
        {
            guard let uuidString = UserDefaults.standard.string( forKey:"BoarBluetooth.LastKnown" ) else
            {
                return nil
            }
            return UUID.init( uuidString:uuidString )
        }
        set
        {
            UserDefaults.standard.setValue( newValue?.uuidString, forKey:"BoarBluetooth.LastKnown" )
        }
    }
    
    var lastKnownPeripheral:CBPeripheral?
    {
        guard let lastKnownPeripheralIdentifier = lastKnownPeripheralIdentifier else
        {
            return nil
        }
        
        return central.retrievePeripherals(withIdentifiers:[ lastKnownPeripheralIdentifier ] ).first
    }
    
    public func powerOn( )
    {
        _ = central
    }
    
    func reconnect( )
    {
        if let peripheral = lastKnownPeripheral
        {
            connect( peripheral:peripheral )
            return
        }
        
        if let lastKnownPeripheralIdentifier = lastKnownPeripheralIdentifier
        {
            for peripheral in central.retrieveConnectedPeripherals( withServices:Services.allServices )
            {
                if peripheral.identifier == lastKnownPeripheralIdentifier
                {
                    connect( peripheral:peripheral )
                    return
                }
            }
        }
    }
    
    public func startScan( )
    {
        guard central.state == .poweredOn else
        {
            return
        }
        central.scanForPeripherals( withServices:Services.allServices, options:[ : ] )
        DispatchQueue.main.async
        {
            self.isScanning = self.central.isScanning
        }
    }
    
    public func stopScan( )
    {
        central.stopScan( )
        DispatchQueue.main.async
        {
            self.isScanning = self.central.isScanning
        }
    }
    
    public func connect( peripheral:CBPeripheral )
    {
        central.stopScan( )
        central.connect( peripheral, options:[ : ] )
        DispatchQueue.main.async
        {
            self.selectedDevice = .init( peripheral:peripheral, readConfiguration:self.readConfiguration )
        }
    }
    
    public func centralManagerDidUpdateState( _ central:CBCentralManager )
    {
        DispatchQueue.main.async
        {
            self.isScanning = central.isScanning
            switch central.state
            {
            case .poweredOn:
                self.isReady = true
                self.reconnect( )
            default:
                self.isReady = false
            }
        }
    }
    
    public func centralManager( _ central:CBCentralManager, didDiscover peripheral:CBPeripheral, advertisementData:[String:Any], rssi RSSI:NSNumber )
    {
        DispatchQueue.main.async
        {
            self.discoveredPeripherals.append( peripheral )
        }
    }
    
    public func centralManager( _ central:CBCentralManager, didConnect peripheral:CBPeripheral )
    {
        os_log( "connected %{public}@", log:log, type:.default, peripheral.title )
        guard let selectedDevice = selectedDevice else
        {
            return
        }
        
        guard selectedDevice.peripheral.identifier == peripheral.identifier else
        {
            return
        }
        
        selectedDevice.discover( )
        DispatchQueue.main.async
        {
            selectedDevice.isConnected = true
        }
    }
    
    public func centralManager( _ central:CBCentralManager, didDisconnectPeripheral peripheral:CBPeripheral, error:Error? )
    {
        os_log( "disconnected %{public}@", log:log, type:.default, peripheral.title )
        guard let selectedDevice = selectedDevice else
        {
            return
        }
        
        guard selectedDevice.peripheral.identifier == peripheral.identifier else
        {
            return
        }
        
        DispatchQueue.main.async
        {
            selectedDevice.isConnected = false
        }
    }
}

extension CBPeripheral
{
    public var title:String
    {
        guard let name = name else
        {
            return "Peripheral"
        }
        return name
    }
}

