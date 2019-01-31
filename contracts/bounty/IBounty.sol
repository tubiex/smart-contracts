pragma solidity ^0.5.2;

import "../ERC20/IERC20.sol";
import "../crowdsale/ICrowdsale.sol";
/**
 * @title Bounty Interface
 */
interface IBounty {

    /** 
    * Getters
    */

    // the amount of tokens allocated to this Bounty contract
    function getAllocation() external view returns (uint256);

    // the remaining token supply not assigned to accounts
    function totalSupply() external view returns (uint256);

    // the total number of Bounty tokens distributed to accounts
    function getDistribution() external view returns (uint256);

    // get an account's current allocated Bounty token record
    function allocationOf(address account) external view returns (uint256);

    // get an account's current unclaimed Bounty token record
    function bountyBalanceOf(address account) external view returns (uint256);

    // get the block number of the account's last claim
    function claimBlock(address account) external view returns (uint256);

    // get the ERC20 token deployment this Bounty contract is dependent on
    function getERC20() external view returns (address);

    /*** BountyDeployed Stage functions ***/ 

    /** 
    * Manager Role Functionality
    */ 
    function initilize (uint256 bountyAllocation) external returns (bool);
    
    // Bounty Stage functions

    /**
    * Public Functionality
    */
    // for accounts to claim their Bounty tokens at a rate of 1% or 100 TBN daily (whichever is larger)
    function claim() external returns (bool);

    /** 
    * Manager Role Functionality
    */ 
    // add new token allotment to the total bounty allocation 
    function addAllocation(uint256 value) external returns (bool); 

    // add bounty tokens to user account balances
    function addBalance(address[] calldata accounts, uint256[] calldata values) external returns (bool);

    // subtract bounty tokens from accounts to adjust bounty balances
    function subBalance(address[] calldata accounts, uint256[] calldata values) external returns (bool);
    
    // transfer some amount of tokens from one account to another to adjust bounty balances
    function bountyTransfer(address from, address to, uint256 value) external returns (bool);

    // set the Crowdsale contract deployed address (required for allowing crowdsale to set the claimable flag when initialized)
    function setCrowdsale(ICrowdsale TBNCrowdsale) external returns (bool);

    // ends the Bounty Stage (thereby locking any account updating and transferring or additional allocation by Manager and claiming by users)
    function bountyEnd() external returns (bool);

    // BountyEnded Stage functions

    /** 
    * Recoverer Role Functionality
    */
    // allows recovery of missent tokens (anytime) as well as recovery of un-distributed TBN once the Bounty Stage has ended.
    function recoverTokens(IERC20 token) external returns (bool);


    /** 
    * Events
    */
    event Initialized(
        uint256 bountyAllocation
    );

    event AllocationAdded(
        uint256 value
    );

    event BalanceAdded( 
        address indexed bountyAccount, 
        uint256 value
    );

    event BalanceSubtracted( 
        address indexed bountyAccount, 
        uint256 value
    );

    event Transfer(
        address indexed from, 
        address indexed to,
        uint256 value
    );

    event SetCrowdsale(
        ICrowdsale crowdsale 
    );

    event BountyClaim(
        address indexed account,
        uint256 claimAmount
    );

    event BountyEnded();

    event TokensRecovered(
        IERC20 token, 
        uint256 recovered
    );

}