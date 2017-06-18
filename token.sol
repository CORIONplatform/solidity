pragma solidity ^0.4.11;

import "announcementTypes.sol";
import "safeMath.sol";
import "module.sol";
import "moduleHandler.sol";
import "tokenDB.sol";

contract thirdPartyContractAbstract {
    function receiveCorionToken(address, uint256, bytes) external returns (bool, uint256) {}
    function approvedCorionToken(address, uint256, bytes) external returns (bool) {}
}

contract token is safeMath, module, announcementTypes {
    /*
        module callbacks
    */
    function connectModule() external returns (bool) {
        require( super._connectModule() );
        return true;
    }
    function disconnectModule() external returns (bool) {
        require( super._disconnectModule() );
        return true;
    }
    function replaceModule(address addr) external returns (bool) {
        require( db.replaceOwner(addr) );
        require( super._replaceModule(addr) );
        return true;
    }
    function disableModule(bool forever) external returns (bool) {
        require( super._disableModule(forever) );
        return true;
    }
    function isActive() public constant returns (bool) {
        return super._isActive();
    }
    function replaceModuleHandler(address newHandler) external returns (bool) {
        require( super._replaceModuleHandler(newHandler) );
        return true;
    }
    modifier isReady { require( super._isActive() ); _; }
    /**
    *
    * @title Corion Platform Token
    * @author iFA @ Corion Platform
    *
    */
    string public name = "Corion";
    string public symbol = "COR";
    uint8 public decimals = 6;
    
    tokenDB private db;
    address public icoAddr;
    uint256 private transactionFeeRate      = 20;
    uint256 private transactionFeeRateM     = 1e3;
    uint256 private transactionFeeMin       =   20000;
    uint256 private transactionFeeMax       = 5000000;
    uint256 private transactionFeeBurn      = 80;
    address private exchangeAddress;
    bool    public  isICO                   = true;
    
    struct _allowance {
        uint256 amount;
        uint256 transactionCount;
    }
    
    mapping(address => mapping(address => _allowance)) private allowance_;
    mapping(address => bool) private genesis;
    
    function token(bool _forReplace, address _moduleHandler, address _db, address _icoAddr, address _exchangeAddress, address[] genesisAddr, uint256[] genesisValue) payable {
        /*
            Installation function
            
            When _icoAddr is defined, 0.2 ether has to be attached  as many times  as many genesis addresses are given
            
            @_forReplace        This address will be replaced with the old one or not.
            @_moduleHandler     modulhandler’s address
            @_db                Address of database
            @_icoAddr           Address of ICO contract
            @_exchangeAddress   address of Market in order to buy gas during ICO
            @genesisAddr        array of Genesis addresses
            @genesisValue       array of balance of genesis addresses
        */
        require( super._registerModuleHandler(_moduleHandler) );
        require( _db != 0x00 );
        require( _icoAddr != 0x00 );
        require( _exchangeAddress != 0x00 );
        db = tokenDB(_db);
        icoAddr = _icoAddr;
        exchangeAddress = _exchangeAddress;
        isICO = ! _forReplace;
        if ( ! _forReplace ) {
            require( db.replaceOwner(this) );
            assert( genesisAddr.length == genesisValue.length );
            require( this.balance >= genesisAddr.length * 0.2 ether );
            for ( uint256 a=0 ; a<genesisAddr.length ; a++ ) {
                genesis[genesisAddr[a]] = true;
                require( db.increase(genesisAddr[a], genesisValue[a]) );
                if ( ! genesisAddr[a].send(0.2 ether) ) {}
                Mint(genesisAddr[a], genesisValue[a]);
            }
        }
    }
    
    function closeIco() external returns (bool) {
        /*
            ICO finished. It can be called only by ICO contract
            
            @bool       Was the Function successful?
        */
        require( msg.sender == icoAddr );
        isICO = false;
        return true;
    }
    
    /**
     * @notice `msg.sender` approves `_spender` to spend `_amount` tokens on its behalf.
     * @param _spender The address of the account able to transfer the tokens
     * @param _amount The amount of tokens to be approved for transfer
     * @param _transactionCount The transaction count of the authorised address
     * @return True if the approval was successful
     */
    function approve(address _spender, uint256 _amount, uint256 _transactionCount) isReady external returns (bool) {
        /*
            Authorise another address to use a certain quantity of the authorising owner’s balance
         
            @_spender           Address of authorised party
            @_amount            Token quantity
            @_transactionCount  Transaction count
            
            @bool               Was the Function successful?
        */
        approve_(_spender, _amount, _transactionCount);
        return true;
    }
    
    /**
     * @notice `msg.sender` approves `_spender` to spend `_amount` tokens on its behalf and notify the spender from your approve with your `_extraData` data.
     * @param _spender The address of the account able to transfer the tokens
     * @param _amount The amount of tokens to be approved for transfer
     * @param _transactionCount The transaction count of the authorised address
     * @param _extraData Data to give forward to the receiver
     * @return True if the approval was successful
     */
    function approveAndCall(address _spender, uint256 _amount, uint256 _transactionCount, bytes _extraData) isReady external returns (bool) {
        /*
            Authorise another address to use a certain quantity of the authorising  owner’s balance
            Following the transaction the receiver address `approvedCorionToken` function is called by the given data
            
            @_spender           Authorized address
            @_amount            Token quantity
            @_extraData         Extra data to be received by the receiver
            @_transactionCount  Transaction count
            
            @bool               Was the Function successful?
        */
        approve_(_spender, _amount, _transactionCount);
        require( thirdPartyContractAbstract(_spender).approvedCorionToken(msg.sender, _amount, _extraData) );
        return true;
    }
    
    function approve_(address _spender, uint256 _amount, uint256 _transactionCount) internal {
        /*
            Internal Function to authorise another address to use a certain quantity of the authorising owner’s balance.
            If the transaction count not match the authorise fails.
            
            @_spender           Address of authorised party
            @_amount            Token quantity
            @_transactionCount  Transaction count
        */
        require( msg.sender != _spender );
        require( db.balanceOf(msg.sender) >= _amount );
        require( allowance_[msg.sender][_spender].transactionCount == _transactionCount );
        allowance_[msg.sender][_spender].amount = _amount;
        Approval(msg.sender, _spender, _amount);
    }
    
    function allowance(address _owner, address _spender) constant returns (uint256 remaining, uint256 transactionCount) {
        /*
            Get the quantity of tokens given to be used
            
            @_owner        authorising address
            @_spender      authorised address
            @remaining     tokens to be spent
        */
        remaining = allowance_[_owner][_spender].amount;
        transactionCount = allowance_[_owner][_spender].transactionCount;
    }
    
    /**
     * @notice Send `_amount` Corion tokens to `_to` from `msg.sender`
     * @param _to The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return Whether the transfer was successful or not
     */
    function transfer(address _to, uint256 _amount) isReady external returns (bool) {
        /*
            Start transaction, token is sent from caller’s address to receiver’s address
            Transaction fee is to be deducted.
            If receiver is not a natural address but a person, he will be called
          
            @_to       to who
            @_amount   quantity
            @bool      Was the Function successful?
        */
        if ( isContract(_to) ) {
            bytes memory data;
            transferToContract(msg.sender, _to, _amount, data);
        } else {
            transfer_( msg.sender, _to, _amount, true);
            Transfer(msg.sender, _to, _amount);
        }
        return true;
    }
    
    /**
     * @notice Send `_amount` tokens to `_to` from `_from` on the condition it is approved by `_from`
     * @param _from The address holding the tokens being transferred
     * @param _to The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return True if the transfer was successful
     */
    function transferFrom(address _from, address _to, uint256 _amount) isReady external returns (bool) {
        /*
            Start transaction to send a quantity from a given address to another address. (approve / allowance). This can be called only by the address approved in advance
            Transaction fee is to be deducted
            If receiver is not a natural address but a person, he will be called
            
            @_from      from who.
            @_to        to who
            @_amount    quantity
            @bool       Was the Function successful?
        */
        if ( _from != msg.sender ) {
            allowance_[_from][msg.sender].amount = safeSub(allowance_[_from][msg.sender].amount, _amount);
            allowance_[_from][msg.sender].transactionCount++;
            AllowanceUsed(msg.sender, _from, _amount);
        }
        if ( isContract(_to) ) {
            bytes memory data;
            transferToContract(_from, _to, _amount, data);
        } else {
            transfer_( _from, _to, _amount, true);
            Transfer(_from, _to, _amount);
        }
        return true;
    }
    
    /**
     * @notice Send `_amount` tokens to `_to` from `_from` on the condition it is approved by `_from`
     * @param _from The address holding the tokens being transferred
     * @param _to The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return True if the transfer was successful
     */
    function transferFromByModule(address _from, address _to, uint256 _amount, bool _fee) isReady external returns (bool) {
        /*
            Start transaction to send a quantity from a given address to another address
            Only ModuleHandler can call it
           
            @_from      from who
            @_to        to who.
            @_amount    quantity
            @_fee       deduct transaction fee - yes or no?
            @bool       Was the Function successful?
        */
        require( super._isModuleHandler(msg.sender) );
        transfer_( _from, _to, _amount, _fee);
        Transfer(_from, _to, _amount);
        return true;
    }
    
    /**
     * @notice Send `_amount` Corion tokens to `_to` from `msg.sender` and notify the receiver from your transaction with your `_extraData` data
     * @param _to The contract address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @param _extraData Data to give forward to the receiver
     * @return Whether the transfer was successful or not
     */
    function transfer(address _to, uint256 _amount, bytes _extraData) isReady external returns (bool) {
        /*
            Start transaction to send a quantity from a given address to another address
            After transaction the function `receiveCorionToken`of the receiver is called  by the given data
            When sending an amount, it is possible the total amount cannot be processed, the remaining amount is sent back with no fee charged
            
            @_to            to who.
            @_amount        quantity
            @_extraData     extra data the receiver will get
            @bool           Was the Function successful?
        */
        transferToContract(msg.sender, _to, _amount, _extraData);
        return true;
    }
    
    function transferToContract(address _from, address _to, uint256 _amount, bytes _extraData) internal {
        /*
            Internal function to start transactions to a contract
            
            @_to            to who.
            @_amount        quantity
            @_extraData     extra data the receiver will get
        */
        transfer_(_from, _to, _amount, exchangeAddress == _to);
        var (success, back) = thirdPartyContractAbstract(_to).receiveCorionToken(_from, _amount, _extraData);
        require( success );
        require( _amount > back );
        if ( back > 0 ) {
            transfer_(_to, _from, back, false);
        }
        _processTransactionFee(_from, _amount - back);
        Transfer(_from, _to, _amount-back, _extraData);
    }
    
    function transfer_(address _from, address _to, uint256 _amount, bool _fee) internal {
        /*
            Internal function to start transactions. When Tokens are sent, transaction fee is charged
            During ICO transactions are allowed only from genesis addresses.
            After sending the tokens, the ModuleHandler is notified and it will  broadcast the fact among members 
            
            The 0xa636a97578d26a3b76b060bbc18226d954cf3757 address are blacklisted.
            
            @_from      from who
            @_to        to who
            @_amount    quantity
            @_fee       deduct transaction fee - yes or no?
        */
        require( _from != 0x00 && _to != 0x00 && _to != 0xa636a97578d26a3b76b060bbc18226d954cf3757 );
        require( ( ! isICO) || genesis[_from] );
        require( db.decrease(_from, _amount) );
        require( db.increase(_to, _amount) );
        if ( _fee ) { _processTransactionFee(_from, _amount); }
        if ( isICO ) {
            require( ico(icoAddr).setInterestDB(_from, db.balanceOf(_from)) );
            require( ico(icoAddr).setInterestDB(_to, db.balanceOf(_to)) );
        }
        Transfer(_from, _to, _amount);
        require( moduleHandler(super._getModuleHandlerAddress()).broadcastTransfer(_from, _to, _amount) );
    }
    
    /**
     * @notice Transaction fee will be deduced from `addr` for transacting `value`
     * @param addr The address where will the transaction fee deduced
     * @param value The base for calculating the fee
     * @return True if the transfer was successful
     */
    function processTransactionFee(address addr, uint256 value) isReady external returns (bool) {
        /*
            Charge transaction fee. It can be called only by moduleHandler  
        
            @addr       from who.
            @value      quantity to calculate the fee
            @bool       Was the Function successful?
        */
        require( super._isModuleHandler(msg.sender) );
        _processTransactionFee(addr, value);
        return true;
    }
    
    function _processTransactionFee(address addr, uint256 value) internal {
        /*
            Internal function to charge the transaction fee. A certain quantity is burnt, the rest is sent to the Schelling game prize pool.
            No transaction fee during ICO.
            
            @addr       from who
            @value      quantity to calculate the fee
        */
        if ( isICO ) { return; }
        var fee = getTransactionFee(value);
        uint256 forBurn = fee * transactionFeeBurn / 100;
        uint256 forSchelling = fee - forBurn;
        
        var (schellingAddr, schF, s) = moduleHandler(super._getModuleHandlerAddress()).getModuleAddressByName('Schelling');
        require( s );
        if ( schellingAddr != 0x00 ) {
            require( db.decrease(addr, forSchelling) );
            require( db.increase(schellingAddr, forSchelling) );
            burn_(addr, forBurn);
            Transfer(addr, schellingAddr, forSchelling);
            require( moduleHandler(super._getModuleHandlerAddress()).broadcastTransfer(addr, schellingAddr, forSchelling) );
        } else {
            burn_(addr, fee);
        }
    }
    
    function getTransactionFee(uint256 value) public constant returns (uint256 fee) {
        /*
            Transaction fee query
     
            @value      quantity to calculate the fee
            @fee        Amount of Transaction fee
        */
        fee = value * transactionFeeRate / transactionFeeRateM / 100;
        if ( fee > transactionFeeMax ) { fee = transactionFeeMax; }
        else if ( fee < transactionFeeMin ) { fee = transactionFeeMin; }
    }
    
    function mint(address _owner, uint256 _value) isReady external returns (bool) {
        /*
            Generating tokens. It can be called only by ICO contract or the moduleHandler.
            
            @_owner     address
            @_value     amount.
            @bool       Was the Function successful?
        */
        require( super._isModuleHandler(msg.sender) || msg.sender == icoAddr );
        mint_(_owner, _value);
        return true;
    }
    
    function mint_(address _owner, uint256 _value) internal {
        /*
            Internal function to generate tokens
            
            @_owner     Token is credited to this address
            @_value     quantity
        */
        require( db.increase(_owner, _value) );
        require( moduleHandler(super._getModuleHandlerAddress()).broadcastTransfer(0x00, _owner, _value) );
        if ( isICO ) {
            require( ico(icoAddr).setInterestDB(_owner, db.balanceOf(_owner)) );
        }
        Mint(_owner, _value);
    }
    
    function burn(address _owner, uint256 _value) isReady external returns (bool) {
        /*
            Burning the token. Can call only modulehandler
            
            @_owner     Burn the token from this address
            @_value     quantity
            @bool       Was the Function successful?
        */
        require( super._isModuleHandler(msg.sender) );
        burn_(_owner, _value);
        return true;
    }
    
    function burn_(address _owner, uint256 _value) internal {
        /*
            Internal function to burn the token
     
            @_owner     Burn the token from this address
            @_value     quantity
        */
        require( db.decrease(_owner, _value) );
        require( moduleHandler(super._getModuleHandlerAddress()).broadcastTransfer(_owner, 0x00, _value) );
        Burn(_owner, _value);
    }
    
    function isContract(address addr) internal returns (bool) {
        /*
            Internal function to check if the given address is natural, or a contract
            
            @addr       address to be checked
        */
        uint codeLength;
        assembly {
            codeLength := extcodesize(addr)
        }
        return codeLength > 0;
    }
    
    function balanceOf(address _owner) constant returns (uint256 _value) {
        /*
            Token balance query
            
            @_owner     address
            @_value     balance of address
        */
        return db.balanceOf(_owner);
    }
    
    function totalSupply() constant returns (uint256 _value) {
        /*
            Total token quantity query
            
            @_value     Total token quantity
        */
        return db.totalSupply();
    }
    
    function configure(announcementType a, uint256 b) isReady external returns(bool) {
        /*
            Token settings configuration.It  can be call only by moduleHandler
           
            @a      Type of setting
            @b      value
        */
        require( super._isModuleHandler(msg.sender) );
        if      ( a == announcementType.transactionFeeRate )    { transactionFeeRate = b; }
        else if ( a == announcementType.transactionFeeMin )     { transactionFeeMin = b; }
        else if ( a == announcementType.transactionFeeMax )     { transactionFeeMax = b; }
        else if ( a == announcementType.transactionFeeBurn )    { transactionFeeBurn = b; }
        else { return false; }
        return true;
    }
    
    event AllowanceUsed(address indexed spender, address indexed owner, uint256 indexed value);
    event Mint(address indexed addr, uint256 indexed value);
    event Burn(address indexed addr, uint256 indexed value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _extraData);
}
