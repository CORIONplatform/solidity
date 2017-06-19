pragma solidity ^0.4.11;

import "safeMath.sol";
import "owned.sol";

contract tokenDB is safeMath, ownedDB {

    struct _allowance {
        uint256 amount;
        uint256 nonce;
    }
    
    mapping(address => mapping(address => _allowance)) private allowance;
    mapping (address => uint256) public balanceOf;
    uint256 public totalSupply;
    
    function increase(address _owner, uint256 _value) external returns(bool) {
        /*
            Increase of balance of the address in database. Only owner can call it.
            
            @_owner         Address
            @_value         quantity
            @bool           Was the Function successful?
        */
        require( isOwner() );
        balanceOf[_owner] = safeAdd(balanceOf[_owner], _value);
        totalSupply = safeAdd(totalSupply, _value);
        return true;
    }
    
    function decrease(address _owner, uint256 _value) external returns(bool) {
        /*
            Decrease of balance of the address in database. Only owner can call it.
            
            @_owner         Address
            @_value         quantity
            @bool           Was the Function successful?
        */
        require( isOwner() );
        balanceOf[_owner] = safeSub(balanceOf[_owner], _value);
        totalSupply = safeSub(totalSupply, _value);
        return true;
    }
    
    function setAllowance(address _owner, address _spender, uint256 _amount, uint256 _nonce) external returns(bool) {
        /*
            Set allowance in the database. Only owner can call it.
        */
        require( isOwner() );
        allowance[_owner][_spender].amount = _amount;
        allowance[_owner][_spender].nonce = _nonce;
        return true;
    }
    
    function getAllowance(address _owner, address _spender) constant returns(bool, uint256, uint256) {
        return ( true, allowance[_owner][_spender].amount, allowance[_owner][_spender].nonce );
    }
}
