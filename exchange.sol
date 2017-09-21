/*
    publisher.sol
    
    Rajci 'iFA' Andor @ ifa@corion.io / ifa@ethereumlottery.net
    CORION Platform
*/
pragma solidity ^0.4.11;

import "./safeMath.sol";
import "./token.sol";
import "./owned.sol";

contract exchange is owned, safeMath {
    /* Structures */
    struct _pos {
        uint256[] orders;
        uint256 next;
        uint256 prev;
        bool sell;
        bool valid;
    }
    struct _orders {
        address owner;
        uint256 amount;
        uint256 rate;
        uint256 orderPos;
        bool valid;
    }
    struct _balances {
        uint256 t; // token
        uint256 e; // ether
    }
    /* Variables */
    uint256 public fee = 250;
    uint256 public feeM = 1e3;
    uint256 public orderUnit = 1e7; //10 COR
    uint256 public rateStep = 0.000000001 ether; // / ION
    uint    public lowGasStop = 250000;
    uint256 public tokenDecimals = 6;
    address public CORAddress;
    address public foundationAddress;
    
    uint256 public sellPrice;
    uint256 public buyPrice;
    uint256 public orderCounter;
    bool public disabled;
    mapping(uint256 => _pos) public pos;
    mapping(uint256 => _orders) public orders;
    mapping(address => _balances) public balances;
    /* Enumerations */
    enum confTypes { fee, feeM, orderUnit, rateStep, tokenAddr, foundationAddr }
    /* Constructor */
    function exchange(address corionAddress, address foundationAddr, uint256 counterStart) {
        owner = msg.sender;
        /*require( corionAddress != 0x00 );
        require( foundationAddr != 0x00 );*/
        CORAddress = corionAddress;
        foundationAddress = foundationAddr;
        orderCounter = counterStart;
        
        balances[0xca35b7d915458ef540ade6068dfe2f44e8fa733c].e = 100 ether;
        balances[0xca35b7d915458ef540ade6068dfe2f44e8fa733c].t = 1000000000;
        balances[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c].e = 100 ether;
        balances[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c].t = 1000000000;
    }
    /* Callback */
    function () payable {
        /*
            Fallback function for charging the ether balance..
        */
        crediting(msg.sender, msg.value, true, false);
        EPayIn(msg.sender, msg.value, true);
    }
    /* Token callbacks */
    function receiveToken(address from, uint256 amount, bytes data) external returns (bool success, uint256 payback) {
        /*
            Message about the fact that the contract has received corion token.
            This can only be requested by a token contract and just in case if the contract is not switched off.
            
            @from       From whom the transaction has come
            @amount     The amount that has arrived.
            @data       Extra data
        */
        require( ! disabled );
        require( msg.sender == CORAddress );
        if ( amount > 0 ) {
            if ( data.length > 0 ) {
                // 0xe0446432a13decc49ad56667b5c663e113491e99cd15b7150dbb47490bf13c4f -> instant
                if ( sha3(data) == bytes32(0xe0446432a13decc49ad56667b5c663e113491e99cd15b7150dbb47490bf13c4f) ) {
                    uint256 _ret;
                    (payback, _ret) = instantTrade(true, amount, 0, false);
                    require( from.send(_ret) );
                }
            } else {
                EPayIn(from, amount, false);
                balances[from].t = safeAdd(balances[from].t, amount);
            }
        }
        return ( true, payback );
    }
    function approvedToken(address from, uint256 amount, bytes data) external returns (bool) {}
    /* External functions */
    function setConfigValues(confTypes typ, uint256 value, address addr) external {
        /*
            Changing the exchange settings. Only allowed to call by the owner.
            
            @typ        The number of the desire variable.
            @value      Value.
            @addr       address.
        */
        require( isOwner() );
        if ( typ == confTypes.fee ) {
            fee = value;
        } else if ( typ == confTypes.feeM ) {
            feeM = value;
        } else if ( typ == confTypes.orderUnit ) {
            orderUnit = value;
        } else if ( typ == confTypes.rateStep ) {
            rateStep = value;
        } else if ( typ == confTypes.tokenAddr ) {
            CORAddress = addr;
        } else if ( typ == confTypes.foundationAddr ) {
            foundationAddress = addr;
        }
    }
    function disableContract() external {
        /*
            Stopping/switcing off the contract. Only allowed to call by the owner.
            After this just the positions should be closed and transfered from the account.
            This is irreversible.
        */
        require( isOwner() );
        disabled = true;
    }
    function sell(bool token, uint256 value, bool instant, uint256 rate) external {
        /*
            Offering token or ether for sale in order to open a position with a specified course or in instant mode. 
            It is only possible to offer what is located on the callers balance. 
            The rate and the amount will be normalized in all the cases.
            The rate has to be entered in WEI/ION resolution. Examples:
                1e12 wei rate: 1.000000 COR = 1 ether
                1e12 wei rate: 0.100000 COR = 0.1 ether
                1 ether = 15 USD = 15 COR -> 1 COR 0,066666666667 ETC => 0,000000066666666667 ETC/ION
                
            If the contract is closed/switched off then it is not possible to call this function.
            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
            @instant        Instant offer
            @rate           Rate which only counts if the offer is not instant.
        */
        uint256 _rate;
        uint256 _token;
        uint256 _ether;
        uint256 _back;
        uint256 _ret;
        require( ! disabled );
        if ( token ) {
            _token = normaliseUnit(value);
            if ( instant ) {
                (_back, _ret) = instantTrade(true, _token, 0, false);
                crediting(msg.sender, _ret, true, true);
                balances[msg.sender].t = safeSub(balances[msg.sender].t, value - _back);
            } else {
                balances[msg.sender].t = safeSub(balances[msg.sender].t, _token);
                _rate = normaliseRate(rate);
                insertPos(_rate, _token, true);
            }
        } else {
            if ( instant ) {
                (_back, _ret) = instantTrade(true, value, 0, true);
                balances[msg.sender].t = safeSub(balances[msg.sender].t, _ret);
                crediting(msg.sender, value - _back, true, true);
            } else {
                _rate = normaliseRate(rate);
                _token = etherToTokenAtPrice(value, _rate);
                _token = normaliseUnit(_token);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balances[msg.sender].e = safeSub(balances[msg.sender].e, _ether);
                insertPos(_rate, _token, false);
            }
        }
    }
    function buy(bool token, uint256 value, bool instant, uint256 rate) external {
        /*
            Token or ether offered for sale and for opening a new position in an instant way or in the quoted rate. 
            Only offerable which is found on the caller’s balance.
            The rate and the amount id going to be normalized in all the cases. 
            The rate has to be given in WEI/ 0.000001 resolution Examples:
                1e12 wei rate: 1.000000 COR = 1 ether
                1e12 wei rate: 0.100000 COR = 0.1 ether
                5       USD/ETC = 0.2                ETC/COR = 200000000000000000 ETC/COR = 200000000000 wei rate = 1 USD/COR
                7.154   USD/ETC = 0.1397819401733296 ETC/COR = 139781940173329600 ETC/COR = 139781940173 wei rate = 1 USD/COR
                during ico:
                5       USD/ETC = 0.18               ETC/COR = 180000000000000000 ETC/COR = 180000000000 wei rate = 0.9 USD/COR
            If the contract is closed/switched off then it is not possible to call this function.            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
            @instant        If it is an instant offer
            @rate           Rate which only counts if the offer is not instant.
        */
        uint256 _rate;
        uint256 _token;
        uint256 _ether;
        uint256 _back;
        uint256 _ret;
        require( ! disabled );
        if ( token ) {
            if ( instant ) {
                (_back, _ret) = instantTrade(false, value, 0, false);
                balances[msg.sender].e = safeSub(balances[msg.sender].e, _ret);
                crediting(msg.sender, value - _back, false, true);
            } else {
                _rate = normaliseRate(rate);
                //_token = etherToTokenAtPrice(value, _rate);
                _token = normaliseUnit(value);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balances[msg.sender].e = safeSub(balances[msg.sender].e, _ether);
                insertPos(_rate, _token, false);
            }
        } else {
            if ( instant ) {
                (_back, _ret) = instantTrade(false, value, 0, true);
                balances[msg.sender].e = safeSub(balances[msg.sender].e, value - _back);
                crediting(msg.sender, _ret, false, true);
            } else {
                _rate = normaliseRate(rate);
                _token = etherToTokenAtPrice(value, _rate);
                _token = normaliseUnit(_token);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balances[msg.sender].e = safeSub(balances[msg.sender].e, _ether);
                insertPos(_rate, _token, false);
            }
        }
    }
    function payout(uint256 amount, bool eth) external {
        /*
            Launching the payment
            When the token is  allocated the transaction fee will be charged from the requested amount.
            If the payment is asked by the owner of the exchange then the difference of the real contracts balance and the inventory will be set automatically.
            
            @amount         Amount of payment
            @eth            In case it is TRUE then it is requested from the ether account, in case it is FALSE then from the token account.
        */
        if ( eth ) {
            balances[msg.sender].e = safeSub(balances[msg.sender].e, amount);
            require( msg.sender.send(amount) );
            EPayOut(msg.sender, amount, true);
        } else {
            balances[msg.sender].t = safeSub(balances[msg.sender].t, amount);
            var (_success, _fee) = token(CORAddress).getTransactionFee(amount);
            require( _success );
            if ( _fee > 0 ) {
                require( token(CORAddress).transfer(msg.sender, safeSub(amount, _fee)) );
            } else {
                require( token(CORAddress).transfer(msg.sender, amount) );
            }
            EPayOut(msg.sender, amount, false);
        }
    }
    function moveOrder(uint256 orderID, uint256 newRate) external {
        /*
            Modifying the rate of the mandate.
            In this case the mandate will be cancelled (deleteOrder), it will be relocated (insertPos) and will get a new ID.
            If the exchange contract is stopped then this function is not callable.
            @orderID    Number of the mandate.
            @newRate    New rate
        */
        require( ! disabled );
        uint256 _newRate = newRate / rateStep * rateStep;
        var _oldRate = orders[orderID].rate;
        require( _newRate != _oldRate );
        require( orders[orderID].valid );
        require( orders[orderID].owner == msg.sender );
        var _amount = orders[orderID].amount;
        bool _sell = pos[_oldRate].sell;
        deleteOrder(orderID, true);
        insertPos(_newRate, _amount, _sell);
    }
    function cancelOrder(uint256 orderID) external {
        /*
            Mandate withdrawal.
            Only that mandate can be withdrawn which was launched from that address. 
            The mandate will be cancelled and the amount will be withdrawn on the account of the caller.

            @orderID    Number of the mandate
        */
        var _oldRate = orders[orderID].rate;
        
        require( orders[orderID].valid );
        require( orders[orderID].owner == msg.sender );
        
        if ( pos[_oldRate].sell ) {
            crediting(msg.sender, orders[orderID].amount, false, false);
        } else {
            crediting(msg.sender, orders[orderID].amount * orders[orderID].rate * (10**tokenDecimals) , true, false);
        }
        deleteOrder(orderID, true);
    }
    function emergency_payout(address tokenAddr, address to) external {
        require( isOwner() );
        require( disabled );
        var _balance = token(tokenAddr).balanceOf(address(this));
        if ( _balance > 0 ) {
            token(tokenAddr).transfer(to, _balance);
        }
        to.send(this.balance);
    }
    /* Internals */
    function normaliseRate(uint256 rate) internal returns (uint256 nRate) {
        /*
            Inner function for normalizing the rate.
            During the normalizing process we divide with the resolution and multiply. 
            Because there is no fraction that is why the value which is less than the resolution will get lost.
            For example: Resolution of the rate (rateStep) is 0.0001 ether and the entered rate was 0.123456 by the user then the function will give 0.1234 ether back.
            @rate       exchange rate
            @nRate      Normalized rate
        */
        nRate = rate / rateStep * rateStep;
        assert( nRate > 0 );
    }
    function normaliseUnit(uint256 unit) internal returns (uint256 nUnit) {
        /*
            Inner function for normalizing the sell/buy token amount.
            During the normalizing process the contract divide with the resolution and multiply.
            Because there is no fraction that is why the value which is less than the resolution will get lost.
            Resollution of the value (orderUnit) is 1.000000 token and the user entered 1.99 as an amount then 1 token will be given back by the function.
            
            @unit      Amount of token
            @nUnit     Normalized amount of token
        */
        nUnit = unit / orderUnit * orderUnit;
        assert( nUnit > 0 );
    }
    function etherToTokenAtPrice(uint256 value, uint256 rate) internal returns (uint256 token) {
        /*
            Inner function which shows that how many value of token can be given for hat amount of ether in that rate
            
            @value      amount of ether (in wei) 
            @rate       rate
            @token      Amount of token
        */
        token = value * (10**tokenDecimals) / rate;
        assert( token >= 0 );
    }
    function tokenToEtherAtPrice(uint256 value, uint256 rate) internal returns (uint256 eth) {
        /*
            Inner function which shows that how many value of token can be given for hat amount of ether in that rate

            @value     Amount of token
            @rate       Rate
            @eth        Amount of ether.
        */
        eth = value * rate / (10**tokenDecimals);
        assert( eth >= 0 );
    }
    function insertToPos(uint256 _rate, uint256 _amount, bool _sell) internal {
        /*
            Inner function for integrating to the positions. 
            
            @_rate      rate
            @_amount    Amount of tokens
            @_sell      Sale or buy/purchase?
        */
        uint256 tmpRate;
        if ( ! pos[_rate].valid ) {
            if ( _sell && sellPrice > 0 ) {
                tmpRate = sellPrice;
            } else if ( ! _sell && buyPrice > 0 ) {
                tmpRate = buyPrice;
            }
            if ( tmpRate > 0 ) {
                if ( _sell && sellPrice > _rate ) {
                    pos[_rate].prev = sellPrice;
                    pos[sellPrice].next = _rate;
                } else if ( ! _sell && buyPrice < _rate ) {
                    pos[_rate].prev = buyPrice;
                    pos[buyPrice].next = _rate;
                } else {
                    while(true) {
                        if ( pos[tmpRate].prev > 0 ) {
                            if ( ( _sell && pos[tmpRate].prev > _rate ) || ( ! _sell && pos[tmpRate].prev < _rate ) ) {
                                pos[_rate].next = tmpRate;
                                pos[_rate].prev = pos[tmpRate].prev;
                                pos[pos[tmpRate].prev].next = _rate;
                                pos[tmpRate].prev = _rate;
                                break;
                            } else {
                                tmpRate = pos[tmpRate].prev;
                                continue;
                            }
                        } else {
                            pos[tmpRate].prev = _rate;
                            pos[_rate].next = tmpRate;
                            break;
                        }
                    }
                }
            }
            if ( _sell && ( sellPrice > _rate || sellPrice == 0 ) ) { sellPrice = _rate; }
            if ( ! _sell && ( buyPrice < _rate || buyPrice == 0 ) ) { buyPrice = _rate; }
        }
        pos[_rate].valid = true;
        pos[_rate].sell = _sell;
        
        orderCounter++;
        orders[orderCounter] = _orders(msg.sender, _amount, _rate, 0, true);

        ENewOrder(orderCounter, msg.sender, _rate, _amount);
        for ( uint256 a=0 ; a<pos[_rate].orders.length ; a++ ) {
            if ( pos[_rate].orders[a] == 0 ) {
                pos[_rate].orders[a] = orderCounter;
                orders[orderCounter].orderPos = a;
                return;
            }
        }
        orders[orderCounter].orderPos = pos[_rate].orders.push(orderCounter)-1;
    }
    function insertPos(uint256 _rate, uint256 _amount, bool _sell) internal {
        /*
            Inner function for creating a position.
            In case it exists then it integrates in between.
            
            @_rate     Rate
            @_amount   Amount of tokens.
            @_sell     Sale or buy/purchase?
        */
        uint256 left;
        uint256 ret;
        if ( ( _sell && _rate <= buyPrice && buyPrice != 0) || ( ( ! _sell ) && _rate >= sellPrice  && sellPrice != 0) ) {
            (left, ret) = instantTrade(_sell, _amount, _rate, false);
            crediting(msg.sender, ret, ! _sell, true);
        } else {
            insertToPos(_rate, _amount, _sell);
        }
        if ( left > 0 ) {
            insertToPos(_rate, left, _sell);
        }
    }
    function instantTradeScanOrders(uint256 currentRate, uint256 _token, bool _sell, bool jump) internal returns (uint256 left, uint256 jumpTo, bool stop) {
        /*
            Inner function in order to complete the offers located in the position.
            
            @currentRate     rate
            @_token          Amount of tokens.
            @_sell           Sale or buy/purchase?
            @jump            If so then it should give back which the next rate is
            @left            Amount of the remaining tokens.
            @jumpTo          Next rate.
            @stop            Should the implementation stop or not? It stops when there is no more offer or in case running out of token
        */
        bool deleteThisOrder;
        uint256 value;
        uint256 deleteThisPos = pos[currentRate].orders.length;
        uint256 orderID;
        left = _token;
        for ( uint256 a=0 ; a<pos[currentRate].orders.length ; a++ ) {
            orderID = pos[currentRate].orders[a];
            deleteThisOrder = false;
            if ( ! orders[orderID].valid ) {
                deleteThisPos--;
                continue;
            }
            if ( orders[orderID].amount >= left ) {
                value = left;
                orders[orderID].amount -= left;
                if ( orders[orderID].amount == 0 ) {
                    deleteThisOrder = true;
                } else {
                    EOrderPartial(orderID, orders[orderID].owner, value);
                }
                stop = true;
                left = 0;
            } else {
                value = orders[orderID].amount;
                left -= value;
                deleteThisOrder = true;
            }
            if ( ! _sell ) {
                value = value * currentRate;
            }
            crediting(orders[orderID].owner, value, ! _sell, true);
            if ( deleteThisOrder ) {
                deleteThisPos--;
                deleteOrder(orderID, false);
            }
            if ( stop || msg.gas <= lowGasStop) {
                break;
            }
        }
        if ( ! stop && jump ) {
            if ( pos[currentRate].prev > 0 ) {
                jumpTo = pos[currentRate].prev;
            } else {
                stop = true;
            }
        }
        if ( deleteThisPos == 0 ) {
            deletePos(currentRate);
        }
    }
    function instantTrade(bool _sell, uint256 _amount, uint256 _rateLimit, bool _ether) internal returns (uint256 left, uint256 ret) {
        /*
            Inner funcion in order to completing the offer.
            If @ether is true then the @amount should be given in ether.
            If @sell is true then the @amount should be sold.
                The @left is the remaining ether. The @ret is the successfully purchased amount of tokens.
                If @sell is false then @amount should be purchased.
                The @left is the remaining ether. The @ret is the successfully sold amount of the tokens.
            In case the @ether is false then the @amount has to be given in tokens.
            In case @sell is true then the @amount should be sold.
            The @left is the remaining token. The @ret is the successfully purchased amount of ether.
            If @sell is false then @amount should be purchased.
            The @left is the remaining amount of tokens. The @ret is the successfully purchased amount of ethers.
            In case the @ratelimit is defined then the exchange rate jump is possible. When selling happens it can not be sold cheaper when it is purchasing it can not be more expensive.
            
            @_sell          If it is TRUE she/he wants to sell if it is FALSE then wants to buy
            @_amount        amount
            @_rateLimit     Exchange rate limitation
            @_ether         Ether amount
            @left           Remaining amount 
            @ret            Value of the offerred amount
        */
        uint256 currentRate;
        bool stop;
        uint256 jumpTo;
        uint256 _token;
        uint256 _tokenLeft;
        
        left = _amount;
        if ( _sell ) {
            currentRate = buyPrice;
        } else {
            currentRate = sellPrice;
        }
        while( left > 0 ) {
            if ( currentRate == 0 ) { break; }
            if ( _ether ) {
                _token = left / currentRate / orderUnit * orderUnit;
                if ( _token == 0 ) {
                    break;
                }
            } else {
                _token = left / orderUnit * orderUnit;
            }
            (_tokenLeft, jumpTo, stop) = instantTradeScanOrders(currentRate, _token, _sell, _rateLimit == 0);
            
            if ( _ether ) {
                left -= (_token - _tokenLeft) * currentRate;
                ret += _token - _tokenLeft;
            } else {
                left -= _token - _tokenLeft;
                ret += (_token - _tokenLeft) * currentRate;
            }
            if ( stop || ( jumpTo == 0 || ( _rateLimit > 0 && ( ( _sell && jumpTo > _rateLimit) || ( ! _sell && jumpTo < _rateLimit) ) ) ) ) { break; }
            currentRate = jumpTo;
        }
    }
    function deletePos(uint256 _rate) internal {
        /*
            Inner function for a complete  cancellation of a position
            
            @_rate      rate
        */
        if ( pos[_rate].next > 0 && pos[_rate].prev > 0 ) {
            pos[pos[_rate].next].prev = pos[_rate].prev;
            pos[pos[_rate].prev].next = pos[_rate].next;
        } else if ( pos[_rate].next == 0 && pos[_rate].prev > 0 ) {
            delete pos[pos[_rate].prev].next;
        } else if ( pos[_rate].prev == 0 && pos[_rate].next > 0 ) {
            delete pos[pos[_rate].next].prev;
        }
        if ( pos[_rate].sell && _rate == sellPrice ) {
            if ( pos[_rate].prev > 0 ) { sellPrice = pos[_rate].prev; }
            else { delete sellPrice; }
        } else if ( ! pos[_rate].sell && _rate == buyPrice ) {
            if ( pos[_rate].prev > 0 ) { buyPrice = pos[_rate].prev; }
            else { delete buyPrice; }
        }
        delete pos[_rate];
    }
    function crediting(address _to, uint256 _amount, bool _ether, bool _fee) internal {
        /*
            Inner function for crediting token or ether.
            
            @_to        Address of the receiver
            @_amount    Amount of token
            @_ether     Amount of ether
            @_fee       fee
        */
        uint256 amount;
        uint256 feeValue;
        if ( _fee ) {
            feeValue = calcFee(_amount);
            amount = safeSub(_amount, feeValue);
        } else {
            amount = _amount;
        }
        if ( _ether ) {
            balances[_to].e = safeAdd(balances[_to].e, amount);
            if ( feeValue > 0 ) {
                balances[foundationAddress].e = safeAdd(balances[foundationAddress].e, feeValue);
            }
        } else {
            balances[_to].t = safeAdd(balances[_to].t, amount);
            if ( feeValue > 0 ) {
                balances[foundationAddress].t = safeAdd(balances[foundationAddress].t, feeValue);
            }
        }
    }
    function calcFee(uint256 amount) internal returns (uint256 feeAmount) {
        /*
            Inner function to calculate the exchange fee.
            
            @amount  Amount of the input
            @fee     Amount of the fee
        */
        return amount * fee / feeM / 100;
    }
    function deleteOrder(uint256 orderID, bool scan) internal {
        /*
            Inner function to cancell a mandate.
            If there is no valid mandate in the position then the position is going to be cancelled as well.
            
            @orderID        ID of the mandate
        */
        bool delIt = true;
        var _rate = orders[orderID].rate;
        var _owner = orders[orderID].owner;
        
        delete pos[_rate].orders[orders[orderID].orderPos];
        delete orders[orderID];
        
        if ( scan ) {
            for ( uint256 a=0 ; a<pos[_rate].orders.length ; a++ ) {
                if ( pos[_rate].orders[a] != 0 ) {
                    delIt = false;
                    break;
                }
            }
            if ( delIt ) {
                deletePos(_rate);
            }
            EOrderCancelled(orderID, msg.sender);
        } else {
            EOrderDone(orderID, _owner);
        }
    }
    /* Constants */
    function getSell(bool token, uint256 value) public constant returns(uint256 spend, uint256 remain, uint256 gasNeed) {
        /*
            Simulation: about buying token or ether instantly
            If there is no offer or the resolution is too low that remains
            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
        */
        gasNeed = msg.gas;
        var (_back, _ret) = instantTrade(true, value, 0, ! token);
        if ( token ) {
            spend = value - _back;
            remain = _ret;
        } else {
            spend = _ret;
            remain = value - _back;
        }
        spend = spend-calcFee(spend);
        gasNeed = gasNeed - msg.gas;
    }
    function getBuy(bool token, uint256 value) public constant returns(uint256 spend, uint256 remain, uint256 gasNeed) {
        /*
            Simulation
            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
        */
        gasNeed = msg.gas;
        var (_back, _ret) = instantTrade(false, value, 0, ! token);
        if ( token ) {
            spend = value - _back;
            remain = _ret;
        } else {
            spend = _ret;
            remain = value - _back;
        }
        spend = spend-calcFee(spend);
        gasNeed = gasNeed - msg.gas;
    }
    function getOrder(uint256 orderID) public constant returns (address owner, uint256 amount, uint256 rate, bool sell) {
        if ( orders[orderID].valid ) {
            owner = orders[orderID].owner;
            amount = orders[orderID].amount;
            rate = orders[orderID].rate;
            sell = pos[orders[orderID].rate].sell;
        }
    }
    /* Events */
    event EPayOut(address owner, uint256 amount, bool eth);
    event EPayIn(address owner, uint256 amount, bool eth);
    event ENewOrder(uint256 orderID, address onwer, uint256 rate, uint256 amount);
    event EOrderDone(uint256 orderID, address onwer);
    event EOrderPartial(uint256 orderID, address onwer, uint256 amount);
    event EOrderCancelled(uint256 orderID, address onwer);
}
