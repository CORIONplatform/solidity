/*
    thirdPartyContract.sol
*/
pragma solidity ^0.4.11;

contract TPCCOR {
    function CORAddress() constant public returns (address) {}
    function receiveCOR(address, uint256, bytes) external returns (bool, uint256) {}
    function approvedCOR(address, uint256, bytes) external returns (bool) {}
}

contract TPCCORP {
    function CORPAddress() constant public returns (address) {}
    function receiveCORP(address, uint256, bytes) external returns (bool, uint256) {}
    function approvedCORP(address, uint256, bytes) external returns (bool) {}
}
