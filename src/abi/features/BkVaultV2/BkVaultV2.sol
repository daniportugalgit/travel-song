// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../utils/AdministrableUpgradableP20.sol";

import "./sigGuardian/VaultSigGuardianV2.sol";

interface IBkFarm {
  function addTo(address playerAddress, uint256 amount, uint256[] memory _resources) external;
}

contract BkVaultV2 is VaultSigGuardianV2, AdministrableUpgradableP20 {
  IBkFarm farm;

  event Claimed(address playerAddress, uint256 eBct, uint256[] resources);

  function initialize(address _operator, address _initialValidator) public initializer {
    __Administrable_init(_operator);
    _initSigGuardian(_initialValidator);
  }

  function claim(
    bytes32 hashDigest,
    ClaimData memory claimData,
    SignatureData calldata signatureData
  ) external whenNotPaused {
    _validateClaim(hashDigest, claimData, signatureData);
    _sendRewardsTo(claimData.playerAddress, claimData.eBct, claimData.resources);
  }

  function _sendRewardsTo(address playerAddress, uint256 eBct, uint256[] memory resources) internal {
    farm.addTo(playerAddress, eBct, resources);
    emit Claimed(playerAddress, eBct, resources);
  }

  function setValidator(address validator, bool isValid) external onlyRole(OPERATOR_ROLE) {
    _setValidator(validator, isValid);
  }

  function setContracts(address _farm) external onlyRole(OPERATOR_ROLE) {
    farm = IBkFarm(_farm);
  }
}
