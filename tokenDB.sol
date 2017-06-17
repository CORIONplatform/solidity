pragma solidity ^0.4.11;

import "safeMath.sol";

contract tokenDB is safeMath {
    address private owner;
    
    mapping (address => uint256) public balanceOf;
    uint256 public totalSupply;
    
    function replaceOwner(address newOwner) external returns(bool) {
        /*
            Set new owner. It can be called only by owner, if owner is not set anyone can call it. 
            
            @newOwner       New owner’s address
        */
        require( owner == 0x00 || msg.sender == owner );
        owner = newOwner;
        return true;
    }
    
    function increase(address _owner, uint256 _value) isOwner external returns(bool) {
        /*
            Increase of balance of the address in database. only owner can call it.
            
            @_owner         Address
            @_value         quantity
            @bool           Was the Function successful?
        */
        balanceOf[_owner] = safeAdd(balanceOf[_owner], _value);
        totalSupply = safeAdd(totalSupply, _value);
        return true;
    }
    
    function decrease(address _owner, uint256 _value) isOwner external returns(bool) {
        /*
            Decrease of balance of the address in database. only owner can call it.
            
            @_owner         Address
            @_value         quantity
            @bool           Was the Function successful?
        */
        balanceOf[_owner] = safeSub(balanceOf[_owner], _value);
        totalSupply = safeSub(totalSupply, _value);
        return true;
    }
    
    modifier isOwner {
        /*
            Only owner can call it.
        */
        require( msg.sender == owner ); _; 
    }
    
}