/*
    dummyExchange.sol
*/
pragma solidity ^0.4.15;

import "./owned.sol";
import "./safeMath.sol";
import "./token.sol";

contract exchange is owned, safeMath {
    /* Variables */
    uint256 public exchangeRate;
    uint256 public exchangeRateM = 1e3;
    uint256 public maxReceiveEther = 2e17; // 0.2 ETC
    address public exchangeRateManager;
    address public foundation = 0xbed261d8da9f13dfd10bf568ea22d353c15737da;
    address public CORAddress;
    /* Constructor */
    function exchange(address _CORAddress, address _exchangeRateManager, uint256 _exchangeRate) payable {
        require( _CORAddress != 0x00 && _exchangeRateManager != 0x00 && _exchangeRate > 0);
        CORAddress = _CORAddress;
        exchangeRateManager = _exchangeRateManager;
        exchangeRate = _exchangeRate;
        owner = msg.sender;
    }
    /* Fallback */
    function () payable {}
    /* Externals */
    function receiveToken(address sender, uint256 amount, bytes data) external returns (bool success, uint256 sendBack) {
        require( msg.sender == CORAddress );
        require( amount > 1000000 );
        require( sender.balance < maxReceiveEther );
        var _max = calcETCtoCOR(maxReceiveEther);
        uint256 _amount = amount;
        if ( _max > _amount ) {
            _amount = _max;
        }
        var _reward = calcCORtoETC(_amount);
        // sending ether
        require( sender.call.value(_reward)() );
        return ( true, safeSub(amount, _amount) );
    }
    function getEther() external {
        require( isOwner() );
        require( foundation.send(this.balance) );
    }  
    function getCOR() external {
        require( isOwner() );
        require( token(CORAddress).transfer(foundation, token(CORAddress).balanceOf(address(this)) ) );
    }
    function setCORAddress(address newCORAddress) external {
        require( isOwner() );
        CORAddress = newCORAddress;
    }
    function setExchangeRate(uint256 newExchangeRate) external {
        require( msg.sender == exchangeRateManager );
        exchangeRate = newExchangeRate;
    }
    /* Constants */
    function calcCORtoETC(uint256 cor) public constant returns(uint256 etc) {
        return safeMul(safeMul(cor, 1e12), exchangeRateM) / exchangeRate ; 
    }
    function calcETCtoCOR(uint256 etc) public constant returns(uint256 cor) {
        return safeMul(exchangeRate, etc) / 1e12 / exchangeRateM;
    }
}
