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

extension CBPeripheralState:CustomStringConvertible
{
    public var description:String
    {
        switch self
        {
        case .connected:
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnected:
            return "disconnected"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }
}


public class GATTPeripheral:Hashable,ObservableObject
{
    public static func == ( lhs:GATTPeripheral, rhs:GATTPeripheral )->Bool
    {
        return lhs.identifier == rhs.identifier
    }
    
    public func hash( into hasher: inout Hasher )
    {
        hasher.combine( identifier )
    }
    
    public let peripheral:CBPeripheral
    init( peripheral:CBPeripheral )
    {
        self.peripheral = peripheral
        self.name = peripheral.title
        self.isConnected = peripheral.state == .connected
    }
    
    public var identifier:UUID
    {
        return peripheral.identifier
    }
    
    @Published public var name:String
    @Published public var isConnected:Bool
    
    func update( )
    {
        DispatchQueue.main.async
        {
            self.name = self.peripheral.title
            self.isConnected = self.peripheral.state == .connected
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
    
    var discoveredPeripherals:Set<GATTPeripheral> = [ ]
    {
        didSet
        {
            peripherals = Array( discoveredPeripherals )
        }
    }
    
    @Published public var peripherals:[GATTPeripheral] = [ ]
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
        
        return central.retrievePeripherals( withIdentifiers:[ lastKnownPeripheralIdentifier ] ).first
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
            self.discoveredPeripherals.insert( .init( peripheral:peripheral ) )
        }
    }
    
    func updatePeripherals( )
    {
        for peripheral in discoveredPeripherals
        {
            peripheral.update( )
        }
    }
    
    public func centralManager( _ central:CBCentralManager, didConnect peripheral:CBPeripheral )
    {
        os_log( "connected %{public}@", log:log, type:.default, peripheral.title )
        
        DispatchQueue.main.async
        {
            self.discoveredPeripherals.insert( .init( peripheral:peripheral ) )
        }
        
        updatePeripherals( )
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
            selectedDevice.isConnectedSubject.value = true
        }
    }
    
    
    
    public func centralManager( _ central:CBCentralManager, didDisconnectPeripheral peripheral:CBPeripheral, error:Error? )
    {
        os_log( "disconnected %{public}@", log:log, type:.default, peripheral.title )
        print( peripheral.state.description )
        updatePeripherals( )
        
        
        
        
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
            selectedDevice.isConnectedSubject.value = false
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

