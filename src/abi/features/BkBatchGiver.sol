// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../interfaces/IBkFarm.sol";

contract BkBatchGiver is AdministrableUpgradable2024 {
  IBkFarm public farm;

  function initialize(address _operator, address _blocklist, address _farm) public initializer {
    __Administrable_init(_operator, _blocklist);

    farm = IBkFarm(_farm);
  }

  function addTo(
    address[] memory playerAddresses,
    uint256[] memory amount,
    uint256[] memory resources
  ) external onlyRole(OPERATOR_ROLE) {
    for (uint i = 0; i < playerAddresses.length; i++) {
      farm.addTo(playerAddresses[i], amount[i], resources);
    }
  }

  function addToMany(
    address[] memory playerAddresses,
    uint256 amount,
    uint256[] memory resources
  ) external onlyRole(OPERATOR_ROLE) {
    for (uint i = 0; i < playerAddresses.length; i++) {
      farm.addTo(playerAddresses[i], amount, resources);
    }
  }
}
