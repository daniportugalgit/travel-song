// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../interfaces/IBkPlayerBonus.sol";

contract BkQuestRewardsCalculator is AdministrableUpgradable2024 {
  IBkPlayerBonus public playerBonus;

  function initialize(address _operator, address _blocklist, address _playerBonus) public initializer {
    __Administrable_init(_operator, _blocklist);

    playerBonus = IBkPlayerBonus(_playerBonus);
  }

  struct MultiplierRequest {
    uint256 squadType;
    uint256 numberOfNtfs;
    uint256 raritySum;
    uint256 synergyBonus;
    uint256 traits;
    uint256 collections;
    uint256 durationInBlocks;
    address account;
  }

  function getBaseMultipliers(MultiplierRequest memory req) external view returns (uint256[] memory) {
    (uint256 globalBonus, uint256 fortuneLevel, uint256[] memory masteries) = playerBonus.bonusWithFortuneAndMasteryOf(
      req.account
    );

    masteries = masteries.length == 0 ? new uint256[](6) : masteries;

    uint256[] memory multipliers = new uint256[](6);
    multipliers[0] = getBctMultiplier(req.squadType, req.raritySum, globalBonus, req.durationInBlocks, masteries[0]);
    multipliers[1] = getEbctMultiplier(
      req.squadType,
      req.numberOfNtfs,
      globalBonus,
      req.durationInBlocks,
      masteries[1]
    );
    multipliers[2] = getBlMultiplier(
      req.squadType,
      req.synergyBonus,
      req.traits,
      globalBonus,
      req.durationInBlocks,
      masteries[2]
    );
    multipliers[3] = getAlMultiplier(
      req.squadType,
      req.synergyBonus,
      req.traits,
      globalBonus,
      req.durationInBlocks,
      masteries[3]
    );
    multipliers[4] = getNutsMultiplier(req.collections, globalBonus, req.durationInBlocks, masteries[4]);
    multipliers[5] = getEvosMultiplier(fortuneLevel, globalBonus, req.durationInBlocks, masteries[5]);

    return multipliers;
  }

  function getBctMultiplier(
    uint256 squadType,
    uint256 raritySum,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // Mandatory Pure squads farm 20% more BCT
    if (squadType != 6) {
      multiplier += 20;
    }

    // The higher the sum of the NFTs' rarities, the more BCT they farm (up to 30%) [max: 6 nfts * 5 rarities = 30]
    multiplier += raritySum;

    return multiplier * durationInBlocks;
  }

  function getEbctMultiplier(
    uint256 squadType,
    uint256 numberOfNtfs,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // Mandatory Pure squads farm 30% more eBCT
    if (squadType != 6) {
      multiplier += 30;
    }

    // The more NFTs there are in the squad, the more eBCT they farm (up to 60%)
    if (numberOfNtfs > 1) {
      multiplier += numberOfNtfs * 10;
    }

    return multiplier * durationInBlocks;
  }

  function getBlMultiplier(
    uint256 squadType,
    uint256 synergyBonus,
    uint256 traits,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // Mandatory Pure squads farm 100% more Loot
    if (squadType != 6) {
      multiplier += 100;
    }

    // The higher the synergy bonus, the more Loot they farm [max synergy bonus: 1440] (up to 144%)
    multiplier += synergyBonus / 10;

    // The higher the number of traits, the more Loot they farm [max traits: 18] (up to 90%)
    multiplier += traits * 5;

    return multiplier * durationInBlocks;
  }

  function getAlMultiplier(
    uint256 squadType,
    uint256 synergyBonus,
    uint256 traits,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // Mandatory Pure squads farm 100% more Loot
    if (squadType != 6) {
      multiplier += 100;
    }

    // The higher the synergy bonus, the more Loot they farm [max synergy bonus: 1440] (up to 144%)
    multiplier += synergyBonus / 10;

    // The higher the number of traits, the more Loot they farm [max traits: 18] (up to 90%)
    multiplier += traits * 5;

    return multiplier * durationInBlocks;
  }

  function getNutsMultiplier(
    uint256 collections,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // The more collection NFTs in the squad, the more nuts (up to +600%) [max collections: 6]
    // They don't have to belong to the same collection
    multiplier += collections * 20;

    return multiplier * durationInBlocks;
  }

  function getEvosMultiplier(
    uint256 fortuneLevel,
    uint256 globalBonus,
    uint256 durationInBlocks,
    uint256 mastery
  ) public pure returns (uint256) {
    uint256 multiplier = 100 + globalBonus + mastery;

    // The higher the fortune level, the more Evos they farm (up to 99%)
    multiplier += fortuneLevel;

    return multiplier * durationInBlocks;
  }
}
