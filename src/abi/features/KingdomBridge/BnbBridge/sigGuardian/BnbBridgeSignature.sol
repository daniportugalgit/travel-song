// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract BnbBridgeSignature {
  uint256 private constant MAGIC_NUMBER = 19958400;

  struct ClaimData {
    address guardianAddress;
    address playerAddress;
    uint256 nonce;
    uint256 stabletokensOut;
    bytes32 depositHash;
  }

  function _getClaimID(ClaimData memory claimData) internal pure virtual returns (uint256) {
    return
      uint256(
        keccak256(
          abi.encode(
            claimData.guardianAddress,
            claimData.playerAddress,
            claimData.nonce,
            claimData.stabletokensOut,
            claimData.depositHash,
            MAGIC_NUMBER, // magic here
            claimData.nonce // magic here
          )
        )
      );
  }
}
