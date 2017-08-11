/*
    thirdPartyContract.sol
*/
pragma solidity ^0.4.15;

contract thirdPartyContract {
    function CORAddress() constant public returns (address) {}
    function CORPAddress() constant public returns (address) {}
    function receiveToken(address, uint256, bytes) external returns (bool, uint256) {}
    function approvedToken(address, uint256, bytes) external returns (bool) {}
}
