//
//  GATTReadConfiguration.swift
//  
//
//  Created by Chris Hinkle on 11/29/20.
//

import CBGATT

open class GATTReadConfiguration<Characteristics> where Characteristics:CharacteristicDefinition
{
    public init( )
    {
        
    }
    
    open func shouldRead( _ characteristic:Characteristics )->Bool
    {
        fatalError( )
    }
    
    open func shouldNotify( _ characteristic:Characteristics )->Bool
    {
        fatalError( )
    }
}
