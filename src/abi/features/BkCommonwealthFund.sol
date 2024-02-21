// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../erc20/interfaces/IBkERC20.sol";
import "../interfaces/ICommunityPool.sol";

contract BkCommonwealthFund is AdministrableUpgradable2024 {
  IBkERC20 public stableToken;
  IBkERC20 public bct;
  ICommunityPool public communityPool;

  address public farmAddress;

  uint256 public totalBurnedBct;
  uint256 public totalStabletokensAdded;
  uint256 public totalFarmRefilledBct;

  uint256 public lastFlowBlock;

  event AddStabletokensToPool(address from, uint256 amount, uint256 totalStabletokensAdded);
  event BurnBctFromPool(address from, uint256 amount, uint256 totalBurnedBct);
  event RefillFarmBct(address from, uint256 amount, uint256 totalFarmRefilledBct);
  event NoStabletokensToFlow(address from, uint256 lastFlowBlock);
  event FlowStabletokens(address from, uint256 lastFlowBlock, uint256 priceBefore, uint256 priceAfter);

  function initialize(
    address _operator,
    address _blocklist,
    address _stableToken,
    address _bct,
    address _communityPool,
    address _farmAddress
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    stableToken = IBkERC20(_stableToken);
    bct = IBkERC20(_bct);
    communityPool = ICommunityPool(_communityPool);
    farmAddress = _farmAddress;

    bct.approve(_communityPool, type(uint256).max);
    stableToken.approve(_communityPool, type(uint256).max);
  }

  ////////////////////////////
  // UPDATER functions:
  function flowStabletokens() external mutex whenNotPaused onlyRole(UPDATER_ROLE) {
    lastFlowBlock = block.number;

    uint256 priceBefore = communityPool.getPrice();

    uint256 currentBalance = stableToken.balanceOf(address(this));

    if (currentBalance == 0) {
      emit NoStabletokensToFlow(msg.sender, lastFlowBlock);
      return;
    }

    uint256 amountToBuyAndBurn = 1 * 1E18; // 1 stabletoken
    if (amountToBuyAndBurn > currentBalance) {
      amountToBuyAndBurn = currentBalance;
    }

    // actually buy and burn $1 in BCT
    uint256 bctBurned = communityPool.actuallyBuyAndBurn(amountToBuyAndBurn);
    totalBurnedBct += bctBurned;
    totalStabletokensAdded += amountToBuyAndBurn;
    emit AddStabletokensToPool(msg.sender, amountToBuyAndBurn, totalStabletokensAdded);

    // refill the farm with the BCT
    uint256 bctToRefill = 27775 * 1E16; // 277.75 BCT
    if (totalFarmRefilledBct < 1000000 * 1e18) {
      communityPool.recoverERC20(address(bct), farmAddress, bctToRefill);
      totalFarmRefilledBct += bctToRefill;
      emit RefillFarmBct(msg.sender, bctToRefill, totalFarmRefilledBct);
    }

    if (totalBurnedBct < 1000000 * 1e18) {
      // Burn the same amount of stabletokens from the pool
      communityPool.burnBct(bctToRefill);
      bctBurned += bctToRefill;
      totalBurnedBct += bctBurned;
    }

    emit BurnBctFromPool(msg.sender, bctBurned, totalBurnedBct);
    uint256 priceAfter = communityPool.getPrice();
    emit FlowStabletokens(msg.sender, lastFlowBlock, priceBefore, priceAfter);
  }

  ////////////////////////////
  // Operator Functions
}
