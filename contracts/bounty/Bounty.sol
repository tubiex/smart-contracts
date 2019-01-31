pragma solidity ^0.5.2;

import "../ERC20/IERC20.sol";
import "../crowdsale/ICrowdsale.sol";
import "./IBounty.sol";
import "../access/roles/ManagerRole.sol";
import "../access/roles/RecoverRole.sol";
import "../access/roles/FundkeeperRole.sol";
import "../math/SafeMath.sol";

/**
 * @title Bounty module contract - for tracking records of Bounty tokens before claiming at the crowdsale
 *
 */
contract Bounty is IBounty, ManagerRole, RecoverRole {
    using SafeMath for uint256;
    
    /*
     *  Storage
     */
    struct BountyData {
        uint256 allocation;
        uint256 balance;
        uint256 claimBlock;
    }

    mapping (address => BountyData) private _bountyData;

    bool private _claimable;
    
    uint256 private _allocation;

    uint256 private _totalSupply;

    IERC20 private _erc20;

    ICrowdsale private _crowdsale;

    bool _setCrowdsale;

    Stages public stages;

    /*
     *  Enums
     */
    enum Stages {
        BountyDeployed,
        Bounty,
        BountyEnded
    }

    uint256 CLAIM_PERIOD = 5760; // the number of blocks per claim period (5760 is the number of blocks in a day)
    
    /*
     *  Modifiers
     */
    modifier atStage(Stages _stage) {
        require(stages == _stage, "functionality not allowed at current stage");
        _;
    }

    modifier isClaimable() {
        require(address(_crowdsale) != address(0x0), "_contract must be deployed and address set");
        if (!_claimable){
            require(_crowdsale.currentStage() >= 1, "_crowdsale must be initialized to claim");
            _claimable = true;
        }
        _;
    }

    /**
    * @dev Constructor
    * @param token TBNERC20 token contract
    */
    constructor(IERC20 token) public {
        require(address(token) != address(0x0), "token address cannot be 0x0");
        _erc20 = token;
        stages = Stages.BountyDeployed;
    }

    /**
    * @dev Safety fallback reverts missent ETH payments 
    */
    function () external payable {
        revert (); 
    }  

  /**
    * @dev Safety function for recovering missent ERC20 tokens (and recovering the un-distributed allocation after BountyEnded)
    * @param token address of the ERC20 contract to recover
    */
    function recoverTokens(IERC20 token) 
        external 
        onlyRecoverer 
        returns (bool) 
    {
        if (token == _erc20){
            require(uint(stages) >= 2, "if recovering TBN, must have progressed to BountyEnded");
        }

        uint256 recovered = token.balanceOf(address(this));
        token.transfer(msg.sender, recovered);
        emit TokensRecovered(token, recovered);
        return true;
    }

    /**
    * @dev Total number of tokens allocated to bounty
    */
    function getAllocation() public view returns (uint256) {
        return _allocation;
    }

    /**
    * @dev Total number of bounty allocated tokens un-distributed to accounts 
    */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
    * @dev Total number of bounty tokens distributed to accounts
    */
    function getDistribution() public view returns (uint256) {
        return _allocation.sub(_totalSupply);
    }

    /**
    * @dev Gets the total bounty allocation of the specified address.
    * @param account The address to query the balance of.
    * @return An uint256 representing the total allocation for this account (claimed or not)
    */
    function allocationOf(address account) public view returns (uint256) {
        return _bountyData[account].allocation;
    }

    /**
    * @dev Gets the current bounty balance of the specified address. (unclaimed tokens)
    * @param account The address to query the balance of.
    * @return An uint256 representing the amount of bounty tokens claimable or transferable
    */
    function bountyBalanceOf(address account) public view returns (uint256) {
        return _bountyData[account].balance;
    }

    /**
    * @dev Gets the pre-crowdsale bounty balance of the specified address.
    * @param account The address to query the balance of.
    * @return An uint256 representing the last block that this account claimed on
    */
    function claimBlock(address account) public view returns (uint256) {
        return _bountyData[account].claimBlock;
    }
    
    function getERC20() public view returns (address) {
        return address(_erc20);
    }

    /**
    * @dev Allows accounts to claim Bounty allocated TBN, at a rate of 1% per day accumulated
    */
    function claim() 
        public
        isClaimable() 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        uint256 claimAmount = _claimAmount(msg.sender);
        require(claimAmount > 0, "claimAmount must be greater than 0 to claim - 0 indicates that this account has already claimed this period or has a balance of 0");
        emit BountyClaim(msg.sender, claimAmount);
        _erc20.transfer(msg.sender, claimAmount);
        return true;
    }

    /**
    * @dev Assigns the bounty token allocation to this contract. Note: TBN token fundkeeper must give this contract an allowance before calling initialize
    * @param initialAllocation the amount of tokens assigned to this contract for Bounty distribution upon initialization
    */
    function initilize(uint256 initialAllocation)
        external 
        onlyManager 
        atStage(Stages.BountyDeployed) 
        returns (bool) 
    {
        _addAllocation(initialAllocation);
        stages = Stages.Bounty;
        emit Initialized(initialAllocation);
        return true;
    }

    /**
    * @dev Add new bounty allocation to the contract. Can only be called by the Manager Role
    * @param value The amount of TBN to be added to the total contract allocation
    */
    function addAllocation(uint256 value) 
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        _addAllocation(value);
        return true;
    }

    /**
    * @dev Assign bounty tokens to accounts (only contract Manger and only at bounty Stage)
    * @param accounts The accounts to add bounty token balances to
    * @param values The amount of tokens to be added to each account
    */
    function addBalance(address[] calldata accounts, uint256[] calldata values)  
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        require(accounts.length == values.length, "bountyAccounts and values must have one-to-one relationship");
        
        for (uint32 i = 0; i < accounts.length; i++) {
            _addBalance(accounts[i], values[i]);
        }
        return true;
    }

    /**
    * @dev Subtract bounty tokens to accounts (only contract Manger and only at Bounty Stage)
    * @param accounts The accounts to subtract bounty token balances from
    * @param values The amount of tokens to subtract from each account
    */
    function subBalance(address[] calldata accounts, uint256[] calldata values) 
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        require(accounts.length == values.length, "accounts and values must have one-to-one relationship");
        
        for (uint32 i = 0; i < accounts.length; i++) {
            _subBalance(accounts[i], values[i]);
        }
        return true;
    }

    /**
    * @dev Transfer bounty tokens to another account
    * @param from The address to transfer from.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    * @return bool true on success
    */
    function bountyTransfer(address from, address to, uint256 value) 
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        _bountyTransfer(from, to, value);
        return true;
    }

    /**
    * @dev Called to end bounty Stage. Can only be called by the Manager Role. Ends all Manger functionality for record manipulation and ends user claim functionality. Recoverer can recover TBN after this.
    */
    function bountyEnd() 
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        stages = Stages.BountyEnded;
        emit BountyEnded();
        return true;
    }

   /**
    * @dev Add allocated TBN to the bounty contract (internal operation)
    * @param value The amount of tokens to be added to this contract's total allocation
    */
    function _addAllocation(uint256 value) internal {
        address fundkeeper = FundkeeperRole(address(_erc20)).fundkeeper();
        require(_erc20.allowance(address(fundkeeper), address(this)) == value, "bounty allocation must be equal to the amount of tokens approved for this contract");
       
        _allocation = _allocation.add(value);
        _totalSupply = _totalSupply.add(value);

        emit AllocationAdded(value);

        // place Bounty allocation in this contract (uses the approve/transferFrom pattern)
        _erc20.transferFrom(fundkeeper, address(this), value);
    }

    /**
    * @dev Add bounty tokens to an account (internal operation)
    * @param account The account which is assigned bounty holdings
    * @param value The amount of tokens to be assigned to this account
    */
    function _addBalance(address account, uint256 value) internal {
        require(account != address(0), "cannot add balance to the 0x0 account");
        require(value <= _totalSupply, "cannot add more allocation to an account than is remaining in the bounty supply");
        
        if(_bountyData[account].claimBlock == 0){ // if this account hasn't been allocated tokens before, set the claimBlock to the current block number
            _bountyData[account].claimBlock = block.number;
        }

        _totalSupply = _totalSupply.sub(value);

        _bountyData[account].allocation = _bountyData[account].allocation.add(value);
        _bountyData[account].balance = _bountyData[account].balance.add(value);

        emit BalanceAdded(account, value);
    }

    /**
    * @dev Subtract bounty tokens from an account (internal operation)
    * @param account The account which is subtracted bounty holdings
    * @param value The amount of tokens to be assigned to this account
    */
    function _subBalance(address account, uint256 value) internal {
        require(_bountyData[account].balance > 0, "bountyAccount must have bounty balance to subtract");
        require(value <= _bountyData[account].balance, "value must be less than or equal to the bounty Account balance");

        _totalSupply = _totalSupply.add(value);

        _bountyData[account].allocation = _bountyData[account].allocation.sub(value);
        _bountyData[account].balance = _bountyData[account].balance.sub(value);

        emit BalanceSubtracted(account, value);
    }

    /**
    * @dev Transfer bounty tokens to another account (internal operation)
    * @param from The address to transfer from.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function _bountyTransfer(address from, address to, uint256 value) internal {
        require(value <= _bountyData[from].balance, "transfer value must be less than the balance of the from account");
        require(to != address(0), "cannot transfer to the 0x0 address");

        _bountyData[from].allocation = _bountyData[from].allocation.sub(value);
        _bountyData[from].balance = _bountyData[from].balance.sub(value);

        if(_bountyData[to].claimBlock == 0){ // if the to account hasn't been allocated tokens before, set the claimBlock to the current block number
            _bountyData[to].claimBlock = block.number;
        }

        _bountyData[to].allocation = _bountyData[to].allocation.add(value);
        _bountyData[to].balance = _bountyData[to].balance.add(value);

        emit Transfer(from, to, value);
    }

    /**
    * @dev Calculates an available claiming portion of an accounts tokens - set to 1% per day accumulated or the remaining balance whichever is smaller (internal operation)
    * @param account The account which claiming is calculated for
    */
    function _claimAmount(address account) internal returns (uint256) {
        uint256 claimAmount;
        uint256 intervals;

        if(block.number < _bountyData[account].claimBlock.add(CLAIM_PERIOD)) { // check the interval of claiming	
            return 0; // already claimed this period
        } else {
            intervals = (block.number.sub(_bountyData[account].claimBlock)).div(CLAIM_PERIOD);
        }

        if(_bountyData[account].balance  <= 10**20){
            claimAmount = 10**20; // this is 100 TBN (100 TBN is the minimum claiming amount per interval when balance can support)
        } else {
            claimAmount = (_bountyData[account].allocation.mul(intervals)).div(100);
            if(claimAmount < 10**20) {
                claimAmount = 10**20;
            }
        }

        if (_bountyData[account].balance > 0){ // check if there is any remaining balance to claimAmount
            if (claimAmount < _bountyData[account].balance) { // check if the claimAmount is < balance
                _bountyData[account].balance = _bountyData[account].balance.sub(claimAmount);
                _bountyData[account].claimBlock = _bountyData[account].claimBlock.add(CLAIM_PERIOD.mul(intervals));
                return claimAmount;
            } else { // claimAmount is >= balance
                claimAmount = _bountyData[account].balance; // claimAmount all remaining, as the remaining balance is less than this account's approved claim amount
                _bountyData[account].balance = _bountyData[account].balance.sub(claimAmount);
                _bountyData[account].claimBlock = block.number;
                return claimAmount;
            }
        } else { // no remaining balance to vest
            return 0;
        }
    }

    /**
    * @dev Set the crowdsale contract storage (only contract Manager and only at Bounty Stage)
    * @param TBNCrowdsale The crowdsale contract deployment
    */
    function setCrowdsale(ICrowdsale TBNCrowdsale)      
        external 
        onlyManager 
        atStage(Stages.Bounty) 
        returns (bool) 
    {
        require(!_setCrowdsale, "the Crowdsale contract address has already been set");
        require(TBNCrowdsale.getERC20() == address(_erc20), "Crowdsale contract must be assigned to the same ERC20 instance as this contract");
        _crowdsale = TBNCrowdsale;
        _setCrowdsale = true;
        emit SetCrowdsale(_crowdsale);
        return true;
    }
}