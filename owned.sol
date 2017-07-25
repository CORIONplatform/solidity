/*
    owned.sol
*/
pragma solidity ^0.4.11;

contract owned {
    address public owner;
    function replaceOwner(address newOwner) external returns(bool success) {
        /*
            Owner replace.
            
            @newOwner   Address of new owner.
            
            @success    Was the Function successful?
        */
        require( isOwner() );
        owner = newOwner;
        return true;
    }
    
    function isOwner() internal returns(bool) {
        /*
            Check of owner address.
            
            @bool   Owner has called the contract or not 
        */
        if ( owner == 0x00 ) {
            return true;
        }
        return owner == msg.sender;
    }
}
