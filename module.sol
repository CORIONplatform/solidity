pragma solidity ^0.4.11;

contract abstractModuleHandler {
    function balanceOf(address _owner) public constant returns (uint256 value, bool success) {}
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {}
}

contract module {
    /*
        Module handler
    */
    
    enum status {
        New,
        Connected,
        Disconnected,
        Disabled
    }
    
    status private moduleStatus;
    uint256 private disabledUntil;
    address private moduleHandlerAddress;
    
    function _connectModule() internal returns (bool) {
        /*
            Registering and/or connecting-to ModuleHandler
            
            This function is called by ModuleHandler load.
                or
            Calls the Pool module at ModuleHandler
        */
        require( msg.sender == moduleHandlerAddress && moduleStatus == status.New );
        moduleStatus = status.Connected;
        moduleHandlerAddress = msg.sender;
        return true;
    }
    function _registerModuleHandler(address addr) internal returns(bool) {
        /*
            Registering ModuleHandler address
            
            This function is automatic called while depoying the contract.
        */
        require( moduleHandlerAddress == 0x00 && moduleStatus == status.New );
        moduleHandlerAddress = addr;
        return true;
    }
    function _disconnectModule() internal returns (bool) {
        /*
            Disconnect the module from the ModuleHandler
            
            This function calls the Poll module
        */
        require( msg.sender == moduleHandlerAddress && moduleStatus == status.Connected );
        moduleStatus = status.Disconnected;
        return true;
    }
    function _replaceModule(address addr) internal returns (bool) {
        /*
            Replace the module for an another new module
            
            This function calls the Poll module
            
            We send every Token and ether to the new module
        */
        require( msg.sender == moduleHandlerAddress && moduleStatus == status.Connected );
        var (bal, s) = abstractModuleHandler(moduleHandlerAddress).balanceOf(address(this));
        require( s );
        if (bal > 0) {
            abstractModuleHandler(moduleHandlerAddress).transferFrom(address(this), addr, bal);
        }
        if ( this.balance > 0 ) { if ( ! addr.send(this.balance) ) { return false; } }
        delete moduleHandlerAddress;
        moduleStatus = status.Disconnected;
        return true;
    }
    function _isActive() internal returns (bool) {
        /*
            Ask for is active the module or not
            
            Free to call
        */
        if ( moduleStatus != status.Connected || block.number < disabledUntil ) { return false; }
        return true;
    }
    function _disableModule(bool forever) internal returns (bool) {
        /*
            Disable the module for one week, if the forever true then for forever.
            
            This function calls the Poll module
        */
        require( msg.sender == moduleHandlerAddress );
        if ( forever ) { moduleStatus = status.Disabled; }
        disabledUntil = block.number + 40320;
        return true;
    }
    function _replaceModuleHandler(address newHandler) internal returns (bool) {
        /*
            Replace the ModuleHandler address.
            
            This function calls the Poll module
        */
        require( msg.sender == moduleHandlerAddress && moduleStatus == status.Connected );
        moduleHandlerAddress = newHandler;
        return true;
    }
    function _isModuleHandler(address addr) internal returns (bool) {
        /*
            Test for ModuleHandler address
            
            Free to call
        */
        if ( moduleStatus != status.Connected ) { return false; }
        return addr == moduleHandlerAddress;
    }
    function _getModuleHandlerAddress() internal returns (address) {
        return moduleHandlerAddress;
    }
}