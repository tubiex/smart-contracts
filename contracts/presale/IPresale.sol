pragma solidity ^0.5.2;

import "../ERC20/IERC20.sol";
import "../crowdsale/ICrowdsale.sol";
/**
 * @title Presale Interface
 */
interface IPresale {

    /** 
    * Getters
    */

    // the amount of tokens allocated to this Presale contract
    function getAllocation() external view returns (uint256);

    // the remaining token supply not assigned to accounts
    function totalSupply() external view returns (uint256);

    // the total number of Presale tokens distributed to accounts
    function getDistribution() external view returns (uint256);

    // get an account's current allocated Presale token record
    function allocationOf(address account) external view returns (uint256);

    // get an account's current unclaimed Presale token record
    function presaleBalanceOf(address account) external view returns (uint256);

    // get the block number of the account's last claim
    function claimBlock(address account) external view returns (uint256);

    // get the ERC20 token deployment this Presale contract is dependent on
    function getERC20() external view returns (address);

    /*** PresaleDeployed Stage functions ***/ 

    /** 
    * Manager Role Functionality
    */ 
    function initilize (uint256 presaleAllocation) external returns (bool);
    
    // Presale Stage functions

    /**
    * Public Functionality
    */
    // for accounts to claim their Presale tokens at a rate of 1% or 100 TBN daily (whichever is larger)
    function claim() external returns (bool);

    /** 
    * Manager Role Functionality
    */ 
    // add new token allotment to the total presale allocation 
    function addAllocation(uint256 value) external returns (bool); 

    // add presale tokens to user account balances
    function addBalance(address[] calldata accounts, uint256[] calldata values) external returns (bool);

    // subtract presale tokens from accounts to adjust presale balances
    function subBalance(address[] calldata accounts, uint256[] calldata values) external returns (bool);
    
    // transfer some amount of tokens from one account to another to adjust presale balances
    function presaleTransfer(address from, address to, uint256 value) external returns (bool);

    // set the Crowdsale contract deployed address (required for allowing crowdsale to set the claimable flag when initialized)
    function setCrowdsale(ICrowdsale TBNCrowdsale) external returns (bool);

    // ends the Presale Stage (thereby locking any account updating and transferring or additional allocation by Manager and claiming by users)
    function presaleEnd() external returns (bool);

    // PresaleEnded Stage functions

    /** 
    * Recoverer Role Functionality
    */
    // allows recovery of missent tokens (anytime) as well as recovery of un-distributed TBN once the Presale Stage has ended.
    function recoverTokens(IERC20 token) external returns (bool);


    /** 
    * Events
    */
    event Initialized(
        uint256 presaleAllocation
    );

    event AllocationAdded(
        uint256 value
    );

    event BalanceAdded( 
        address indexed presaleAccount, 
        uint256 value
    );

    event BalanceSubtracted( 
        address indexed presaleAccount, 
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

    event PresaleClaim(
        address indexed account,
        uint256 claimAmount
    );

    event PresaleEnded();

    event TokensRecovered(
        IERC20 token, 
        uint256 recovered
    );

}
