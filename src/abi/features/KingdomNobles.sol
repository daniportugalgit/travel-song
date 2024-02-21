// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../utils/AntiMevLock.sol";
import "../erc20/interfaces/IBkERC20.sol";

contract KingdomNobles is AntiMevLock, AdministrableUpgradable2024 {
  IBkERC20 public stableToken; // a trusted ERC20 token
  address public treasury; // a trusted EOA

  mapping(address => uint256) private _balances; // how much each address has available to withdraw
  mapping(address => uint256) private _accumulatedStabletokensByAddress; // how much each address has accumulated in total
  mapping(address => mapping(uint256 => uint256)) private _loyaltyByCycleAndAddress; // address => => cycle => accumulated sum of the inverse of the positions
  mapping(uint256 => uint256) private _rewardsByPosition; // position => reward

  struct Cycle {
    uint256 number; // 1-indexed
    uint256 startBlock;
    uint256 endBlock;
  }
  Cycle public currentCycle;
  uint256 public cycleDuration;

  uint256 public accumulatedPayouts;

  event DistributeRewards(address[] accounts, uint256 totalRewards, uint256 accumulatedPayouts);
  event WithdrawRewards(address account, uint256 amount);
  event GainLoyalty(address account, uint256 amount, uint256 stabletokens);
  event SpendLoyalty(address account, uint256 amount);
  event ForfeitLoyalty(address account, bytes32 associatedTx, uint256 loyaltyLost);

  mapping(address => uint256) public kingdomNameSetAtBlock;
  mapping(address => string) public kingdomNames;
  uint256 public totalBurnedKozi;

  event BurnKozi(address from, uint256 amount, uint256 totalBurnedKozi);
  event SetKingdomName(address account, string name);
  event MissedRewards(address account, uint256 amount);

  function initialize(
    address _operator,
    address _blocklist,
    address _stableToken,
    address _treasury
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    stableToken = IBkERC20(_stableToken);
    treasury = _treasury;
    _setLockPeriod(8640); // 1 day in blocks

    // Each deposit contains 12.5% of the total stabletokens received by the Kingdom in any given sell to the Kozi Pool
    // They are redistributed to the top 25 holders of Kozi
    // We'll divide this value by 1000 to get the reward per position
    _rewardsByPosition[25] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[24] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[23] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[22] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[21] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[20] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[19] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[18] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[17] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[16] = 4; // Knight: 0.05% of the total (0.4% of the deposit)
    _rewardsByPosition[15] = 8; // High Knight: 0.10% of the total (0.8% of the deposit)
    _rewardsByPosition[14] = 8; // High Knight: 0.10% of the total (0.8% of the deposit)
    _rewardsByPosition[13] = 8; // High Knight: 0.10% of the total (0.8% of the deposit)
    _rewardsByPosition[12] = 8; // High Knight: 0.10% of the total (0.8% of the deposit)
    _rewardsByPosition[11] = 8; // High Knight: 0.10% of the total (0.8% of the deposit)
    _rewardsByPosition[10] = 16; // Knight Commander: 0.20% of the total (1.6% of the deposit)
    _rewardsByPosition[9] = 24; //  Lord: 0.30% of the total (2.4% of the deposit)
    _rewardsByPosition[8] = 32; //  High Lord: 0.40% of the total (3.2% of the deposit)
    _rewardsByPosition[7] = 40; //  Baron: 0.50% of the total (4% of the deposit)
    _rewardsByPosition[6] = 48; //  Viscount: 0.60% of the total (4.8% of the deposit)
    _rewardsByPosition[5] = 56; //  Count: 0.70% of the total (5.6% of the deposit)
    _rewardsByPosition[4] = 80; //  Marquess: 1.00% of the total (8% of the deposit)
    _rewardsByPosition[3] = 120; //  Duke: 1.50% of the total (12% of the deposit)
    _rewardsByPosition[2] = 200; //  Grand Vizier: 2.50% of the total (20% of the deposit)
    _rewardsByPosition[1] = 304; //  The King: 3.80% of the total (30.4% of the deposit)

    cycleDuration = 8640 * 90; // 90 days in blocks
    _startNewCycle();
  }

  function _startNewCycle() private {
    currentCycle.number += 1;
    currentCycle.startBlock = block.number;
    currentCycle.endBlock = block.number + cycleDuration;
  }

  ////////////////////////////
  // Public functions:
  function withdraw() external mutex whenNotPaused onlyUnlockedSender notBlocklisted(msg.sender) {
    uint256 availableRewards = _balances[msg.sender];
    require(availableRewards > 0, "KingdomNobles: no rewards available");

    _balances[msg.sender] = 0;
    require(stableToken.transfer(msg.sender, availableRewards), "KingdomNobles: transfer failed");

    emit WithdrawRewards(msg.sender, availableRewards);
  }

  function setKingdomName(string calldata name) public payable whenNotPaused notBlocklisted(msg.sender) {
    require(bytes(name).length > 0, "KingdomNobles: name too short");
    require(bytes(name).length <= 32, "KingdomNobles: name too long");
    require(msg.value >= 1e17, "It costs 0.1 Kozi"); // it costs 0.1 Kozi to set a name

    kingdomNames[msg.sender] = name;
    kingdomNameSetAtBlock[msg.sender] = block.number;

    _burnKozi(msg.value);

    emit SetKingdomName(msg.sender, name);
  }

  ////////////////////////////
  // View functions:
  function accumulatedStabletokensOf(address account) external view returns (uint256) {
    return _accumulatedStabletokensByAddress[account];
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  function loyaltyOf(address account) external view returns (uint256) {
    return _loyaltyByCycleAndAddress[account][currentCycle.number];
  }

  function loyaltyByCycleOf(address account, uint256 cycle) external view returns (uint256) {
    return _loyaltyByCycleAndAddress[account][cycle];
  }

  function lockedUntilOf(address account) external view returns (uint256) {
    return _lockedUntil[account];
  }

  function kingdomNamesOf(address[] memory accounts) external view returns (string[] memory) {
    string[] memory names = new string[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i++) {
      names[i] = kingdomNames[accounts[i]];
    }
    return names;
  }

  ////////////////////////////
  // Updater Functions
  function gainLoyalty(address account, uint256 loyalty, uint256 stabletokens) external onlyRole(UPDATER_ROLE) {
    _gainLoyalty(account, loyalty, stabletokens);
  }

  function spendLoyalty(address account, uint256 amount) external onlyRole(UPDATER_ROLE) {
    _spendLoyalty(account, amount);
  }

  function forfeitLoyalty(address account, bytes32 associatedTx) external onlyRole(UPDATER_ROLE) {
    uint256 _loyalty = _loyaltyByCycleAndAddress[account][currentCycle.number];
    _loyaltyByCycleAndAddress[account][currentCycle.number] = 0;

    emit ForfeitLoyalty(account, associatedTx, _loyalty);
  }

  ////////////////////////////
  // Operator Functions
  function distribute(
    address[] memory accounts,
    uint256 totalAmount
  ) external mutex whenNotPaused onlyRole(UPDATER_ROLE) {
    // make sure the list of accounts is not empty
    require(accounts.length > 0, "KingdomNobles: no accounts");

    // make sure the list of accounts is not too long
    require(accounts.length <= 25, "KingdomNobles: too many accounts");

    // transfer the totalAmount from msg.sender to this contract
    require(stableToken.transferFrom(msg.sender, address(this), totalAmount), "KingdomNobles: transfer failed");

    // if the current cycle is over, start a new one
    if (block.number >= currentCycle.endBlock) {
      _startNewCycle();
    }

    // update the accumulatedPayouts
    accumulatedPayouts += totalAmount;

    uint256 spentAmount = 0;
    for (uint256 i = 0; i < accounts.length; i++) {
      if (kingdomNameSetAtBlock[accounts[i]] == 0) {
        _missRewards(accounts[i], (totalAmount * _rewardsByPosition[i + 1]) / 1000);
        continue;
      } else {
        uint256 reward = (totalAmount * _rewardsByPosition[i + 1]) / 1000;
        _gainLoyalty(accounts[i], 25 - i, reward);
        spentAmount += reward;
      }
    }

    // make sure we didn't spend more than the totalAmount
    require(spentAmount <= totalAmount, "KingdomNobles: spent too much");

    // add the remaining amount back to the treasury
    uint256 remainingAmount = totalAmount - spentAmount;
    if (remainingAmount > 0) {
      require(stableToken.transfer(treasury, remainingAmount), "KingdomNobles: transfer failed");
    }

    emit DistributeRewards(accounts, spentAmount, accumulatedPayouts);
  }

  ////////////////////////////
  // Internal functions
  function _gainLoyalty(address account, uint256 loyalty, uint256 stabletokens) private {
    _loyaltyByCycleAndAddress[account][currentCycle.number] += loyalty;

    if (stabletokens != 0) {
      _balances[account] += stabletokens;
      _accumulatedStabletokensByAddress[account] += stabletokens;
    }

    emit GainLoyalty(account, loyalty, stabletokens);
  }

  function _spendLoyalty(address account, uint256 amount) private {
    require(_loyaltyByCycleAndAddress[account][currentCycle.number] >= amount, "KingdomNobles: not enough loyalty");

    _loyaltyByCycleAndAddress[account][currentCycle.number] -= amount;

    emit SpendLoyalty(account, amount);
  }

  function _missRewards(address account, uint256 amount) private {
    emit MissedRewards(account, amount);
  }

  function _burnKozi(uint256 amount) private {
    // burn it
    payable(address(0)).transfer(amount);

    // update the totalBurnedKozi
    totalBurnedKozi += amount;

    emit BurnKozi(msg.sender, amount, totalBurnedKozi);
  }
}
