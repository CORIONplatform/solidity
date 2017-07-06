pragma solidity ^0.4.11;

import "./safeMath.sol";
import "./token.sol";
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

contract exchange is owned, safeMath {
    uint256 public fee = 250;
    uint256 public feeM = 1e3;
    uint256 public orderUnit = 1e6;
    uint256 public rateStep = 0.0001 ether;
    uint256 public maxForGasSell = 1 ether;
    
    token public corion;
    uint256 public sellPrice;
    uint256 public buyPrice;
    uint256 private orderCounter;
    bool public disabled;

    enum confTypes { fee, feeM, orderUnit, rateStep, maxForGasSell, tokenAddr }
    
    struct _pos {
        uint256[] orders;
        uint256 next;
        uint256 prev;
        bool sell;
        bool valid;
    }
    mapping(uint256 => _pos) private pos;
    
    struct _orders {
        address owner;
        uint256 amount;
        uint256 rate;
        uint256 orderPos;
        bool valid;
    }
    mapping(uint256 => _orders) private orders;
    
    struct _balance {
        uint256 t; // token
        uint256 e; // ether
    }
    mapping(address => _balance) private balance;
    uint256 private exchangeTokenBalance;
    uint256 private exchangeEtherBalance;
    
    enum callbackData {
        nothing,
        buyForGas
    }
    
    function exchange(address _token, uint256 counterStart) {
        /*
            Installation function.
            
            @_token     Address of the token.
        */
        corion = token(_token);
        orderCounter = counterStart;
    }
    function () payable {
        /*
            Fallback function for charging the ether balance..
        */
        crediting(msg.sender, msg.value, true, false);
        exchangeEtherBalance += msg.value;
        EPayIn(msg.sender, msg.value, true);
    }
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
        } else if ( typ == confTypes.maxForGasSell ) {
            maxForGasSell = value;
        } else if ( typ == confTypes.tokenAddr ) {
            corion = token(addr);
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
    function nomraliseRate(uint256 rate) internal returns (uint256 nRate) {
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
    function nomraliseUnit(uint256 unit) internal returns (uint256 nUnit) {
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
        token = value * 1e6 / rate;
        assert( token >= 0 );
    }
    function tokenToEtherAtPrice(uint256 value, uint256 rate) internal returns (uint256 eth) {
        /*
            Inner function which shows that how many value of token can be given for hat amount of ether in that rate

            @value     Amount of token
            @rate       Rate
            @eth        Amount of ether.
        */
        eth = value * rate / 1e6;
        assert( eth >= 0 );
    }
    function sell(bool token, uint256 value, bool instant, uint256 rate) external {
        /*
            Offering token or ether for sale in order to open a position with a specified course or in instant mode. 
            It is only possible to offer what is located on the callers balance. 
            The rate and the amount will be normalized in all the cases.
            The rate has to be entered in WEI/0.000001 token resolution.   Examples:
                1e12 wei rate: 1.000000 COR = 1 ether
                1e12 wei rate: 0.100000 COR = 0.1 ether
                5       USD/ETC = 0.2                ETC/COR = 200000000000000000 ETC/COR = 200000000000 wei rate = 1 USD/COR
                7.154   USD/ETC = 0.1397819401733296 ETC/COR = 139781940173329600 ETC/COR = 139781940173 wei rate = 1 USD/COR
                During the ICO
                5       USD/ETC = 0.18               ETC/COR = 180000000000000000 ETC/COR = 180000000000 wei rate = 0.9 USD/COR
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
            _token = nomraliseUnit(value);
            if ( instant ) {
                (_back, _ret) = instantTrade(true, _token, 0, false);
                crediting(msg.sender, _ret, true, true);
                balance[msg.sender].t = safeSub(balance[msg.sender].t, value - _back);
            } else {
                balance[msg.sender].t = safeSub(balance[msg.sender].t, _token);
                _rate = nomraliseRate(rate);
                insertPos(_rate, _token, true);
            }
        } else {
            if ( instant ) {
                (_back, _ret) = instantTrade(true, value, 0, true);
                balance[msg.sender].t = safeSub(balance[msg.sender].t, _ret);
                crediting(msg.sender, value - _back, true, true);
            } else {
                _rate = nomraliseRate(rate);
                _token = etherToTokenAtPrice(value, _rate);
                _token = nomraliseUnit(_token);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balance[msg.sender].e = safeSub(balance[msg.sender].e, _ether);
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
                balance[msg.sender].e = safeSub(balance[msg.sender].e, _ret);
                crediting(msg.sender, value - _back, false, true);
            } else {
                _rate = nomraliseRate(rate);
                _token = etherToTokenAtPrice(value, _rate);
                _token = nomraliseUnit(_token);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balance[msg.sender].e = safeSub(balance[msg.sender].e, _ether);
                insertPos(_rate, _token, false);
            }
        } else {
            if ( instant ) {
                (_back, _ret) = instantTrade(false, value, 0, true);
                balance[msg.sender].e = safeSub(balance[msg.sender].e, value - _back);
                crediting(msg.sender, _ret, false, true);
            } else {
                _rate = nomraliseRate(rate);
                _token = etherToTokenAtPrice(value, _rate);
                _token = nomraliseUnit(_token);
                _ether = tokenToEtherAtPrice(_token, _rate);
                balance[msg.sender].e = safeSub(balance[msg.sender].e, _ether);
                insertPos(_rate, _token, false);
            }
        }
    }
    function getSell(bool token, uint256 value) public constant returns(uint256 spend, uint256 remain) {
        /*
            Simulation: about buying token or ether instantly
            If there is no offer or the resolution is too low that remains
            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
        */
        var (_back, _ret) = instantTrade(true, value, 0, ! token);
        if ( token ) {
            spend = value - _back;
            remain = _ret;
        } else {
            spend = _ret;
            remain = value - _back;
        }
        spend = spend-calcFee(spend);
    }
    function getBuy(bool token, uint256 value) public constant returns(uint256 spend, uint256 remain) {
        /*
            Simulation
            
            @token          Offers token or ether. If it is TRUE then token, if it is FALSE then ether is offered.
            @value          The offered amount.
        */
        var (_back, _ret) = instantTrade(false, value, 0, ! token);
        if ( token ) {
            spend = value - _back;
            remain = _ret;
        } else {
            spend = _ret;
            remain = value - _back;
        }
        spend = spend-calcFee(spend);
    }
    function instantTradeSim(bool _sell, uint256 _amount, bool _ether) internal returns (uint256 left, uint256 ret) {
        /*
            Inner function for the simulation of completing the offer.
            If @ether is true then the @amount should be given in ether.
            If the @sell is true then the @amount has to be sold.
            The @left is the remaining ether. The @ret is the successfully purchased amount of the tokens.
            If @sell is false then @amount has to be purchased.
            The @left is the remaining ether. The @ret is the successfully purchased amount of the tokens.
            
            If the @ether is false then the @amount has to be entered in token.
            If the @sell is true then the @amount has to be sold.
            The @left is the remaining token. The @ret is the successfully purchased amount of the ethers.
            If @sell is false then @amount has to be purchased.
            The @left is the remaining token. The @ret is the successfully sold amount of the ethers.
          
            @_sell          If it is TRUE she/he wants to sell if it is FALSE then wants to buy
            @_amount        amount
            @_ether         Amount based on ether
            @left           Remaining amount
            @ret            value of the offered amount
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
            (_tokenLeft, jumpTo, stop) = instantTradeScanOrdersSim(currentRate, _token, _sell);
            
            if ( _ether ) {
                left -= (_token - _tokenLeft) * currentRate;
                ret += _token - _tokenLeft;
            } else {
                left -= _token - _tokenLeft;
                ret += (_token - _tokenLeft) * currentRate;
            }
            if ( stop || ( jumpTo == 0 ) ) { break; }
            currentRate = jumpTo;
        }
    }
    function instantTradeScanOrdersSim(uint256 currentRate, uint256 _token, bool _sell) internal returns (uint256 left, uint256 jumpTo, bool stop) {
        /*
            Inner function for completing the simulation of the offers which are located in the position.
         
            @currentRate      Rate
            @_token           Amount of the token
            @_sell            If it is a sell or a purchase.
            @left             Amount of the remaining tokens
            @jumpTo           Next rate
            @stop             Should the implementation stop or not? It stops when there is no more offer or in case running out of token.
        */
        uint256 value;
        uint256 deleteThisPos = pos[currentRate].orders.length;
        uint256 orderID;
        left = _token;
        for ( uint256 a=0 ; a<pos[currentRate].orders.length ; a++ ) {
            orderID = pos[currentRate].orders[a];
            if ( ! orders[orderID].valid ) {
                deleteThisPos--;
                continue;
            }
            if ( orders[orderID].amount >= left ) {
                value = left;
                orders[orderID].amount -= left;
                stop = true;
                left = 0;
            } else {
                value = orders[orderID].amount;
                left -= value;
            }
            crediting(orders[orderID].owner, value, ! _sell, true);
            if ( stop ) { break; }
        }
        if ( ! stop ) {
            if ( pos[currentRate].prev > 0 ) {
                jumpTo = pos[currentRate].prev;
            } else {
                stop = true;
            }
        }
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
        orders[orderCounter].orderPos = pos[_rate].orders.push(orderCounter);
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
            crediting(orders[orderID].owner, value, ! _sell, true);
            if ( deleteThisOrder ) {
                deleteThisPos--;
                EOrderDone(orderID, orders[orderID].owner);
                delete orders[orderID];
                delete pos[currentRate].orders[a];
            }
            if ( stop ) { break; }
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
            balance[_to].e = safeAdd(balance[_to].e, amount);
            exchangeEtherBalance = safeSub(exchangeEtherBalance, feeValue);
        } else {
            balance[_to].t = safeAdd(balance[_to].t, amount);
            exchangeTokenBalance = safeSub(exchangeTokenBalance, feeValue);
        }
    }
    function calcFee(uint256 amount) internal returns (uint256 fee) {
        /*
            Inner function to calculate the exchange fee.
            
            @amount  Amount of the input
            @fee     Amount of the fee
        */
        return amount * fee / feeM / 100;
    }
    function payout(uint256 amount, bool eth) external {
        /*
            Launching the payment
            When the token is  allocated the transaction fee will be charged from the requested amount.
            If the payment is asked by the owner of the exchange then the difference of the real contracts balance and the inventory will be set automatically.
            
            @amount         Amount of payment
            @eth            In case it is TRUE then it is requested from the ether account, in case it is FALSE then from the token account.
        */
        var (t, e) = getBalance(msg.sender);
        if ( eth ) {
            balance[msg.sender].e = safeSub(e, amount);
            exchangeEtherBalance = safeSub(exchangeEtherBalance, amount);
            require( msg.sender.send(amount) );
            EPayOut(msg.sender, amount, true);
        } else {
            balance[msg.sender].t = safeSub(t, amount);
            exchangeTokenBalance = safeSub(exchangeTokenBalance, amount);
            var (_success, _fee) = token(corion).getTransactionFee(amount);
            require( _success );
            require( token(corion).transfer(msg.sender, safeSub(amount, _fee)) );
            EPayOut(msg.sender, amount, false);
        }
    }
    function receiveCorionToken(address _from, uint256 _amount, bytes _data) external returns (bool success, uint256 back) {
        /*
            Message about the fact that the contract has received corion token.
            This can only be requested by a token contract and just in case if the contract is not switched off.
            
            @_from      From whom the transaction has come
            @_amount    The amount that has arrived.
            @_data      Extra data
        */
        uint256 _ret;
        require( ! disabled );
        exchangeTokenBalance = safeAdd(exchangeTokenBalance, _amount);
        EPayIn(_from, _amount, false);
        if ( _data.length > 0 ) {
            if ( _data[0] == bytes1(uint8(callbackData.buyForGas)) ) {
                (back, _ret) = instantTrade(true, _amount, 0, false);
                require( _ret < maxForGasSell );
                require( msg.sender.send(_ret) );
            }
        }
        if ( back > 0 ) {
            exchangeTokenBalance = safeSub(exchangeTokenBalance, back);
            EPayOut(_from, back, false);
        }
        return ( true, back );
    }
    function approvedCorionToken(address _from, uint256 _amount, bytes _data) external returns (bool) {
        /*
            Notification that the contract has received corion token as a collection.
            In this case we get the whole amount and credit that on the account of the user.
            
            @_from      Address of the entitled person.
            @_amount    Amount of the transaction
            @_data      extra data
        */
        require( corion.transferFrom(_from, address(this), _amount) );
        exchangeTokenBalance = safeAdd(exchangeTokenBalance, _amount);
        crediting(_from, _amount, false, false);
        EPayIn(_from, _amount, false);
        return true;
    }
    function getBalance(address Address) public constant returns(uint256 Token, uint256 Ether) {
        /*
            Public function for the inquiry of the token and ether amounts
            
            @Address        Address 
            @Token          Balance of the token
            @Ether          Balance of the ether
        */
        return getBalance_(Address);
    }
    function getBalance_(address Address) internal returns(uint256 Token, uint256 Ether) {
        /*
            Inner function for the inquiry of the token and ether amounts
        
            @Address        Address
            @Token          Balance of the token
            @Ether          Balance of the ether
        */
        Token = balance[Address].t;
        Ether = balance[Address].e;
        if ( isOwner() ) {
            uint256 bal = corion.balanceOf(address(this));
            if ( bal >= exchangeTokenBalance ) {
                Token += corion.balanceOf(address(this)) - exchangeTokenBalance;
            }
            Ether += this.balance - exchangeEtherBalance;
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
        deleteOrder(orderID);
        EOrderCancelled(orderID, msg.sender);
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
            crediting(msg.sender, orders[orderID].amount * orders[orderID].rate , false, true);
        }
        deleteOrder(orderID);
        EOrderCancelled(orderID, msg.sender);
    }
    function deleteOrder(uint256 orderID) internal {
        /*
            Inner function to cancell a mandate.
            If there is no valid mandate in the position then the position is going to be cancelled as well.
            
            @orderID        ID of the mandate
        */
        bool delIt = true;
        var _rate = orders[orderID].rate;
        
        delete pos[_rate].orders[orders[orderID].orderPos];
        delete orders[orderID];
        
        for ( uint256 a=0 ; a<pos[_rate].orders.length ; a++ ) {
            if ( pos[_rate].orders[a] != 0 ) {
                delIt = false;
                break;
            }
        }
        if ( delIt ) {
            deletePos(_rate);
        }
    }
    function getOrder(uint256 orderID) public constant returns (address owner, uint256 amount, uint256 rate, bool sell) {
        if ( orders[orderID].valid ) {
            owner = orders[orderID].owner;
            amount = orders[orderID].amount;
            rate = orders[orderID].rate;
            sell = pos[orders[orderID].rate].sell;
        }
    }
    
    event EPayOut(address owner, uint256 amount, bool eth);
    event EPayIn(address owner, uint256 amount, bool eth);
    event ENewOrder(uint256 orderID, address onwer, uint256 rate, uint256 amount);
    event EOrderDone(uint256 orderID, address onwer);
    event EOrderPartial(uint256 orderID, address onwer, uint256 amount);
    event EOrderCancelled(uint256 orderID, address onwer);
}
