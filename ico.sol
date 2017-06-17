pragma solidity ^0.4.11;

import "safeMath.sol";
import "token.sol";
import "premium.sol";
import "moduleHandler.sol";

contract abstractToken {
    function mint(address _owner, uint256 _value) external returns (bool) {}
    function totalSupply() public constant returns (uint256) {}
    function balanceOf(address _owner) public constant returns (uint256 balance) {}
    function closeIco() external returns (bool) {}
}

contract ico is safeMath {
    
    struct icoLevels_ {
        uint256 block;
        uint8 rate;
    }
    struct affiliate_ {
        uint256 weight;
        uint256 paid;
    }
    struct interest_ {
        uint256 amount;
        bool empty;
    }
    struct brought_ {
        uint256 eth;
        uint256 cor;
        uint256 corp;
    }
    
    uint256 private constant oneSegment = 40320;
    
    address private owner;
    address private tokenAddr;
    address private premiumAddr;
    uint256 public startBlock;
    uint256 public icoDelay;
    address private foundationAddress;
    address private icoEtcPriceAddr;
    uint256 public icoExchangeRate;
    uint256 private icoExchangePrevRate;
    uint256 private icoExchangeRateSetBlock;
    uint256 constant icoExchangeRateM = 1e4;
    uint256 private interestOnICO   = 25;
    uint256 private interestOnICOM  = 1e3;
    uint256 private interestBlockDelay = 720;
    uint256 private constant exchangeRateDelay = 125;
    bool public aborted;
    bool public closed;
    icoLevels_[] private icoLevels;
    mapping (address => affiliate_) private affiliate;
    mapping (address => brought_) private brought;
    mapping (address => mapping(uint256 => interest_)) private interestDB;
    uint256 private totalMint;
    uint256 private totalPremiumMint;
    
    function ico(address foundation, address priceSet, uint256 exchangeRate, uint256 _startBlock, address[] genesisAddr, uint256[] genesisValue) {
        /*
            Installation function.
            
            @foundation     The ETC address of the foundation
            @priceSet       The address which will be able to make changes on the rate later on.
            @exchangeRate   The current ETC/USD rate multiplied by 1e4. For example: 2.5 USD/ETC = 25000
            @_startBlock    The height (level) of the beginning of the ICO. If it is 0 then it will be the current array’s height.
            @genesisAddr    Array of Genesis addresses
            @genesisValue   Array of balance of genesis addresses
        */
        foundationAddress = foundation;
        icoExchangeRate = exchangeRate;
        icoExchangePrevRate = icoExchangeRate;
        icoEtcPriceAddr = priceSet;
        owner = msg.sender;
        if ( _startBlock > 0 ) {
            require( _startBlock >= block.number );
            startBlock = _startBlock;
        } else {
            startBlock = block.number;
        }
        icoLevels.push(icoLevels_(startBlock + oneSegment * 4, 103));
        icoLevels.push(icoLevels_(startBlock + oneSegment * 3, 105));
        icoLevels.push(icoLevels_(startBlock + oneSegment * 2, 110));
        icoLevels.push(icoLevels_(startBlock + oneSegment * 1, 115));
        icoLevels.push(icoLevels_(startBlock + oneSegment / 7, 120));
        icoLevels.push(icoLevels_(startBlock, 125));
        icoDelay = startBlock + oneSegment * 5;
        for ( uint256 a=0 ; a<genesisAddr.length ; a++ ) {
            interestDB[genesisAddr[a]][0].amount = genesisValue[a];
        }
    }
    
    function ICObonus() public constant returns(uint256 bonus) {
        /*
            Query of current bonus
            
            @bonus Bonus %
        */
        for ( uint8 a=0 ; a<icoLevels.length ; a++ ) {
            if ( block.number > icoLevels[a].block ) {
                return icoLevels[a].rate - 100;
            }
        }
    }
    
    function setInterestDB(address addr, uint256 balance) external returns(bool success) {
        /*
            Setting interest database. It can be requested by Token contract only.
            A database has to be built in order  that after ICO closed everybody can get their compound interest on their capital accumulated 
            
            @addr       Sender
            @balance    Quantity
            
            @success    Was the process successful or not
        */
        require( msg.sender == tokenAddr );
        uint256 num = (block.number - startBlock) / interestBlockDelay;
        interestDB[addr][num].amount = balance;
        if ( balance == 0 ) { 
            interestDB[addr][num].empty = true;
        }
        return true;
    }
    
    function checkInterest(address addr) public constant returns(uint256 amount) {
        /*
            Query of compound interest
            
            @addr       Address
            
            @amount     Amount of compound interest
        */
        uint256 lastBal;
        uint256 tamount;
        bool empty;
        interest_ memory idb;
        uint256 to = (block.number - startBlock) / interestBlockDelay;
        
        if ( to == 0 || aborted ) { return 0; }
        
        for ( uint256 r=0 ; r < to ; r++ ) {
            if ( r*interestBlockDelay+startBlock >= icoDelay ) { break; }
            idb = interestDB[addr][r];
            if ( idb.amount > 0 ) {
                if ( empty ) {
                    lastBal = idb.amount + amount;
                } else {
                    lastBal = idb.amount;
                }
            }
            if ( idb.empty ) {
                lastBal = 0;
                empty = idb.empty;
            }
            lastBal += tamount;
            tamount = lastBal * interestOnICO / interestOnICOM / 100;
            amount += tamount;
        }
    }
    
    function getInterest(address beneficiary) external {
        /*
            Request of  compound interest. This is deleted  from the database after the ICO closed and following the query of the compound interest.
            
            @beneficiary    Beneficiary who will receive the interest
        */
        uint256 lastBal;
        uint256 tamount;
        uint256 amount;
        bool empty;
        interest_ memory idb;
        address addr = beneficiary;
        uint256 to = (block.number - startBlock) / interestBlockDelay;
        if ( addr == 0x00 ) { addr = msg.sender; }
        
        require( block.number > icoDelay );
        require( ! aborted );
        
        for ( uint256 r=0 ; r < to ; r++ ) {
            if ( r*interestBlockDelay+startBlock >= icoDelay ) { break; }
            idb = interestDB[msg.sender][r];
            if ( idb.amount > 0 ) {
                if ( empty ) {
                    lastBal = idb.amount + amount;
                } else {
                    lastBal = idb.amount;
                }
            }
            if ( idb.empty ) {
                lastBal = 0;
                empty = idb.empty;
            }
            lastBal += tamount;
            tamount = lastBal * interestOnICO / interestOnICOM / 100;
            amount += tamount;
            delete interestDB[msg.sender][r];
        }
        
        require( amount > 0 );
        abstractToken(tokenAddr).mint(addr, amount);
    }
    
    function setICOEthPrice(uint256 value) external {
        /*
            Setting of the ICO ETC USD rates which can only be calle by a pre-defined address. 
            After this function is completed till the call of the next function (which is at least an exchangeRateDelay array) this rate counts.
            With this process avoiding the sudden rate changes.
            
            @value  The ETC/USD rate multiplied by 1e4. For example: 2.5 USD/ETC = 25000
        */
        require( isICO() );
        require( icoEtcPriceAddr == msg.sender );
        require( icoExchangeRateSetBlock < block.number);
        icoExchangeRateSetBlock = block.number + exchangeRateDelay;
        icoExchangeRate = icoExchangePrevRate;
        icoExchangePrevRate = value;
    }
    
    function extendICO() external {
        /*
            Extend the period of the ICO with one segment.
            
            It is only possible during the ICO and only callable by the owner.
        */
        require( isICO() );
        require( msg.sender == owner );
        icoDelay += oneSegment;
    }
    
    function closeICO() external {
        /*
            Closing the ICO.
            It is only possible when the ICO period passed and only by the owner.
            The 96% of the whole amount of the token is generated to the address of the fundation.
            Ethers which are situated in this contract will be sent to the address of the fundation.
        */
        require( msg.sender == owner );
        require( block.number > icoDelay );
        require( ! closed );
        closed = true;
        require( ! aborted );
        require( abstractToken(tokenAddr).mint(foundationAddress, abstractToken(tokenAddr).totalSupply() * 96 / 100) );
        require( abstractToken(premiumAddr).mint(foundationAddress, totalMint / 5000 - totalPremiumMint) );
        require( foundationAddress.send(this.balance) );
        require( abstractToken(tokenAddr).closeIco() );
        require( abstractToken(premiumAddr).closeIco() );
    }
    
    function abortICO() external {
        /*
            Withdrawal of the ICO.            
            It is only possible during the ICO period.
            Only callable by the owner.
            After this process only the receiveFunds function will be available for the customers.
        */
        require( isICO() );
        require( msg.sender == owner );
        aborted = true;
    }
    
    function connectTokens(address _tokenAddr, address _premiumAddr) external {
        /*
            Installation function which joins the two token contracts with this contract.
            Only callable by the owner
            
            @_tokenAddr     Address of the corion token contract.
            @_premiumAddr   Address of the corion premium token contract
        */
        require( msg.sender == owner );
        require( tokenAddr == 0x00 && premiumAddr == 0x00 );
        tokenAddr = _tokenAddr;
        premiumAddr = _premiumAddr;
    }
    
    function receiveFunds() external {
        /*
            Refund the amount which was purchased during the ICO period.
            
            This one is only callable if the ICO is withdrawn.
             In this case the address gets back the 90% of the amount which was spent for token during the ICO period.
        */
        require( aborted );
        require( brought[msg.sender].eth > 0 );
        uint256 val = brought[msg.sender].eth * 90 / 100;
        delete brought[msg.sender];
        require( msg.sender.send(val) );
    }
    
    function () payable {
        /*
            Callback function. Simply calls the buy function as a beneficiary and there is no affilate address.
            If they call the contract without any function then this process will be taken place.
        */
        require( isICO() );
        require( buy(msg.sender, 0x00) );
    }
    
    function buy(address beneficiaryAddress, address affilateAddress) payable returns (bool) {
        /*
            Buying a token
            
            If there is not at least 0.2 ether balance on the beneficiaryAddress then the amount of the ether which was intended for the purchase will be reduced by 0.2 and that will be sent to the address of the beneficiary.
            From the remaining amount calculate the reward with the help of the getIcoReward function.
            Only that affilate address is valid which has some token on it’s account.
            If there is a valid affilate address then calculate and credit the reward as well in the following way:
            With more than 1e12 token contract credit 5% reward based on the calculation that how many tokens did they buy when he was added as an affilate.
                More than 1e11 token: 4%
                More than 1e10 token: 3%
                More than 1e9 token: 2% below 1%
            @beneficiaryAddress     The address of the accredited where the token will be sent.
            @affilateAddress        The address of the person who offered who will get the referral reward. It can not be equal with the beneficiaryAddress.
        */
        require( isICO() );
        if ( beneficiaryAddress == 0x00) { beneficiaryAddress = msg.sender; }
        require( beneficiaryAddress != affilateAddress );
        uint256 _value = msg.value;
        if ( beneficiaryAddress.balance < 0.2 ether ) {
            require( beneficiaryAddress.send(0.2 ether) );
            _value = safeSub(_value, 0.2 ether);
        }
        var reward = getIcoReward(_value);
        require( reward > 0 );
        require( abstractToken(tokenAddr).mint(beneficiaryAddress, reward) );
        brought[beneficiaryAddress].eth = safeAdd(brought[beneficiaryAddress].eth, _value);
        brought[beneficiaryAddress].cor = safeAdd(brought[beneficiaryAddress].cor, reward);
        totalMint = safeAdd(totalMint, reward);
        require( foundationAddress.send(_value * 10 / 100) );
        uint256 extra;
        if ( affilateAddress != 0x00 && ( brought[affilateAddress].eth > 0 || interestDB[affilateAddress][0].amount > 0 ) ) {
            affiliate[affilateAddress].weight = safeAdd(affiliate[affilateAddress].weight, reward);
            extra = affiliate[affilateAddress].weight;
            uint256 rate;
            if (extra >= 1e12) {
                rate = 5;
            } else if (extra >= 1e11) {
                rate = 4;
            } else if (extra >= 1e10) {
                rate = 3;
            } else if (extra >= 1e9) { 
                rate = 2;
            } else {
                rate = 1;
            }
            extra = safeSub(extra * rate / 100, affiliate[affilateAddress].paid);
            affiliate[affilateAddress].paid = safeAdd(affiliate[affilateAddress].paid, extra);
            abstractToken(tokenAddr).mint(affilateAddress, extra);
        }
        checkPremium(beneficiaryAddress);
        EICO(beneficiaryAddress, reward, affilateAddress, extra);
        return true;
    }

    function checkPremium(address _owner) internal {
        /*
            Crediting the premium token
        
            @_owner The corion token balance of this address will be set based on the calculation which shows that how many times can be the amount of the purchased tokens devided by 5000. 
            So after each 5000 token we give 1 premium token.
        */
        uint256 _reward = (brought[_owner].cor / 5e9) - brought[_owner].corp;
        if ( _reward > 0 ) {
            require( abstractToken(premiumAddr).mint(_owner, _reward) );
            brought[_owner].corp = safeAdd(brought[_owner].corp, _reward);
            totalPremiumMint = safeAdd(totalPremiumMint, _reward);
        }
    }
    
    function getIcoReward(uint256 value) public constant returns (uint256 reward) {
        /*
            Expected token volume at token purchase
            
            @value The amount of ether for the purchase
            @reward Amount of the token
                x = (value * 1e6 * USD_ETC_exchange rate / 1e4 / 1e18) * bonus percentage
                2.700000 token = (1e18 * 1e6 * 22500 / 1e4 / 1e18) * 1.20
        */
        reward = value * 1e6 * icoExchangeRate / icoExchangeRateM / 1 ether;
        for ( uint8 a=0 ; a<icoLevels.length ; a++ ) {
            if ( block.number > icoLevels[a].block ) {
                reward = reward * icoLevels[a].rate / 100;
                break;
            }
        }
        if ( reward < 5e6) { return 0; }
    }
    
    function isICO() public constant returns (bool) {
        return startBlock <= block.number && block.number <= icoDelay && ( ! aborted ) && ( ! closed );
    }
    
    event EICO(address indexed Address, uint256 indexed value, address Affilate, uint256 AffilateValue);
}
