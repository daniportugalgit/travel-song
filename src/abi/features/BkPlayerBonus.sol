// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../interfaces/IBkStasher.sol";

// Upgradeable contract that calculates the bonus of a player
contract BkPlayerBonus is AdministrableUpgradable2024 {
  IBkStasher public stasher;

  struct Player {
    uint256 stash;
    uint256 mythicMints;
    uint256 item;
    uint256 special;
    uint256 fortuneLevel;
    uint256 total;
  }
  mapping(address => Player) public players;

  /* UPDATE VARIABLES */
  mapping(address => uint256[]) public masteryLevels; // [BCT,eBCT,BL,AL,NUT,EVO] :: percentage of bonus farm to that

  mapping(address => uint256) public soldOrTransferredAt; // players who have sold or transferred BCT in the last 40 days are not eligible for the mastery bonus

  function initialize(address _operator, address _blocklist, address _stasher) public initializer {
    __Administrable_init(_operator, _blocklist);

    stasher = IBkStasher(_stasher);
  }

  // to be called when a new player registers in the Farm contract
  function resetBonusOf(address account) public onlyRole(UPDATER_ROLE) {
    Player storage player = players[account];
    player.stash = stasher.levelOf(account);

    _setTotalBonusOf(account);
  }

  function _setTotalBonusOf(address account) private {
    Player storage player = players[account];
    player.total = player.stash + player.item + player.special;
  }

  // To be called when a player stashes or unstashes BCT
  function setStashOf(address account, uint256 stash) public onlyRole(UPDATER_ROLE) {
    players[account].stash = stash;
    _setTotalBonusOf(account);
  }

  // To be called when a player earns an item
  function setItemOf(address account, uint256 item) public onlyRole(UPDATER_ROLE) {
    players[account].item = item;
    _setTotalBonusOf(account);
  }

  // To be called when a player mints a mythic NFT
  function setMythicMintsOf(address account, uint256 mythicMints) public onlyRole(UPDATER_ROLE) {
    players[account].mythicMints = mythicMints;
    _setTotalBonusOf(account);
  }

  function incrementMythicsOf(address account) public onlyRole(UPDATER_ROLE) {
    players[account].mythicMints++;
    _setTotalBonusOf(account);
  }

  // To be called when a player earns or loses something special
  function setSpecialOf(address account, uint256 special) public onlyRole(UPDATER_ROLE) {
    players[account].special = special;
    _setTotalBonusOf(account);
  }

  function setFortuneLevelOf(address account, uint256 fortuneLevel) public onlyRole(UPDATER_ROLE) {
    players[account].fortuneLevel = fortuneLevel;
    _setTotalBonusOf(account);
  }

  function setMasteryLevelsOf(address account, uint256[] memory _masteryLevels) public onlyRole(UPDATER_ROLE) {
    masteryLevels[account] = _masteryLevels;
  }

  function setAllOf(
    address account,
    Player calldata playerBonus,
    uint256[] calldata _masteryLevels
  ) public onlyRole(UPDATER_ROLE) {
    players[account] = playerBonus;
    masteryLevels[account] = _masteryLevels;
    _setTotalBonusOf(account);
  }

  function setSoldOrTransferredOf(address account) public onlyRole(UPDATER_ROLE) {
    soldOrTransferredAt[account] = block.number;
  }

  function detailedBonusOf(address account) public view returns (Player memory, uint256[] memory _masteryLevels) {
    if (masteryLevels[account].length == 0 || players[account].stash < 10) {
      uint256[] memory masteries = new uint256[](6);
      return (players[account], masteries);
    }

    return (players[account], masteryLevels[account]);
  }

  function bonusOf(address account) public view returns (uint256) {
    return players[account].total;
  }

  function bonusWithFortuneOf(address account) public view returns (uint256, uint256) {
    uint256 _fortuneLevel = players[account].fortuneLevel;
    return (players[account].total, _fortuneLevel);
  }

  function bonusWithFortuneAndMasteryOf(address account) public view returns (uint256, uint256, uint256[] memory) {
    uint256 _fortuneLevel = players[account].fortuneLevel;
    if (masteryLevels[account].length == 0 || players[account].stash < 10) {
      uint256[] memory masteries = new uint256[](6);
      return (players[account].total, _fortuneLevel, masteries);
    }
    return (players[account].total, _fortuneLevel, masteryLevels[account]);
  }
}
