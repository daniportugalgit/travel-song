// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../erc20/interfaces/IBkERC20.sol";
import "../interfaces/IBkPlayerBonus.sol";
import "../interfaces/IBkFarm.sol";
import "../interfaces/IBkPlayer.sol";

contract BkStasher is AdministrableUpgradable2024 {
  IBkERC20 public bct;
  IBkPlayerBonus public playerBonus;
  IBkFarm public farm;

  mapping(address => uint256) public stashedAt;
  mapping(address => uint256) public balances;
  mapping(uint256 => uint256) public levelToAmount;
  mapping(address => bool) public hasMigrated;
  mapping(address => bool) public hasInteractedAfterMigration;
  mapping(address => uint256) private _levelOf;
  uint256 maxLevel;
  uint256 cooldownInBlocks;

  struct LevelSet {
    uint256 amount;
    uint256 level;
  }

  event Stashed(address account, uint256 amount);
  event Unstashed(address account, uint256 amount);

  // UPGRADE VARIABLES:
  mapping(address => uint256) public withdrawnAt; // players can withdraw up to 2k BCT every month, and only once per month. This is the timestamp of the last withdrawal.

  function initialize(address _operator, address _blocklist, address _bct) public initializer {
    __Administrable_init(_operator, _blocklist);

    bct = IBkERC20(_bct);

    maxLevel = 10;
    cooldownInBlocks = 8640 * 180; // 180 days
  }

  function stash(uint256 amount, bool fromFarm) external whenNotPaused {
    hasInteractedAfterMigration[msg.sender] = true;

    if (fromFarm) {
      require(true == false, "DISABLED");
      _stashFromFarmFor(msg.sender, amount);
    } else {
      _stashFor(msg.sender, amount);
    }

    _giveBonusForStashing(msg.sender, amount);
  }

  function unstash() external whenNotPaused {
    require(block.number - withdrawnAt[msg.sender] >= 8640 * 30, "TOO_EARLY"); // can only withdraw once a month

    if (stashedAt[msg.sender] > 0) {
      require(block.number - stashedAt[msg.sender] >= cooldownInBlocks, "COOLDOWN");
    }

    _unstashFor(msg.sender);
  }

  function unstashFor(address account) external onlyRole(OPERATOR_ROLE) whenNotPaused {
    _unstashFor(account);
  }

  function migrateStash(address account, uint256 amount) external onlyRole(UPDATER_ROLE) {
    require(hasMigrated[account] == false, "Already migrated");
    hasMigrated[account] = true;

    _addToStash(account, amount);
  }

  ///////////////////////////////////
  // Private

  function _stashFor(address to, uint256 amount) private {
    bct.transferFrom(to, address(this), amount);
    _addToStash(to, amount);
  }

  function _giveBonusForStashing(address account, uint256 amount) private {
    // always give 40% bonus:
    uint256 bonus = (amount * 40) / 100;

    // and no resource bonus:
    uint256[] memory bonusResourceCents = new uint256[](0);

    farm.addTo(account, bonus, bonusResourceCents);
  }

  function _stashFromFarmFor(address to, uint256 amount) private {
    farm.spendBctFrom(to, amount, false); // will revert if going negative

    // now transfer from the farm to this contract
    bct.transferFrom(address(farm), address(this), amount);

    _addToStash(to, amount);
  }

  function _addToStash(address to, uint256 amount) private {
    require(amount > 0, "zero");

    balances[to] += amount;
    stashedAt[to] = block.number;

    setLevelOf(to);

    playerBonus.setStashOf(to, _levelOf[to]);

    emit Stashed(to, amount);
  }

  /**
   * @dev will unstash 2k BCT for the player if it can;
   *      less than that if there's not enough BCT in the stash.
   * @param to The address to unstash for
   */
  function _unstashFor(address to) private {
    require(balances[to] > 0, "NO_BALANCE");

    uint256 amount;
    if (balances[to] >= 2000 ether) {
      amount = 2000 ether;
    } else {
      amount = balances[to];
    }

    withdrawnAt[to] = block.number;

    balances[to] = balances[to] - amount;

    setLevelOf(to);
    playerBonus.setStashOf(to, _levelOf[to]);

    bct.transfer(to, amount);

    emit Unstashed(to, amount);
  }

  function balanceOf(address account) external view returns (uint256) {
    return balances[account];
  }

  function setLevelOf(address account) public {
    if (balances[account] < levelToAmount[1]) {
      _levelOf[account] = 0;
      return;
    }

    uint256 level = 0;
    for (uint256 i = 1; i <= maxLevel; i++) {
      if (balances[account] >= levelToAmount[i]) {
        level = i;
      } else {
        break;
      }
    }

    _levelOf[account] = level;
  }

  function levelOf(address account) public view returns (uint256) {
    return _levelOf[account];
  }

  function balanceAndLevelOf(address account) external view returns (uint256, uint256) {
    return (balances[account], levelOf(account));
  }

  function setLevels(LevelSet[] calldata _levelSet) external onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < _levelSet.length; i++) {
      levelToAmount[_levelSet[i].level] = _levelSet[i].amount;
    }
  }

  function setCooldownInBlocks(uint256 blocks) public onlyRole(OPERATOR_ROLE) {
    cooldownInBlocks = blocks;
  }

  function setMaxLevel(uint256 _maxLevel) public onlyRole(OPERATOR_ROLE) {
    maxLevel = _maxLevel;
  }

  function setPlayerBonusAndFarm(address _playerBonus, address _farm) public onlyRole(OPERATOR_ROLE) {
    playerBonus = IBkPlayerBonus(_playerBonus);
    farm = IBkFarm(_farm);
  }
}
