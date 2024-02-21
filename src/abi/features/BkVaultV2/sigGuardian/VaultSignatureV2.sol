// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VaultSignatureV2 {
  uint256 private constant MAGIC_NUMBER = 9979200;

  struct ClaimData {
    address guardianAddress;
    address playerAddress;
    uint256 eBct;
    uint256[] resources;
    uint256 nonce;
  }

  function _getClaimID(ClaimData memory claimData) internal pure virtual returns (uint256) {
    return
      uint256(
        keccak256(
          abi.encode(
            claimData.guardianAddress,
            claimData.playerAddress,
            claimData.eBct,
            claimData.resources,
            claimData.nonce,
            MAGIC_NUMBER, // magic here
            claimData.nonce // magic here
          )
        )
      );
  }
}
