//
//  File.swift
//  
//
//  Created by Chris Hinkle on 11/29/20.
//

import Foundation
import CoreBluetooth
import CBGATT
import os.log
import Combine



public class GATTDevice<Services,Characteristics>:NSObject,ObservableObject,CBPeripheralDelegate where Services:ServiceDefinition,Characteristics:CharacteristicDefinition
{
    private let log:OSLog = .init( subsystem:"BoarBluetooth", category:"GATTDevice" )
    let peripheral:CBPeripheral
    
    
    typealias CharacteristicSubject = CurrentValueSubject<CharacteristicModel?,Never>
    private var characteristcsSubjects:[Characteristics:CharacteristicSubject] = [ : ]
    private func subject( for characteristic:Characteristics )->CharacteristicSubject
    {
        if !characteristcsSubjects.keys.contains( characteristic )
        {
            characteristcsSubjects[ characteristic ] = .init( nil )
        }
        return characteristcsSubjects[ characteristic ]!
    }
    
    public func publisher( for characteristic:Characteristics )->AnyPublisher<CharacteristicModel?,Never>
    {
        return subject( for:characteristic ).eraseToAnyPublisher( )
    }
    
    let readConfiguration:GATTReadConfiguration<Characteristics>
    init( peripheral:CBPeripheral, readConfiguration:GATTReadConfiguration<Characteristics> )
    {
        self.peripheral = peripheral
        self.readConfiguration = readConfiguration
        super.init( )
        peripheral.delegate = self
    }
    
    @Published public var isConnected:Bool = false
    
    
    
    func discover( )
    {
        peripheral.discoverServices( Services.allServices )
    }

    public func peripheral( _ peripheral:CBPeripheral, didDiscoverServices error:Error? )
    {
        guard let services = peripheral.services else
        {
            return
        }
        
        for service in services
        {
            guard let serviceDef = Services.init( rawValue:service.uuid.uuidString ) else
            {
                continue
            }
            peripheral.discoverCharacteristics( Array<CBUUID>( serviceDef.characteristics ), for:service )
        }
    }
    
    public func peripheral( _ peripheral:CBPeripheral, didDiscoverCharacteristicsFor service:CBService, error:Error? )
    {
        guard let characteristics = service.characteristics else
        {
            return
        }
        
        for characteristic in characteristics
        {
            guard let characteristicDef = Characteristics.init( rawValue:characteristic.uuid.uuidString ) else
            {
                continue
            }
            
            if readConfiguration.shouldNotify( characteristicDef )
            {
                peripheral.setNotifyValue( true, for:characteristic )
            }
            else if readConfiguration.shouldRead( characteristicDef )
            {
                peripheral.readValue( for:characteristic )
            }
        }
    }
    
    public func peripheral( _ peripheral:CBPeripheral, didUpdateNotificationStateFor characteristic:CBCharacteristic, error:Error? )
    {
        if let error = error
        {
            os_log( "peripheral update notification State error: %{public}@", log:log, type:.error, error.localizedDescription )
            return
        }
        
        guard let characteristicDef = Characteristics.init( rawValue:characteristic.uuid.uuidString ) else
        {
            return
        }
        
        if characteristic.isNotifying
        {
            os_log( "characteristic is notifying: %{public}@", log:log, type:.default, characteristicDef.description )
        }
        else
        {
            os_log( "characteristic is not notifying: %{public}@", log:log, type:.default, characteristicDef.description )
        }
    }
    
    public func peripheral( _ peripheral:CBPeripheral, didUpdateValueFor characteristic:CBCharacteristic, error:Error? )
    {
        if let error = error
        {
            os_log( "peripheral update notification State error: %{public}@", log:log, type:.error, error.localizedDescription )
            return
        }
        
        guard let characteristicDef = Characteristics.init( rawValue:characteristic.uuid.uuidString ) else
        {
            return
        }
        
        let valueSubject:CharacteristicSubject = subject( for:characteristicDef )
        
        if let data = characteristic.value
        {
            valueSubject.value = characteristicDef.model( with:data )
        }
        else
        {
            valueSubject.value = nil
        }
    }
}
