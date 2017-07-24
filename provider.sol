pragma solidity ^0.4.11;

import "./module.sol";
import "./moduleHandler.sol";
import "./safeMath.sol";

contract schellingVars {
    /*
        Common enumerations and structures of the Schelling and Database contract.
    */
    enum voterStatus {
        base,
        afterPrepareVote,
        afterSendVoteOk,
        afterSendVoteBad
    }
    struct rounds_s {
        uint256 totalAboveWeight;
        uint256 totalBelowWeight;
        uint256 reward;
        uint256 blockHeight;
        bool voted;
    }
    struct voter_s {
        uint256 roundID;
        bytes32 hash;
        voterStatus status;
        bool voteResult;
        uint256 rewards;
    }
}

contract schellingDB is safeMath, schellingVars {
    /*
        Schelling database contract.
    */
    address public owner;
    function replaceOwner(address newOwner) external returns(bool) {
        require( owner == 0x00 || msg.sender == owner );
        owner = newOwner;
        return true;
    }
    modifier isOwner { require( msg.sender == owner ); _; }
    /*
        Constructor
    */
    function schellingDB() {
        rounds.length = 2;
        rounds[0].blockHeight = block.number;
        currentSchellingRound = 1;
    }
    /*
        Funds
    */
    mapping(address => uint256) public funds;
    function getFunds(address _owner) public constant returns(bool success, uint256 amount) {
        return (true, funds[_owner]);
    }
    function setFunds(address _owner, uint256 _amount) isOwner external returns(bool success) {
        funds[_owner] = _amount;
        return true;
    }
    /*
        Rounds
    */
    rounds_s[] public rounds;
    function getRound(uint256 _id) constant returns(bool success, uint256 totalAboveWeight, uint256 totalBelowWeight, uint256 reward, uint256 blockHeight, bool voted) {
        if ( rounds.length <= _id ) { return (false, 0, 0, 0, 0, false); }
        else { return (true, rounds[_id].totalAboveWeight, rounds[_id].totalBelowWeight, rounds[_id].reward, rounds[_id].blockHeight, rounds[_id].voted); }
    }
    function pushRound(uint256 _totalAboveWeight, uint256 _totalBelowWeight, uint256 _reward, uint256 _blockHeight, bool _voted) isOwner external returns(bool success, uint256 newID) {
        return (true, rounds.push(rounds_s(_totalAboveWeight, _totalBelowWeight, _reward, _blockHeight, _voted)));
    }
    function setRound(uint256 _id, uint256 _totalAboveWeight, uint256 _totalBelowWeight, uint256 _reward, uint256 _blockHeight, bool _voted) isOwner external returns(bool success) {
        rounds[_id] = rounds_s(_totalAboveWeight, _totalBelowWeight, _reward, _blockHeight, _voted);
        return true;
    }
    function getCurrentRound() constant returns(bool success, uint256 roundID) {
        return (true, rounds.length-1);
    }
    /*
        Voter
    */
    mapping(address => voter_s) public voter;
    function getVoter(address _owner) constant returns(bool success, uint256 roundID, bytes32 hash, voterStatus status, bool voteResult, uint256 rewards) {
        roundID         = voter[_owner].roundID;
        hash            = voter[_owner].hash;
        status          = voter[_owner].status;
        voteResult      = voter[_owner].voteResult;
        rewards         = voter[_owner].rewards;
        success         = true;
    }
    function setVoter(address _owner, uint256 _roundID, bytes32 _hash, voterStatus _status, bool _voteResult, uint256 _rewards) isOwner external returns(bool success) {
        voter[_owner] = voter_s(
            _roundID,
            _hash,
            _status,
            _voteResult,
            _rewards
            );
        return true;
    }
    /*
        Schelling Token emission
    */
    mapping(uint256 => uint256) public schellingExpansion;
    function getSchellingExpansion(uint256 _id) constant returns(bool success , uint256 amount) {
        return (true, schellingExpansion[_id]);
    }
    function setSchellingExpansion(uint256 _id, uint256 _expansion) isOwner external returns(bool success) {
        schellingExpansion[_id] = _expansion;
        return true;
    }
    /*
        Current Schelling Round
    */
    uint256 private currentSchellingRound;
    function setCurrentSchellingRound(uint256 _id) isOwner external returns(bool success) {
        currentSchellingRound = _id;
        return true;
    }
    function getCurrentSchellingRound() constant returns(bool success, uint256 roundID) {
        return (true, currentSchellingRound);
    }
}

