pragma solidity ^0.4.11;

contract owned {
    address private owner = msg.sender;
    
    function replaceOwner(address newOwner) external returns(bool) {
        /*
            owner replace.
            
            @newOwner address of new owner.
        */
        require( isOwner() );
        owner = newOwner;
        return true;
    }
    
    function isOwner() internal returns(bool) {
        /*
            Check of owner address.
            
            @bool owner has called the contract or not 
        */
        return owner == msg.sender;
    }
}