pragma solidity ^0.5.2;

import "../ERC20/IERC20.sol";

/**
 * @title Crowdsale Interface
 */
interface ICrowdsale {

  /** 
  * Getters
  */

  function getInterval(uint256 blockNumber) external view returns (uint256);
  
  function getERC20() external view returns (address);
  
  function getDistributedTotal() external view returns (uint256);
    
  function currentStage() external view returns (uint256);

  /*** CrowdsaleDeployed Stage functions ***/ 

  /** 
  * Manager Role Functionality
  */ 

  function initialize(
      uint256 ETHPrice,
      uint256 reserveFloor,
      uint256 reserveStart, 
      uint256 reserveCeiling,
      uint256 crowdsaleAllocation
    ) external returns (bool); 

  /*** Crowdsale Stage functions ***/

  /**
  * Public Account Functionality
  */
  // function to participate in the crowdsale by contributing ETH, limit represent the TBN per ETH limit a user would like to enforce (0 means no limit set, free participation)
  function participate(uint256 limit) external payable returns (bool);

  // function to claim TBN from previous specific intervals of participation
  function claim(uint256 interval) external;

  // function to claim a specific array of intervals
  function claimInterval(uint256[] calldata intervals) external returns (bool);

  // function to claim TBN from all previous un-claimed intervals of participation
  function claimAll() external returns (bool);

  /** 
  * Manager Role Functionality
  */
  // function to set a new ETH price for the crowdsale depending on the open market price (will auto-adjust the ETHprice, the reservePrice, and the ETHReserveAmount in the next interval)
  function setRebase(uint256 newETHPrice) external returns (bool);

  // function to reveal the hidden hard cap if/when it is reached (45 days guaranteed)
  function revealCap(uint256 cap, uint256 secret) external returns (bool); 

  /**
  * Fundkeeper Role Functionality
  */
  // function to gather any ETH funds from the crowdsale to the Fundkeeper Account
  function collect() external returns (bool);
  
  /**
   * Whitelister Role Functionality
  */
  // funciton to add to whitelist participants to claim during Crowdsale
  function addToWhitelist(address[] calldata participants) external;
  
  // funciton to remove whitelist participants to claim during Crowdsale
  function removeFromWhitelist(address[] calldata participants) external;

    
  /*** CrowdsaleEnded Stage functions ***/

  /** 
  * Recoverer Role Functionality
  */ 
  // function to recover ERC20 tokens (if TBN ERC20, must occur in the CrowdsaleEnded Stage)
  function recoverTokens(IERC20 token) external returns (bool);

  event Participated (uint256 interval, address account, uint256 amount);
  event Claimed (uint256 interval, address account, uint256 amount);
  event Collected (address collector, uint256 amount);
  event Rebased(uint256 newETHPrice, uint256 newETHReservePrice, uint256 newETHReserveAmount);
  event TokensRecovered(IERC20 token, uint256 recovered);
}