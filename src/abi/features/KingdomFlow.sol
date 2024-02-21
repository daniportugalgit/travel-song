// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../erc20/interfaces/IBkERC20.sol";

import "../interfaces/IKingdomFunds.sol";
import "../interfaces/IKingdomNobles.sol";
import "../interfaces/IKoziPool.sol";

contract KingdomFlow is AdministrableUpgradable2024 {
  IBkERC20 public stableToken; // a trusted ERC20 token

  IKingdomFunds public kingdomFunds;
  IKingdomNobles public kingdomNobles;
  IKoziPool public koziPool;

  uint256 public totalBurnedKozi;
  uint256 public totalStabletokensDistributed;

  address public treasury;

  uint256 public lastFlowBlock;
  uint256 public maxKoziPerFlow;
  bool public burnExcessKozi;

  event FlowKozi(address from, uint256 amount, uint256 stableTokensDistributed, uint256 totalStabletokensDistributed);
  event BurnKozi(address from, uint256 amount, uint256 totalBurnedKozi);

  function initialize(
    address _operator,
    address _blocklist,
    address _stableToken,
    address _treasury
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    stableToken = IBkERC20(_stableToken);
    treasury = _treasury;
    maxKoziPerFlow = 99999 * 1e18; // start with this, then go down to 360 * 1e16 after 3 months.
    burnExcessKozi = false; // start with this, then change to true after 3 months.
  }

  ////////////////////////////
  // UPDATER functions:
  function flowKozi(address[] memory _kingdomNobles) external payable mutex whenNotPaused onlyRole(UPDATER_ROLE) {
    lastFlowBlock = block.number;

    // we'll first get a loose estimate of the amount of Kozi we should sell
    // it's always a bit lower than the amount needed to push the price below the Target Price
    uint256 amountToSell = koziPool.estimateKindomSellToTargetPrice();

    if (amountToSell > 0) {
      // if the current price is above the Target Price, we'll sell Kozi to the Kozi Pool

      // we'll sell up to 3.6 Kozi at a time
      if (amountToSell > maxKoziPerFlow) {
        amountToSell = maxKoziPerFlow;
      }

      // we'll sell up to the amount of Kozi we received
      if (amountToSell > msg.value) {
        amountToSell = msg.value;
      }

      uint256 excessKozi = msg.value - amountToSell;

      // we'll sell the Kozi to the Kozi Pool and receive Stabletokens in return
      koziPool.kingdomSell{value: amountToSell}();

      // now, we send each portion to the right place: Funds and Kingdom Nobles
      uint256 stabletokenBalance = stableToken.balanceOf(address(this));

      // update the totalStabletokensDistributed
      totalStabletokensDistributed += stabletokenBalance;

      // we'll send 12.5% of the total Stabletokens to the Kingdom Nobles
      uint256 amountToNobles = (stabletokenBalance * 125) / 1000;
      kingdomNobles.distribute(_kingdomNobles, amountToNobles);

      // 4% of the total Stabletokens will be sent to the Cosmic Fund (#1)
      uint256 amountToCosmicFund = (stabletokenBalance * 4) / 100;
      kingdomFunds.deposit(1, amountToCosmicFund);

      // 4% of the total Stabletokens will be sent to the Beast Kingdom Commonwealth Fund (#2)
      uint256 amountToBeastKingdomCommonwealthFund = (stabletokenBalance * 4) / 100;
      kingdomFunds.deposit(2, amountToBeastKingdomCommonwealthFund);

      // 3% of the total Stabletokens will be sent to the Crystal Ball initiave (#3)
      uint256 amountToCrystalBallInitiative = (stabletokenBalance * 3) / 100;
      kingdomFunds.deposit(3, amountToCrystalBallInitiative);

      // 1.5% of the total Stabletokens will be sent to the Noble Fortune Saga Fund (#4) [part of the Crystal Ball Initiative]
      uint256 amountToNobleFortuneSagaFund = (stabletokenBalance * 15) / 1000;
      kingdomFunds.deposit(4, amountToNobleFortuneSagaFund);

      // the rest of the Stabletokens will be sent to the Treasury
      uint256 amountToTreasury = stableToken.balanceOf(address(this));
      stableToken.transfer(treasury, amountToTreasury);

      // if there's any excess Kozi, we'll burn it
      if (excessKozi > 0) {
        if (burnExcessKozi) {
          _burnKozi(excessKozi);
        } else {
          // if we're not burning the excess Kozi, we'll send it back to the sender
          payable(msg.sender).transfer(excessKozi);
        }
      }

      emit FlowKozi(msg.sender, msg.value, stabletokenBalance, totalStabletokensDistributed);
    } else {
      // if the current price is below the Target Price, we'll burn all the Kozi we received
      if (burnExcessKozi) {
        _burnKozi(msg.value);
      } else {
        // if we're not burning the Kozi, we'll send it back to the sender
        payable(msg.sender).transfer(msg.value);
      }
    }
  }

  function _burnKozi(uint256 amount) private {
    // burn it
    payable(address(0)).transfer(amount);

    // update the totalBurnedKozi
    totalBurnedKozi += amount;

    emit BurnKozi(msg.sender, amount, totalBurnedKozi);
  }

  ////////////////////////////
  // Operator Functions
  function setContracts(
    address _kingdomFunds,
    address _kingdomNobles,
    address _koziPool
  ) public onlyRole(OPERATOR_ROLE) {
    kingdomFunds = IKingdomFunds(_kingdomFunds);
    kingdomNobles = IKingdomNobles(_kingdomNobles);
    koziPool = IKoziPool(_koziPool);

    // approve kingdomFunds and kingdomNobles to spend stabletokens:
    stableToken.approve(_kingdomFunds, type(uint256).max);
    stableToken.approve(_kingdomNobles, type(uint256).max);
  }

  function setMaxKoziPerFlow(uint256 _maxKoziPerFlow) public onlyRole(OPERATOR_ROLE) {
    maxKoziPerFlow = _maxKoziPerFlow;
  }

  function setBurnExcessKozi(bool _burnExcessKozi) public onlyRole(OPERATOR_ROLE) {
    burnExcessKozi = _burnExcessKozi;
  }
}
