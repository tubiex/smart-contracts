// (C) block.one all rights reserved

pragma solidity ^0.5.2;

import "../math/SafeMath.sol";
import "../ERC20/IERC20.sol";
import "../access/roles/FundkeeperRole.sol";
import "./ICrowdsale.sol";
import "../access/roles/ManagerRole.sol";
import "../access/roles/RecoverRole.sol";
import "../access/roles/WhitelisterRole.sol";

contract TBNCrowdSale is ICrowdsale, ManagerRole, RecoverRole, FundkeeperRole, WhitelisterRole {
    using SafeMath for uint256;
    
    /*
     *  Storage
     */
    struct Interval {
        uint256 reservePrice;  // the reservePrice in ETH for this interval @ 18 decimals of precision
        uint256 ETHReserveAmount;   // the reserve amount of ETH for this interval @ 18 decimals of precision
    }

    mapping (uint256 => Interval) public intervals;

    IERC20 private _erc20;                          // the TBN ERC20 token deployment
    
    uint256 private _guaranteedIntervals;           // number of guaranteed intervals before the sale can end early (set as 47)
    uint256 private _numberOfIntervals;             // number of intervals in the sale (188)
    bytes32 private _hiddenCap;                     // a hash of <the hidden hard cap(in WEI)>+<a secret number> to be revealed if/when the hard cap is reached - does not rebase so choose wisely

    uint256 private _reserveFloor;                  // the minimum possible reserve price in USD @ 18 decimal precision (set @ 0.0975 USD)
    uint256 private _reserveCeiling;                // the maximum possible reserve price in USD @ 18 decimal precision (set @ 0.15 USD)
    uint256 private _reserveStep;                   // the base amount to step down the price if reserve is not met @ 18 decimals of precision (0.15-.0975/188 = .0000279255)

    uint256 private _crowdsaleAllocation;           // total amount of TBN allocated to the crowdsale contract for distribution
    uint256 private _distributedTotal;              // total amount of TBN to be distributed (this will be fixed at CrowdsaleEnded, running total until then)
    uint256 private _totalContributions;            // total amount of ETH contributed for the whole sale period

    uint256 private WEI_FACTOR = 10**18;            // ETH base in WEI

    uint256 private _rebaseNewPrice;                // holds the rebase ETH price until rebasing occurs in the next active interval @ decimal 18
    uint256 private _rebased;                       // the interval setRebase was called, _rebase() will occur in the next interval
    
    uint256 private _lastAdjustedInterval;          // the most recent reserve adjusted interval

    bool private _recoverySafety;                           // a flag to be sure it is safe to recover TBN tokens

    uint256 public startBlock;                      // block number of the start of interval 0
    uint256 public endBlock;                        // block number of the last block of the last interval
    uint256 public endInterval;                     // the interval number when the Crowdfund stage was ended
    uint256 public INTERVAL_BLOCKS = 5520;          // number of block per interval - 23 hours @ 15 sec per block

    uint256 public ETHPrice;                        // ETH price in USD with 18 decimal precision for calculating reserve pricing
    uint256 public tokensPerInterval;               // number of tokens available for distribution each interval
    
    mapping (uint256 => uint256) public intervalTotals; // total ETH contributed per interval

    mapping (uint256 => mapping (address => uint256)) public participationAmount;
    mapping (uint256 => mapping (address => bool)) public claimed;
    mapping (address => bool) public whitelist;
    
    Stages public stages;

    /*
     *  Enums
     */
    enum Stages {
        CrowdsaleDeployed,
        Crowdsale,
        CrowdsaleEnded
    }

    /*
     *  Modifiers
     */
    modifier atStage(Stages _stage) {
        require(stages == _stage, "functionality not allowed at current stage");
        _;
    }

    modifier onlyWhitelisted(address _participant) {
        require(whitelist[_participant] == true, "account is not white listed");
        _;
    }

    // update reserve adjustment and execute rebasing if ETH price was rebased last interval
    // also checks for end of sale endBlock condition and accounts for if the sale has been ended early or via reaching the endblock (then does final adjust and distribution calculations)
    modifier update() {
        uint256 interval = getInterval(block.number);
        if(endInterval == 0) {
            if (block.number > endBlock) { // check for sale end, endBlock condition
                interval = _numberOfIntervals.add(1);
                if (uint(stages) < 2) {
                    stages = Stages.CrowdsaleEnded;
                    endInterval = _numberOfIntervals.add(1);
                }
            }
        } else {
            interval = endInterval;
        }

        if(_lastAdjustedInterval != interval){ // check that the current interval is reserve adjusted
            for (uint i = _lastAdjustedInterval.add(1); i <= interval; i++) { // if current not adjusted, catch up adjustment until current interval
                _adjustReserve(i); // adjust the dynamic reserve price
                _addDistribution(i); // sum of total sale distribution
            }
            if(endInterval != 0 && _recoverySafety != true) { // need to ensure that update() has been called at least once after endInterval has been set (to guarantee the accuracy of _distributedTotal)
                _recoverySafety = true;
            }
            _lastAdjustedInterval = interval;
        }

        // we can rebase only if reserve ETH ajdustment is current (done above)
        if( interval > 1 && _rebased == interval.sub(1)){ // check if the ETH price was set for rebasing last interval
            _rebase(_rebaseNewPrice);
            _;
        } else {
            _;
        }
    }

    /**
    * @dev Constructor
    * @param token TBNERC20 token contract
    * @param numberOfIntervals the total number of 23 hr intervals run the crowdsale (set as 188)
    * @param guaranteedIntervals the number of guaranteed intervals before the sale can end eraly (set as 47)
    * @param hiddenCap a keccak256 hash string of the hardcap number of ETH (in WEI) and a secret number to be revealed if this hidden hard cap is reached
    */
    constructor(
        IERC20 token,
        uint256 numberOfIntervals,
        uint256 guaranteedIntervals,
        bytes32 hiddenCap    
    ) public {
        require(address(token) != address(0x0), "token address cannot be 0x0");
        require(guaranteedIntervals > 0, "guaranteedIntervals must be larger than zero");
        require(numberOfIntervals > guaranteedIntervals, "numberOfIntervals must be larger than guaranteedIntervals");

        _erc20 = token;
        _numberOfIntervals = numberOfIntervals;
        _guaranteedIntervals = guaranteedIntervals;
        _hiddenCap = hiddenCap;

        stages = Stages.CrowdsaleDeployed;
    }

    /**
    * @dev Fallback auto participates with any ETH payment, with guarantee set to 0 (this means no TBN per ETH restrictions)
    */
    function () external payable {
        participate(0);
    }

    /**
    * @dev Safety function for recovering missent ERC20 tokens (and recovering the un-distributed allocation after CrowdsaleEnded)
    * @param token address of the ERC20 contract to recover
    */
    function recoverTokens(IERC20 token) 
        external 
        onlyRecoverer 
        returns (bool) 
    {
        uint256 recover;
        if (token == _erc20){
            require(uint(stages) >= 2, "if recovering TBN, must have progressed to CrowdsaleEnded");
            require(_recoverySafety, "update() needs to run at least once since the sale has ended");
            recover = token.balanceOf(address(this)).sub(_distributedTotal);
        } else {
            recover = token.balanceOf(address(this));
        }

        token.transfer(msg.sender, recover);
        emit TokensRecovered(token, recover);
        return true;
    }

   /*
     *  Getters
     */


    /**
    * @dev Gets the interval based on the blockNumber given
    * @param blockNumber The block.number to check the interval of
    * @return An uint256 representing the interval number
    */
    function getInterval(uint256 blockNumber) public view returns (uint256) {
        return _intervalFor(blockNumber);
    }

    /**
    * @dev Gets the TBN ERC20 deployment linked to this contract
    * @return The address of the deployed TBN ERC20 contract
    */
    function getERC20() public view returns (address) {
        return address(_erc20);
    }

    /**
    * @dev Gets the current total number of TBN distributed based on the contributions minus any tokens already claimed
    * @return The running total of distributed TBN
    */
    function getDistributedTotal() public view returns (uint256) {
        return _distributedTotal;
    }

    function currentStage() public view returns(uint256) {
        return uint256(stages);
    }

    /**
    * @dev public function for anyone to participate in a given interval
    * @param guarantee The minimum number of TBN per ETH contribution ratio the participant is willing to make this call at
    *    Note: a non-zero guarantee allows the participant to set a guaranteed minimum number of TBN per ETH for participation
    *    e.g., guarantee = 1000, guarantees that if the current rewarded TBN per 1 ETH is less than 1000, the call will fail
    * @return True if successful
    */
    function participate(uint256 guarantee) 
        public 
        payable 
        atStage(Stages.Crowdsale) 
        update()
        onlyWhitelisted(msg.sender) 
        returns (bool) 
    {
        uint256 interval = getInterval(block.number);
        require(interval <= _numberOfIntervals, "interval of current block number must be less than or equal to the number of intervals");
        require(msg.value >= .01 ether, "minimum participation amount is .01 ETH");
        
        if (guarantee != 0) {
            uint256 TBNperWEI;
            if(intervalTotals[interval] >= intervals[interval].ETHReserveAmount) {
                TBNperWEI = (tokensPerInterval.mul(WEI_FACTOR)).div(intervalTotals[interval]); // WEI_FACTOR for 18 decimal precision
            } else {
                TBNperWEI = (WEI_FACTOR.mul(WEI_FACTOR)).div(intervals[interval].reservePrice); // 1st WEI_FACTOR represents 1 ETH, second WEI_FACTOR is for 18 decimal precision
            }
            require(TBNperWEI >= guarantee, "the number TBN per ETH is less than your expected guaranteed number of TBN");
        }

        participationAmount[interval][msg.sender] = participationAmount[interval][msg.sender].add(msg.value);
        intervalTotals[interval] = intervalTotals[interval].add(msg.value);
        _totalContributions = _totalContributions.add(msg.value);

        emit Participated(interval, msg.sender, msg.value);

        return true;
    }


    /**
    * @dev public function for anyone to claim TBN from past interval participations
    * @param interval The interval to claim from
    */
    function claim(uint256 interval) 
        public 
        update()
    {
        require(uint(stages) >= 1, "must be in the Crowdsale or later stage to claim");
        require(getInterval(block.number) > interval, "the given interval must be less than the current interval");
        
        if (claimed[interval][msg.sender] || intervalTotals[interval] == 0 || participationAmount[interval][msg.sender] == 0) {
            return;
        }

        uint256 intervalClaim;
        uint256 contributorProportion = participationAmount[interval][msg.sender].mul(WEI_FACTOR).div(intervalTotals[interval]);
        uint256 reserveMultiplier;
        if (intervalTotals[interval] >= intervals[interval].ETHReserveAmount){
            reserveMultiplier = WEI_FACTOR;
        } else {
            reserveMultiplier = intervalTotals[interval].mul(WEI_FACTOR).div(intervals[interval].ETHReserveAmount);
        }

        intervalClaim = tokensPerInterval.mul(contributorProportion).mul(reserveMultiplier).div(10**36);
        claimed[interval][msg.sender] = true;
        if(intervalClaim == 0) {
            return;
        }
        _distributedTotal = _distributedTotal.sub(intervalClaim);
        emit Claimed(interval, msg.sender, intervalClaim);
        
        _erc20.transfer(msg.sender, intervalClaim);
    }

    /**
    * @dev public function to claim unclaimed TBN for specific intervals
    * @param claimIntervals an array of interval to claim from
    * @return True is successful
    */
    function claimInterval(uint256[] memory claimIntervals) 
        public
        returns (bool) 
    {
        for (uint i = 0; i < claimIntervals.length; i++) {
            claim(claimIntervals[i]);
        }
        return true;
    }

    /**
    * @dev public function to claim all interval unclaimed so far
    * @return True is successful
    */
    function claimAll() 
        public
        returns (bool) 
    {
        for (uint i = 0; i < getInterval(block.number); i++) {
            claim(i);
        }
        return true;
    }

    ///  @dev Function to whitelist participants during the crowdsale
    ///  @param participants Array of addresses to whitelist
    function addToWhitelist(address[] calldata participants) external onlyWhitelister {
        for (uint32 i = 0; i < participants.length; i++) {
            if(participants[i] != address(0) && whitelist[participants[i]] == false){
                whitelist[participants[i]] = true;
            }
        }
    }

    ///  @dev Function to remove the whitelististed participants
    ///  @param nonparticipants is an array of accounts to remove form the whitelist
    function removeFromWhitelist(address[] calldata nonparticipants) external onlyWhitelister {
        for (uint32 i = 0; i < nonparticipants.length; i++) {
            if(nonparticipants[i] != address(0) && whitelist[nonparticipants[i]] == true){
                whitelist[nonparticipants[i]] = false;
            }
        }
    }

    /**
    * @dev Crowdsale Manager Role can assign the crowdsale token allocation to this contract. Note: TBN token fundkeeper must give this contract an allowance before calling initialize
    *      Also sets the initial ETH Price, reserve price floor, and reserve price ceiling; all in USD with 18 decimal precision
    * @param newETHPrice the intital price of ETH in USD
    * @param reserveFloor the minimum reserve price per TBN (in USD)
    * @param reserveCeiling the maximum reserve price per TBN (in USD)
    * @param crowdsaleAllocation the amount of tokens assigned to this contract for Crowdsale distribution upon initialization
    * @return True if successful
    */
    function initialize(
        uint256 newETHPrice,
        uint256 reserveFloor,
        uint256 reserveStart, 
        uint256 reserveCeiling,
        uint256 crowdsaleAllocation
    ) 
        external 
        onlyManager 
        atStage(Stages.CrowdsaleDeployed) 
        returns (bool) 
    {
        require(newETHPrice > reserveCeiling, "ETH basis price must be greater than the reserve ceiling"); 
        require(reserveFloor > 0, "the reserve floor must be greater than 0");
        require(reserveCeiling > reserveFloor.add(_numberOfIntervals), "the reserve ceiling must be _numberOfIntervals WEI greater than the reserve floor");
        require(reserveStart >= reserveFloor, "the reserve start price must be greater than the reserve floor");
        require(reserveStart <= reserveCeiling, "the reserve start price must be less than the reserve ceiling");
        require(crowdsaleAllocation > 0, "crowdsale allocation must be assigned a number greater than 0");
        
        address fundkeeper = FundkeeperRole(address(_erc20)).fundkeeper();
        require(_erc20.allowance(address(fundkeeper), address(this)) == crowdsaleAllocation, "crowdsale allocation must be equal to the amount of tokens approved for this contract");

        // set intital variables
        ETHPrice = newETHPrice;
        _rebaseNewPrice = ETHPrice;
        _crowdsaleAllocation = crowdsaleAllocation;
        _reserveFloor = reserveFloor;
        _reserveCeiling = reserveCeiling;
        _reserveStep = (_reserveCeiling.sub(_reserveFloor)).div(_numberOfIntervals);
        startBlock = block.number;
        
        tokensPerInterval = crowdsaleAllocation.div(_numberOfIntervals);

        // calc initial intervalReserve
        uint256 interval = getInterval(block.number);
        intervals[interval].reservePrice = (reserveStart.mul(WEI_FACTOR)).div(ETHPrice);
        intervals[interval].ETHReserveAmount = tokensPerInterval.mul(intervals[interval].reservePrice).div(WEI_FACTOR);

        // create calculated initial variables
        endBlock = startBlock.add(INTERVAL_BLOCKS.mul(_numberOfIntervals));
       
        stages = Stages.Crowdsale;

        // place crowdsale allocation in this contract
        _erc20.transferFrom(fundkeeper, address(this), crowdsaleAllocation);
        return true;
    }

    /**
    * @dev Crowdsale Manager Role can rebase the ETH price to accurately reflect the open market
    *      Note: this rebase will occur in this following interval from when this function is called and only on rebase can occur in an interval
    *            Rebasing can occur as many times as necessary in the previous interval before updating occurs 
    * @param newETHPrice the intital price of ETH in USD
    * @return True if successful
    */
    function setRebase(uint256 newETHPrice) 
        external 
        onlyManager 
        atStage(Stages.Crowdsale) 
        returns (bool) 
    {
        require(newETHPrice > _reserveCeiling, "ETH price cannot be set smaller than the reserve ceiling");
        uint256 interval = getInterval(block.number);
        require(block.number <= endBlock, "cannot rebase after the crowdsale period is over");
        require(interval > 0, "cannot rebase in the initial interval");
        _rebaseNewPrice = newETHPrice;
        _rebased = interval;
        return true;
    }

    /**
    * @dev Crowdsale Manager Role can reveal the hidden hard cap (and end sale early - but only enacted after 45 days as per our policy)
    * @param cap the hidden hard cap - number of ETH (in WEI)
    * @param secret an additional secret uint256 to prevent people from guessing the hidden cap
    * @return True if successful
    */
    function revealCap(uint256 cap, uint256 secret) 
        external 
        onlyManager 
        atStage(Stages.Crowdsale) 
        returns (bool) 
    {
        require(block.number >= startBlock.add(INTERVAL_BLOCKS.mul(_guaranteedIntervals)), "cannot reveal hidden cap until after the guaranteed period");
        uint256 interval = getInterval(block.number);
        bytes32 hashed = keccak256(abi.encode(cap, secret));
        if (hashed == _hiddenCap) {
            require(cap <= _totalContributions, "revealed cap must be under the total contribution");
            stages = Stages.CrowdsaleEnded;
            endInterval = interval;
            return true;
        }
        return false;
    }

    /**
    * @dev Crowdsale Fundkeeper Role can collect ETH any number of times
    * @return True if successful
    */
    function collect() 
        external 
        onlyFundkeeper 
        returns (bool) 
    {
        emit Collected(msg.sender, address(this).balance);
        msg.sender.transfer(address(this).balance);
    }

    /**
    * @dev Crowdsale Manager Role can rebase the ETH price to accurately reflect the open market (internal function)
    * @param newETHPrice the intital price of ETH in USD
    */
    function _rebase(uint256 newETHPrice) 
        internal 
        atStage(Stages.Crowdsale) 
    {
        uint256 interval = getInterval(block.number);
        
        // get old price
        uint256 oldPrice = (intervals[interval].reservePrice.mul(ETHPrice)).div(WEI_FACTOR);
        
        // new ETH base price
        ETHPrice = newETHPrice;

        // recalc ETH reserve Price
        intervals[interval].reservePrice = (oldPrice.mul(WEI_FACTOR)).div(ETHPrice);
        // recalc ETH reserve Amount
        intervals[interval].ETHReserveAmount = tokensPerInterval.mul(intervals[interval].reservePrice).div(WEI_FACTOR);

        // reset _rebaseNewPrice to 0
        _rebaseNewPrice = 0;
        // reset _rebased to 0
        _rebased = 0;

        emit Rebased(
            ETHPrice,
            intervals[interval].reservePrice,
            intervals[interval].ETHReserveAmount
        );
    } 

    /**
    * @dev Gets the interval based on the blockNumber given (internal function)
    *      Note: Each window is 23 hours long so that end-of-window rotates around the clock for all timezones
    * @param blockNumber The block.number to check the interval of
    * @return An uint256 representing the interval number
    */
    function _intervalFor(uint256 blockNumber) 
        internal 
        view 
        returns (uint256) 
    {
        uint256 interval;
        if(blockNumber <= startBlock) {
            interval = 0;
        }else if(blockNumber <= endBlock) {
            interval = blockNumber.sub(startBlock).div(INTERVAL_BLOCKS);
        } else {
            interval = ((endBlock.sub(startBlock)).div(INTERVAL_BLOCKS)).add(1);
        }

        return interval;
    }

    /**
    * @dev Adjusts the dynamic reserve price and therefore the new expected reserve amount (both in ETH) for this interval depending on the contribution results of the previous interval (internal function)
    * @param interval the interval to do the adjustment for
    */
    function _adjustReserve(uint256 interval) internal {
        require(interval > 0, "cannot adjust the initial interval reserve");
        // get last reserve info
        uint256 lastReserveAmount = intervals[interval.sub(1)].ETHReserveAmount; // reserve amount of ETH expected last round
        uint256 lastUSDPrice = (intervals[interval.sub(1)].reservePrice.mul(ETHPrice)).div(WEI_FACTOR); // the calculated price per TBN in USD from the last round

        uint256 ratio; // % in 18 decimal precision to see what ratio the contribution and target reserve are apart
        uint256 multiplier; //  a mltiplier to increase the number of steps to adjust depending on the size of the ratio

        uint256 newUSDPrice;

        // adjust reservePrice accordingly, the further away from the target reserve contribution was, the more steps the reerve price will be adjusted
        if (intervalTotals[interval.sub(1)] > lastReserveAmount) { // check if last reserve was exceeded
            ratio = (lastReserveAmount.mul(WEI_FACTOR)).div(intervalTotals[interval.sub(1)]);
            if(ratio <= 33*10**16){ // if lastReserveAmount is 33% or less of the last contributed amount step up * 3
                multiplier = 3;
            } else if (ratio <= 66*10**16){ // if lastReserveAmount is between 33%+ or 66% of the last contributed amount step up * 2
                multiplier = 2;
            } else { // if lastReserveAmount is larger than 66%+ upto 100% of the contributed amount
                multiplier = 1;
            }

            newUSDPrice = lastUSDPrice.add(_reserveStep.mul(multiplier)); // the new USD price will be the last interval USD price plus the reserve step times the multiplier
            
            if (newUSDPrice >= _reserveCeiling) { // new price is greater than or equal to the ceiling reserve
                intervals[interval].reservePrice = (_reserveCeiling.mul(WEI_FACTOR)).div(ETHPrice); // set to ceiling reserve (capped)
            } else { // new price is less than the ceiling reserve
                intervals[interval].reservePrice = (newUSDPrice.mul(WEI_FACTOR)).div(ETHPrice); // set new reserve price
            }

        } else if (intervalTotals[interval.sub(1)] < lastReserveAmount) { // last reserve was not met
            ratio = (intervalTotals[interval.sub(1)].mul(WEI_FACTOR)).div(lastReserveAmount);
            if(ratio <= 33*10**16){ // the last contributed amount is 33% or less of lastReserveAmount, step down * 3
                multiplier = 3;
            } else if (ratio <= 66*10**16){ // the last contributed amount is between 33%+ and 66% of lastReserveAmount, step down * 2
                multiplier = 2;
            } else { // the last contributed amount is greater than 66%+ of lastReserveAmount, step down * 1
                multiplier = 1;
            }

            newUSDPrice = lastUSDPrice.sub(_reserveStep.mul(multiplier)); // the new USD price will be the last interval USD price minus the reserve step times the multiplier
            
            if (newUSDPrice <= _reserveFloor) { // new price is less than or equal to the floor reserve
                intervals[interval].reservePrice = (_reserveFloor.mul(WEI_FACTOR)).div(ETHPrice); // set to floor reserve (bottomed)
            } else { // new price is greater than the floor reserve
                intervals[interval].reservePrice = (newUSDPrice.mul(WEI_FACTOR)).div(ETHPrice); // set new reserve price
            }
        } else { // intervalTotals[interval.sub(1)] == lastReserveAmount, last reserve met exactly
            intervals[interval].reservePrice = intervals[interval.sub(1)].reservePrice; // reserve Amount met exactly, no change in price
        }
        // calculate ETHReserveAmount based on the new reserve price
        intervals[interval].ETHReserveAmount = tokensPerInterval.mul(intervals[interval].reservePrice).div(WEI_FACTOR);
                            
    }

    /**
    * @dev Adds this interval's distributed tokens to the _distributedTotal storage variable to track the total number of TBN tokens to be distributed
    * @param interval the interval to do the calculation for
    */
    function _addDistribution(uint256 interval) internal {
        uint256 reserveMultiplier;

        if (intervalTotals[interval.sub(1)] >= intervals[interval.sub(1)].ETHReserveAmount){
            reserveMultiplier = WEI_FACTOR;
        } else {
            reserveMultiplier = intervalTotals[interval.sub(1)].mul(WEI_FACTOR).div(intervals[interval.sub(1)].ETHReserveAmount);
        }
        uint256 intervalDistribution = (tokensPerInterval.mul(reserveMultiplier)).div(WEI_FACTOR);

        _distributedTotal = _distributedTotal.add(intervalDistribution);
    }
}