pragma solidity ^0.5.2;

import "../ERC20/IERC20.sol";
import "../crowdsale/ICrowdsale.sol";
import "./IPresale.sol";
import "../access/roles/ManagerRole.sol";
import "../access/roles/RecoverRole.sol";
import "../access/roles/FundkeeperRole.sol";
import "../math/SafeMath.sol";

/**
 * @title Presale module contract - for tracking records of Presale tokens before claiming at the crowdsale
 *
 */
contract Presale is IPresale, ManagerRole, RecoverRole {
    using SafeMath for uint256;
    
    /*
     *  Storage
     */
    struct PresaleData {
        uint256 allocation;
        uint256 balance;
        uint256 claimBlock;
    }

    mapping (address => PresaleData) private _presaleData;

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
        PresaleDeployed,
        Presale,
        PresaleEnded
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
        stages = Stages.PresaleDeployed;
    }

    /**
    * @dev Safety fallback reverts missent ETH payments 
    */
    function () external payable {
        revert (); 
    }  

  /**
    * @dev Safety function for recovering missent ERC20 tokens (and recovering the un-distributed allocation after PresaleEnded)
    * @param token address of the ERC20 contract to recover
    */
    function recoverTokens(IERC20 token) 
        external 
        onlyRecoverer 
        returns (bool) 
    {
        if (token == _erc20){
            require(uint(stages) >= 2, "if recovering TBN, must have progressed to PresaleEnded");
        }

        uint256 recovered = token.balanceOf(address(this));
        emit TokensRecovered(token, recovered);
        token.transfer(msg.sender, recovered);
        return true;
    }

    /**
    * @dev Total number of tokens allocated to presale
    */
    function getAllocation() public view returns (uint256) {
        return _allocation;
    }

    /**
    * @dev Total number of presale allocated tokens un-distributed to accounts 
    */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
    * @dev Total number of presale tokens distributed to accounts
    */
    function getDistribution() public view returns (uint256) {
        return _allocation.sub(_totalSupply);
    }

    /**
    * @dev Gets the total presale allocation of the specified address.
    * @param account The address to query the balance of.
    * @return An uint256 representing the total allocation for this account (claimed or not)
    */
    function allocationOf(address account) public view returns (uint256) {
        return _presaleData[account].allocation;
    }

    /**
    * @dev Gets the current presale balance of the specified address. (unclaimed tokens)
    * @param account The address to query the balance of.
    * @return An uint256 representing the amount of presale tokens claimable or transferable
    */
    function presaleBalanceOf(address account) public view returns (uint256) {
        return _presaleData[account].balance;
    }

    /**
    * @dev Gets the pre-crowdsale presale balance of the specified address.
    * @param account The address to query the balance of.
    * @return An uint256 representing the last block that this account claimed on
    */
    function claimBlock(address account) public view returns (uint256) {
        return _presaleData[account].claimBlock;
    }
    
    function getERC20() public view returns (address) {
        return address(_erc20);
    }

    function currentStage() public view returns(uint256) {
        return uint(stages);
    }
    
    /**
    * @dev Allows accounts to claim Presale allocated TBN, at a rate of 1% per day accumulated
    */
    function claim() 
        public
        isClaimable() 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        uint256 claimAmount = _claimAmount(msg.sender);
        require(claimAmount > 0, "claimAmount must be greater than 0 to claim - 0 indicates that this account has already claimed this period or has a balance of 0");
        emit PresaleClaim(msg.sender, claimAmount);
        _erc20.transfer(msg.sender, claimAmount);
        return true;
    }

    /**
    * @dev Assigns the presale token allocation to this contract. Note: TBN token fundkeeper must give this contract an allowance before calling initialize
    * @param initialAllocation the amount of tokens assigned to this contract for Presale distribution upon initialization
    */
    function initilize(uint256 initialAllocation)
        external 
        onlyManager 
        atStage(Stages.PresaleDeployed) 
        returns (bool) 
    {
        _addAllocation(initialAllocation);
        stages = Stages.Presale;
        emit Initialized(initialAllocation);
        return true;
    }

    /**
    * @dev Add new presale allocation to the contract. Can only be called by the Manager Role
    * @param value The amount of TBN to be added to the total contract allocation
    */
    function addAllocation(uint256 value) 
        external 
        onlyManager 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        _addAllocation(value);
        return true;
    }

    /**
    * @dev Assign presale tokens to accounts (only contract Manger and only at presale Stage)
    * @param accounts The accounts to add presale token balances to
    * @param values The amount of tokens to be added to each account
    */
    function addBalance(address[] calldata accounts, uint256[] calldata values) 
        external 
        onlyManager 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        require(accounts.length == values.length, "presaleAccounts and values must have one-to-one relationship");
        
        for (uint32 i = 0; i < accounts.length; i++) {
            _addBalance(accounts[i], values[i]);
        }
        return true;
    }

    /**
    * @dev Subtract presale tokens to accounts (only contract Manger and only at Presale Stage)
    * @param accounts The accounts to subtract presale token balances from
    * @param values The amount of tokens to subtract from each account
    */
    function subBalance(address[] calldata accounts, uint256[] calldata values) 
        external 
        onlyManager 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        require(accounts.length == values.length, "accounts and values must have one-to-one relationship");
        
        for (uint32 i = 0; i < accounts.length; i++) {
            _subBalance(accounts[i], values[i]);
        }
        return true;
    }

    /**
    * @dev Transfer presale tokens to another account
    * @param from The address to transfer from.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    * @return bool true on success
    */
    function presaleTransfer(address from, address to, uint256 value) 
        external 
        onlyManager 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        _presaleTransfer(from, to, value);
        return true;
    }

    /**
    * @dev Called to end presale Stage. Can only be called by the Manager Role. Ends all Manger functionality for record manipulation and ends user claim functionality. Recoverer can recover TBN after this.
    */
    function presaleEnd() 
        external 
        onlyManager 
        atStage(Stages.Presale) 
        returns (bool) 
    {
        stages = Stages.PresaleEnded;
        emit PresaleEnded();
        return true;
    }

   /**
    * @dev Add allocated TBN to the presale contract (internal operation)
    * @param value The amount of tokens to be added to this contract's total allocation
    */
    function _addAllocation(uint256 value) internal {
        address fundkeeper = FundkeeperRole(address(_erc20)).fundkeeper();
        require(_erc20.allowance(address(fundkeeper), address(this)) == value, "presale allocation must be equal to the amount of tokens approved for this contract");
       
        _allocation = _allocation.add(value);
        _totalSupply = _totalSupply.add(value);
        
        emit AllocationAdded(value);
        
        // place Presale allocation in this contract (uses the approve/transferFrom pattern)
        _erc20.transferFrom(fundkeeper, address(this), value);
    }

    /**
    * @dev Add presale tokens to an account (internal operation)
    * @param account The account which is assigned presale holdings
    * @param value The amount of tokens to be assigned to this account
    */
    function _addBalance(address account, uint256 value) internal {
        require(account != address(0), "cannot add balance to the 0x0 account");
        require(value <= _totalSupply, "cannot add more allocation to an account than is remaining in the presale supply");
        
        if(_presaleData[account].claimBlock == 0){ // if this account hasn't been allocated tokens before, set the claimBlock to the current block number
            _presaleData[account].claimBlock = block.number;
        }

        _totalSupply = _totalSupply.sub(value);

        _presaleData[account].allocation = _presaleData[account].allocation.add(value);
        _presaleData[account].balance = _presaleData[account].balance.add(value);

        emit BalanceAdded(account, value);
    }

    /**
    * @dev Subtract presale tokens from an account (internal operation)
    * @param account The account which is subtracted presale holdings
    * @param value The amount of tokens to be assigned to this account
    */
    function _subBalance(address account, uint256 value) internal {
        require(_presaleData[account].balance > 0, "presaleAccount must have presale balance to subtract");
        require(value <= _presaleData[account].balance, "value must be less than or equal to the presale Account balance");

        _totalSupply = _totalSupply.add(value);

        _presaleData[account].allocation = _presaleData[account].allocation.sub(value);
        _presaleData[account].balance = _presaleData[account].balance.sub(value);

        emit BalanceSubtracted(account, value);
    }

    /**
    * @dev Transfer presale tokens to another account (internal operation)
    * @param from The address to transfer from.
    * @param to The address to transfer to.
    * @param value The amount to be transferred.
    */
    function _presaleTransfer(address from, address to, uint256 value) internal {
        require(value <= _presaleData[from].balance, "transfer value must be less than the balance of the from account");
        require(to != address(0), "cannot transfer to the 0x0 address");

        _presaleData[from].allocation = _presaleData[from].allocation.sub(value);
        _presaleData[from].balance = _presaleData[from].balance.sub(value);

        if(_presaleData[to].claimBlock == 0){ // if the to account hasn't been allocated tokens before, set the claimBlock to the current block number
            _presaleData[to].claimBlock = block.number;
        }

        _presaleData[to].allocation = _presaleData[to].allocation.add(value);
        _presaleData[to].balance = _presaleData[to].balance.add(value);

        emit Transfer(from, to, value);
    }

    /**
    * @dev Calculates an available claiming portion of an accounts tokens - set to 1% per day accumulated or the remaining balance whichever is smaller (internal operation)
    * @param account The account which claiming is calculated for
    */
    function _claimAmount(address account) internal returns (uint256) {
        uint256 claimAmount;
        uint256 intervals;

        if(block.number < _presaleData[account].claimBlock.add(CLAIM_PERIOD)) { // check the interval of claiming	
            return 0; // already claimed this period
        } else {
            intervals = (block.number.sub(_presaleData[account].claimBlock)).div(CLAIM_PERIOD);
        }

        if(_presaleData[account].balance  <= 10**20){
            claimAmount = 10**20; // this is 100 TBN (100 TBN is the minimum claiming amount per interval when balance can support)
        } else {
            claimAmount = (_presaleData[account].allocation.mul(intervals)).div(100);
            if(claimAmount < 10**20) {
                claimAmount = 10**20;
            }
        }

        if (_presaleData[account].balance > 0){ // check if there is any remaining balance to claimAmount
            if (claimAmount < _presaleData[account].balance) { // check if the claimAmount is < balance
                _presaleData[account].balance = _presaleData[account].balance.sub(claimAmount);
                _presaleData[account].claimBlock = _presaleData[account].claimBlock.add(CLAIM_PERIOD.mul(intervals));
                return claimAmount;
            } else { // claimAmount is >= balance
                claimAmount = _presaleData[account].balance; // claimAmount all remaining, as the remaining balance is less than this account's approved claim amount
                _presaleData[account].balance = _presaleData[account].balance.sub(claimAmount);
                _presaleData[account].claimBlock = block.number;
                return claimAmount;
            }
        } else { // no remaining balance to vest
            return 0;
        }
    }

    /**
    * @dev Set the crowdsale contract storage (only contract Manager and only at Presale Stage)
    * @param TBNCrowdsale The crowdsale contract deployment
    */
    function setCrowdsale(ICrowdsale TBNCrowdsale)      
        external 
        onlyManager 
        atStage(Stages.Presale) 
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