contract schelling is module, schellingVars, safeMath {
    /*
        Schelling contract
    */
    /*
        module callbacks
    */
    function transferEvent(address from, address to, uint256 value) external onlyForModuleHandler returns (bool success) {
        /*
            Transaction completed. This function can be called only by the ModuleHandler. 
            If this contract is the receiver, the amount will be added to the prize pool of the current round.
            
            @from      From who
            @to        To who
            @value     Amount
            
            @success   Was the transaction succesfull?
        */
        if ( to == address(this) ) {
            var _currentRound = getCurrentRound();
            var _round = getRound(_currentRound);
            _round.reward = safeAdd(_round.reward, value);
            setRound(_currentRound, _round);
        }
        return true;
    }
    function configureModule(announcementType aType, uint256 value, address addr) external onlyForModuleHandler returns(bool success) {
        /*
            Can be called only by the ModuleHandler.
            
            @aType      Sort of configuration
            @value      Value
        */
        require( super.isModuleHandler(msg.sender) );
        if      ( aType == announcementType.schellingRoundBlockDelay )     { roundBlockDelay = value; }
        else if ( aType == announcementType.schellingCheckRounds )         { interestCheckRounds = uint8(value); }
        else if ( aType == announcementType.schellingCheckAboves )         { interestCheckAboves = uint8(value); }
        else if ( aType == announcementType.schellingRate )                { interestRate = value; }
        else { return false; }
        super._configureModule(aType, value, addr);
        return true;
    }
    modifier isReady {
        var (_success, _active) = super.isActive();
        require( _success && _active ); 
        _;
    }
    /*
        Schelling database functions.
    */
    function getFunds(address addr) internal returns (uint256 amount) {
        var (_success, _amount) = db.getFunds(addr);
        require( _success );
        return _amount;
    }
    function setFunds(address addr, uint256 amount) internal {
        require( db.setFunds(addr, amount) );
    }
    function setVoter(address owner, voter_s voter) internal {
        require( db.setVoter(owner, 
            voter.roundID,
            voter.hash,
            voter.status,
            voter.voteResult,
            voter.rewards
            ) );
    }    
    function getVoter(address addr) internal returns (voter_s) {
        var (_success, _roundID, _hash, _status, _voteResult, _rewards) = db.getVoter(addr);
        require( _success );
        return voter_s(_roundID, _hash, _status, _voteResult, _rewards);
    }
    function setRound(uint256 id, rounds_s round) internal {
        require( db.setRound(id, 
            round.totalAboveWeight,
            round.totalBelowWeight,
            round.reward,
            round.blockHeight,
            round.voted
            ) );
    }
    function pushRound(rounds_s round) internal returns (uint256 newID) {
        var (_success, _newID) = db.pushRound( 
            round.totalAboveWeight,
            round.totalBelowWeight,
            round.reward,
            round.blockHeight,
            round.voted
            );
        require( _success );
        return _newID;
    }
    function getRound(uint256 id) internal returns (rounds_s) {
        var (_success, _totalAboveWeight, _totalBelowWeight, _reward, _blockHeight, _voted) = db.getRound(id);
        require( _success );
        return rounds_s(_totalAboveWeight, _totalBelowWeight, _reward, _blockHeight, _voted);
    }
    function getCurrentRound() internal returns (uint256 roundID) {
        var (_success, _roundID) = db.getCurrentRound();
        require( _success );
        return _roundID;
    }
    function setCurrentSchellingRound(uint256 id) internal {
        require( db.setCurrentSchellingRound(id) );
    }
    function getCurrentSchellingRound() internal returns(uint256 roundID) {
        var (_success, _roundID) = db.getCurrentSchellingRound();
        require( _success );
        return _roundID;
    }
    function setSchellingExpansion(uint256 id, uint256 amount) internal {
        require( db.setSchellingExpansion(id, amount) );
    }
    function getSchellingExpansion(uint256 id) internal returns(uint256 amount) {
        var (_success, _amount) = db.getSchellingExpansion(id);
        require( _success );
        return _amount;
    }
    /*
        Schelling module
    */
    uint256 public roundBlockDelay     = 720;
    uint8   public interestCheckRounds = 7;
    uint8   public interestCheckAboves = 4;
    uint256 public interestRate        = 300;
    uint256 public interestRateM       = 1e3;

    bytes1 public aboveChar = 0x31;
    bytes1 public belowChar = 0x30;
    schellingDB public db;
    
    function schelling(address _moduleHandler, address _db, bool _forReplace) {
        /*
            Installation function.
            
            @_moduleHandler         Address of ModuleHandler.
            @_db                    Address of the database.
            @_forReplace            This address will be replaced with the old one or not.
            @_icoExpansionAddress   This address can turn schelling runds during ICO.
        */
        db = schellingDB(_db);
        super.registerModuleHandler(_moduleHandler);
        if ( ! _forReplace ) {
            require( db.replaceOwner(this) );
        }
    }
    function prepareVote(bytes32 votehash, uint256 roundID) isReady noContract external {
        /*
            Initializing manual vote.
            Only the hash of vote will be sent. (Envelope sending). 
            The address must be in default state, that is there are no vote in progress. 
            Votes can be sent only on the actually Schelling round.
            
            @votehash               Hash of the vote
            @roundID                Number of Schelling round
        */
        nextRound();
        
        var _currentRound = getCurrentRound();
        var _round = getRound(_currentRound);
        //voter_s memory _voter;
        //uint256 _funds;
        
        require( roundID == _currentRound );
        
        var _voter = getVoter(msg.sender);
        var _funds = getFunds(msg.sender);
        
        require( _funds > 0 );
        require( _voter.status == voterStatus.base );
        _voter.roundID = _currentRound;
        _voter.hash = votehash;
        _voter.status = voterStatus.afterPrepareVote;
        
        setVoter(msg.sender, _voter);
        _round.voted = true;
        
        setRound(_currentRound, _round);
    }
    function sendVote(string vote) isReady noContract external {
        /*
            Check vote (Envelope opening)
            Only the sent “envelopes” can be opened.
            Envelope opening only in the next Schelling round.
            If the vote invalid, the deposit will be lost.
            If the “envelope” was opened later than 1,5 Schelling round, the vote is automatically invalid, and deposit can be lost.
            Lost deposits will be 100% burned.
            
            @vote      Hash of the content of the vote.
        */
        nextRound();
        
        var _currentRound = getCurrentRound();
        //rounds_s memory _round;
        //voter_s memory _voter;
        //uint256 _funds;
        
        bool _lostEverything;
        var _voter = getVoter(msg.sender);
        var _round = getRound(_voter.roundID);
        var _funds = getFunds(msg.sender);
        
        require( _voter.status == voterStatus.afterPrepareVote );
        require( _voter.roundID < _currentRound );
        if ( sha3(vote) == _voter.hash ) {
            delete _voter.hash;
            if (_round.blockHeight+roundBlockDelay/2 >= block.number) {
                if ( bytes(vote)[0] == aboveChar ) {
                    _voter.status = voterStatus.afterSendVoteOk;
                    _round.totalAboveWeight += _funds;
                    _voter.voteResult = true;
                } else if ( bytes(vote)[0] == belowChar ) {
                    _voter.status = voterStatus.afterSendVoteOk;
                    _round.totalBelowWeight += _funds;
                } else { _lostEverything = true; }
            } else {
                _voter.status = voterStatus.afterSendVoteBad;
            }
        } else { _lostEverything = true; }
        if ( _lostEverything ) {
            require( moduleHandler(moduleHandlerAddress).burn(address(this), _funds) );
            delete _funds;
            delete _voter.status;
        }
        
        setVoter(msg.sender, _voter);
        setRound(_voter.roundID, _round);
        setFunds(msg.sender, _funds);
    }
    function checkVote() isReady noContract external {
        /*
            Checking votes.
            Vote checking only after the envelope opening Schelling round.
            Deposit will be lost, if the vote wrong, or invalid.
            The right votes take share of deposits.
        */
        nextRound();
        
        //rounds_s memory _round;
        //voter_s memory _voter;
        //uint256 _funds;
        
        var _voter = getVoter(msg.sender);
        var _round = getRound(_voter.roundID);
        var _funds = getFunds(msg.sender);
        
        require( _voter.status == voterStatus.afterSendVoteOk || _voter.status == voterStatus.afterSendVoteBad );
        if ( _round.blockHeight+roundBlockDelay/2 <= block.number ) {
            if ( isWinner(_round, _voter.voteResult) && _voter.status == voterStatus.afterSendVoteOk ) {
                _voter.rewards += _funds * _round.reward / getRoundWeight(_round.totalAboveWeight, _round.totalBelowWeight);
            } else {
                require( moduleHandler(moduleHandlerAddress).burn(address(this), _funds) );
                delete _funds;
            }
            delete _voter.status;
            delete _voter.roundID;
        } else { throw; }
        
        setVoter(msg.sender, _voter);
        setFunds(msg.sender, _funds);
    }
    function getRewards(address beneficiary) isReady noContract external {
        /*
            Redeem of prize.
            The prizes will be collected here, and with this function can be transferred to the account of the user.
            Optionally there can be an address of a beneficiary added, which address the prize will be sent to. Without beneficiary, the owner is the default address.
            Prize will be sent from the Schelling address without any transaction fee.
            
            @beneficiary        Address of the beneficiary
        */
        var _voter = getVoter(msg.sender);
        
        address _beneficiary = msg.sender;
        if (beneficiary != 0x0) { _beneficiary = beneficiary; }
        uint256 _reward;
        require( _voter.rewards > 0 );
        require( _voter.status == voterStatus.base );
        _reward = _voter.rewards;
        delete _voter.rewards;
        require( moduleHandler(moduleHandlerAddress).transfer(address(this), _beneficiary, _reward, false) );
            
        setVoter(msg.sender, _voter);
    }
    function checkReward() public constant returns (uint256 reward) {
        /*
            Withdraw of the amount of the prize (it’s only information).
            
            @reward         Prize
        */
        var _voter = getVoter(msg.sender);
        return _voter.rewards;
    }
    function nextRound() internal returns (bool success) {
        /*
            Inside function, checks the time of the Schelling round and if its needed, creates a new Schelling round.
        */
        var _currentRound = getCurrentRound();
        var _round = getRound(_currentRound);
        rounds_s memory _newRound;
        rounds_s memory _prevRound;
        var currentSchellingRound = getCurrentSchellingRound();
        uint256 _aboves;
        uint256 _expansion;
        
        if ( _round.blockHeight+roundBlockDelay > block.number) { return false; }
        _newRound.blockHeight = block.number;
        if ( ! _round.voted ) {
            _newRound.reward = _round.reward;
        }
        
        for ( uint256 a=_currentRound ; a>=_currentRound-interestCheckRounds ; a-- ) {
            if (a == 0) { break; }
            _prevRound = getRound(a);
            if ( _prevRound.totalAboveWeight > _prevRound.totalBelowWeight ) { _aboves++; }
        }
        if ( _aboves >= interestCheckAboves ) {
            _expansion = getTotalSupply() * interestRate / interestRateM / 100;
        }
        
        currentSchellingRound++;
        
        pushRound(_newRound);
        setSchellingExpansion(currentSchellingRound, _expansion);
        require( moduleHandler(moduleHandlerAddress).broadcastSchellingRound(currentSchellingRound, _expansion) );
        return true;
    }
    function addFunds(uint256 amount) isReady noContract external {
        /*
            Deposit taking.
            Every participant entry with his own deposit.
            In case of wrong vote only this amount of deposit will be burn.
            The deposit will be sent to the address of Schelling, charged with transaction fee.
            
            @amount          Amount of deposit.
        */
        var _voter = getVoter(msg.sender);
        var _funds = getFunds(msg.sender);
        
        var (_success, _isICO) = moduleHandler(moduleHandlerAddress).isICO();
        require( _success && _isICO );
        require( _voter.status == voterStatus.base );
        require( amount > 0 );
        require( moduleHandler(moduleHandlerAddress).transfer(msg.sender, address(this), amount, true) );
        _funds += amount;
        
        setFunds(msg.sender, _funds);
        setVoter(msg.sender, _voter);
    }
    function getFunds() isReady noContract external {
        /*
            Deposit withdrawn.
            If the deposit isn’t lost, it can be withdrawn.
            By withdrawn, the deposit will be sent from Schelling address to the users address, charged with transaction fee..
        */
        var _voter = getVoter(msg.sender);
        var _funds = getFunds(msg.sender);
        
        require( _funds > 0 );
        require( _voter.status == voterStatus.base );
        setFunds(msg.sender, 0);
        setVoter(msg.sender, _voter);
        
        require( moduleHandler(moduleHandlerAddress).transfer(address(this), msg.sender, _funds, true) );
    }
    function getCurrentSchellingRoundID() public constant returns (uint256 roundID) {
        /*
            Number of actual Schelling round.
            
            @roundID        Schelling round.
        */
        return getCurrentSchellingRound();
    }
    function getSchellingRound(uint256 id) public constant returns (uint256 expansion) {
        /*
            Amount of token emission of the Schelling round.
            
            @id             Number of Schelling round
            @expansion      Amount of token emission
        */
        return getSchellingExpansion(id);
    }
    function getRoundWeight(uint256 aboveW, uint256 belowW) internal returns (uint256 weight) {
        /*
            Inside function for calculating the weights of the votes.
            
            @aboveW     Weight of votes: ABOVE
            @belowW     Weight of votes: BELOW
            @weight     Calculatet weight
        */
        if ( aboveW == belowW ) {
            return aboveW + belowW;
        } else if ( aboveW > belowW ) {
            return aboveW;
        } else if ( aboveW < belowW) {
            return belowW;
        }
    }
    function isWinner(rounds_s round, bool aboveVote) internal returns (bool wins) {
        /*
            Inside function for calculating the result of the game.
            
            @round      Structure of Schelling round.
            @aboveVote  Is the vote = ABOVE or not
            @wins       Result
        */
        if ( round.totalAboveWeight == round.totalBelowWeight ||
            ( round.totalAboveWeight > round.totalBelowWeight && aboveVote ) ) {
            return true;
        }
        return false;
    }
    
    function getTotalSupply() internal returns (uint256 amount) {
        /*
            Inside function for querying the whole amount of the tokens.
            
            @amount     Whole token amount
        */
        var (_success, _amount) = moduleHandler(moduleHandlerAddress).totalSupply();
        require( _success );
        return _amount;
    }
    
    function getTokenBalance(address addr) internal returns (uint256 balance) {
        /*
            Inner function in order to poll the token balance of the address.
            
            @addr       Address
            
            @balance    Balance of the address.
        */
        var (_success, _balance) = moduleHandler(moduleHandlerAddress).balanceOf(addr);
        require( _success );
        return _balance;
    }
    
    modifier noContract {
        /*
            Contract can’t call this function, only a natural address.
        */
        require( msg.sender == tx.origin ); _;
    }
}
