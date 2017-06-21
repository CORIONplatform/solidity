pragma solidity ^0.4.11;

import "module.sol";
import "announcementTypes.sol";
import "owned.sol";

import "publisher.sol";
import "token.sol";
import "provider.sol";
import "schelling.sol";
import "premium.sol";
import "ico.sol";

contract abstractModule {
    function connectModule() external returns (bool) {}
    function disconnectModule() external returns (bool) {}
    function replaceModule(address addr) external returns (bool) {}
    function disableModule(bool forever) external returns (bool) {}
    function isActive() public constant returns (bool) {}
    function replaceModuleHandler(address newHandler) external returns (bool) {}
    function transferEvent(address from, address to, uint256 value) external returns (bool) {}
    function newSchellingRoundEvent(uint256 roundID, uint256 reward) external returns (bool) {}
}

contract moduleHandler is owned, announcementTypes {
    
    struct _modules {
        address addr;
        bytes32 name;
        bool schellingEvent;
        bool transferEvent;
    }
    
    _modules[] public modules;
    address public foundationAddress;
    
    function load(address foundation, bool forReplace, address Token, address Premium, address Publisher, address Schelling, address Provider) {
        /*
            Loading modulest to ModuleHandler.
            
            This module can be called only once and only by the owner, if every single module and its database are already put on the blockchain.
            If forReaplace is true, than the ModuleHandler will be replaced. Before the publishing of its replace, the new contract must be already on the blockchain.
            
            @foundation     Address of foundation.
            @forReplace     Is it for replace or not. If not, it will be connected to the module.
            @Token          address of token.
            @Publisher      address of publisher.
            @Schelling      address of Schelling.
            @Provider       address of provider
        */
        require( super.isOwner() );
        require( modules.length == 0 );
        foundationAddress = foundation;
        addModule( _modules(Token,      sha3('Token'),      false, false),  ! forReplace);
        addModule( _modules(Premium,    sha3('Premium'),    false, false),  ! forReplace);
        addModule( _modules(Publisher,  sha3('Publisher'),  false, true),   ! forReplace);
        addModule( _modules(Schelling,  sha3('Schelling'),  false, true),   ! forReplace);
        addModule( _modules(Provider,   sha3('Provider'),   true, true),    ! forReplace);
    }
    function addModule(_modules input, bool call) internal {
        /*
            Inside function for registration of the modules in the database.
            If the call is false, wont happen any direct call.
            
            @input  _Structure of module.
            @call   Is connect to the module or not.
        */
        if ( call ) { require( abstractModule(input.addr).connectModule() ); }
        var (id, found) = searchModuleByAddress(input.addr);
        if ( ! found ) {
            id = modules.length;
            modules.length++;
        }
        modules[id] = input;
    }
    function getModuleAddressByName(string name) external returns ( address addr, bool found, bool success) {
        /*
            Search by name for module. The result is an Ethereum address.
            
            @name       Name of module.
            @addr       address of module.
            @found      Is there any result.
            @success    Was the transaction succesfull or not.
        */
        var (a, b) = getModuleIDByName(name);
        if ( b ) { return (modules[a].addr, true, true); }
        return (0x00, false, true);
    }
    function getModuleIDByName(string name) internal returns( uint id, bool found ) {
        /*
            Search by name for module. The result is an index array.
            
            @name       name of module.
            @id         index of module.
            @found      Was there any result or not.
        */
        bytes32 _name = sha3(name);
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            if ( modules[a].name == _name ) {
                return (a, true);
            }
        }
    }
    function searchModuleByAddress(address addr) internal returns( uint id, bool found ) {
        /*
            Search by ethereum address for module. The result is an index array.
            
            @name       name of module.
            @id         index of module.
            @found      Was there any result or not.
        */
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            if ( modules[a].addr == addr ) {
                return (a, true);
            }
        }
    }
    function replaceModule(string name, address addr) external returns (bool) {
        /*
            Module replace, can be called only by the Publisher contract.
            
            @name       name of module.
            @addr       address of module.
            @bool       Was there any result or not.
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName(name);
        require( found );
        require( abstractModule(modules[id].addr).replaceModule(addr) );
        require( abstractModule(addr).connectModule() );
        modules[id].addr = addr;
        return true;
    }
    function newModule(string name, address addr, bool schellingEvent, bool transferEvent) external returns (bool) {
        /*
            Adding new module to the database. Can be called only by the Publisher contract.
            
            @name               name of module.
            @addr               address of module.
            @schellingEvent     Gets it new Schelling round notification?
            @transferEvent      Gets it new transaction notification?
            @bool               Was there any result or not.
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName(name);
        require( ! found );
        addModule( _modules(addr, sha3(name), schellingEvent, transferEvent), true);
        return true;
    }
    function dropModule(string name) external returns (bool) {
        /*
            Deleting module from the database. Can be called only by the Publisher contract.
            
            @name   Name of module to delete.
            @bool   Was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName(name);
        require( found );
        abstractModule(modules[id].addr).disableModule(true);
        delete modules[id];
        return true;
    }
    function broadcastTransfer(address from, address to, uint256 value) external returns (bool) {
        /*
            Announcing transactions for the modules.
            
            Can be called only by the token module.
            Only the configured modules get notifications.( transferEvent )
            
            @from       from who.
            @to         to who.
            @value      amount.
            @bool       Was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Token') );
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            if ( modules[a].transferEvent && abstractModule(modules[a].addr).isActive() ) {
                require( abstractModule(modules[a].addr).transferEvent(from, to, value) );
            }
        }
        return true;
    }
    function broadcastSchellingRound(uint256 roundID, uint256 reward) external returns (bool) {
        /*
            Announcing new Schelling round for the modules.
            Can be called only by the Schelling module.
            Only the configured modules get notifications( schellingEvent ).
            
            @roundID        Number of Schelling round.
            @reward         Coin emission in this Schelling round.
            @bool           Was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Schelling') );
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            if ( modules[a].schellingEvent && abstractModule(modules[a].addr).isActive() ) {
                require( abstractModule(modules[a].addr).newSchellingRoundEvent(roundID, reward) );
            }
        }
        return true;
    }
    function replaceModuleHandler(address newHandler) external returns (bool) {
        /*
            Replacing ModuleHandler.
            
            Can be called only by the publisher.
            Every module will be informed about the ModuleHandler replacement.
            
            @newHandler     Address of the new ModuleHandler.
            @bool           Was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            require( abstractModule(modules[a].addr).replaceModuleHandler(newHandler) );
        }
        return true;
    }
    function balanceOf(address _owner) public constant returns (uint256 value, bool success) {
        /*
            Query of token balance.
            
            @_owner     address
            @value      balance.
            @success    was the function successfull?
        */
        var (id, found) = getModuleIDByName('Token');
        require( found );
        return (token(modules[id].addr).balanceOf(_owner), true);
    }
    function totalSupply() public constant returns (uint256 value, bool success) {
        /*
            Query of the whole token amount.
            
            @value      amount.
            @success    was the function successfull?
        */
        var (id, found) = getModuleIDByName('Token');
        require( found );
        return (token(modules[id].addr).totalSupply(), true);
    }
    function isICO() public constant returns (bool ico, bool success) {
        /*
            Query of ICO state
            
            @ico        Is ICO in progress?.
            @success    was the function successfull?
        */
        var (id, found) = getModuleIDByName('Token');
        require( found );
        return (token(modules[id].addr).isICO(), true);
    }
    function getCurrentSchellingRoundID() public constant returns (uint256 round, bool success) {
        /*
            Query of number of the actual Schelling round.
            
            @round      Schelling round.
            @success    was the function successfull?
        */
        var (id, found) = getModuleIDByName('Schelling');
        require( found );
        return (schelling(modules[id].addr).getCurrentSchellingRoundID(), true);
    }
    function mint(address _to, uint256 _value) external returns (bool success) {
        /*
            Token emission request. Can be called only by the provider.
            
            @_to        Place of new token
            @_value     Token amount.
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Provider') );
        (id, found) = getModuleIDByName('Token');
        require( found );
        require( token(modules[id].addr).mint(_to, _value) );
        return true;
    }
    function transfer(address _from, address _to, uint256 _value, bool _fee) external returns (bool success) {
        /*
            Token transaction request. If the _from isn’t equal with the address of the caller, than can be called only by the Schelling module.
            
            @_from      from who.
            @_to        to who.
            @_value     Token amount.
            @_fee       Transaction fee will be charged or not?
            @success    was the function successfull?
        */
        var (id, found) = getModuleIDByName('Token');
        require( found );
        if ( _from != msg.sender ) {
            var (sid, sfound) = searchModuleByAddress(msg.sender);
            require( sfound && modules[sid].name == sha3('Schelling') );
        }
        require( token(modules[id].addr).transferFromByModule(_from, _to, _value, _fee) );
        return true;
    }
    function processTransactionFee(address _from, uint256 _value) external returns (bool success) {
        /*
            Token transaction fee. Can be called only by the provider.
            
            @_from      from who.
            @_value     Token amount.
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Provider') );
        (id, found) = getModuleIDByName('Token');
        require( found );
        require( token(modules[id].addr).processTransactionFee(_from, _value) );
        return true;
    }
    function burn(address _from, uint256 _value) external returns (bool success) {
        /*
            Token burn. Can be called only by Schelling.
            
            @_from      from who.
            @_value     Token amount.
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Schelling') );
        (id, found) = getModuleIDByName('Token');
        require( found );
        require( token(modules[id].addr).burn(_from, _value) );
        return true;
    }
    function configureToken(announcementType a, uint256 b) external returns (bool success) {
        /*
            Changing token configuration. Can be called only by Publisher.
            
            @a          Type of variable (announcementType).
            @b          New value
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName('Token');
        require( found );
        require( token(modules[id].addr).configure(a, b) );
        return true;
    }
    function configureProvider(announcementType a, uint256 b) external returns (bool success) {
        /*
            Changing configuration of provider. Can be called only by provider
            
            @a          Type of variable (announcementType).
            @b          New value
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName('Provider');
        require( found );
        require( provider(modules[id].addr).configure(a, b) );
        return true;
    }
    function configureSchelling(announcementType a, uint256 b) external returns (bool success) {
        /*
            Changing configuration of Schelling. Can be called only by Publisher.
            
            @a          Type of variable (announcementType).
            @b          New value
            @success    was the function successfull?
        */
        var (id, found) = searchModuleByAddress(msg.sender);
        require( found && modules[id].name == sha3('Publisher') );
        (id, found) = getModuleIDByName('Schelling');
        require( found );
        require( schelling(modules[id].addr).configure(a, b) );
        return true;
    }
    function freezing(bool forever) external {
        /*
            Freezing CORION Platform. Can be called only by the owner.
            Freez can not be recalled!
            
            @forever    Is it forever or not?
        */
        require( super.isOwner() );
        for ( uint256 a=0 ; a<modules.length ; a++ ) {
            require( abstractModule(modules[a].addr).disableModule(forever) );
        }
    }
}