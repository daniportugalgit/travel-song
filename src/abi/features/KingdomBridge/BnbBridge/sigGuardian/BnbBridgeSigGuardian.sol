// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./BnbBridgeSignature.sol";
import "../../ECDSA.sol";

contract BnbBridgeSigGuardian is BnbBridgeSignature {
  mapping(address => bool) private _validators;
  mapping(bytes32 => bool) private _usedClaimIds;
  mapping(bytes32 => bool) private _usedDepositHashes;

  mapping(address => uint256) public nonces; // player => nonce mapping
  mapping(address => uint256) public lastNonceUpBlock; // player => last nonce update block mapping

  /**
   * @dev Information on a signature: address, r, s, and v
   */
  struct SignatureData {
    address signer;
    uint8 _v;
    bytes32 _r;
    bytes32 _s;
  }

  bool isInitialized;

  function _initSigGuardian(address initialValidator) internal {
    require(!isInitialized, "ALREADY_INITIALIZED");

    _setValidator(initialValidator, true);
    isInitialized = true;
  }

  function _validateClaim(
    bytes32 hashDigest,
    ClaimData memory claimData,
    SignatureData calldata signatureData
  ) internal {
    require(claimData.guardianAddress == address(this), "INV_GUARDIAN");
    require(_hasCorrectClaimId(hashDigest, claimData), "INV_DATA");
    require(_hasCorrectSigner(hashDigest, signatureData), "INV_SIGNER");
    require(_hasCorrectNonce(claimData.playerAddress, claimData.nonce), "INV_NONCE");
    require(!_usedClaimIds[hashDigest], "INV_CLAIM");
    require(!_usedDepositHashes[claimData.depositHash], "INV_DEPOSIT");

    _usedClaimIds[hashDigest] = true;
    _usedDepositHashes[claimData.depositHash] = true;
    lastNonceUpBlock[claimData.playerAddress] = block.number;
    nonces[claimData.playerAddress] = claimData.nonce;
  }

  function _hasCorrectClaimId(bytes32 hashDigest, ClaimData memory claimData) internal pure returns (bool) {
    uint256 claimID = _getClaimID(claimData);
    return uint256(hashDigest) == claimID;
  }

  function _hasCorrectSigner(bytes32 hashDigest, SignatureData calldata signatureData) internal view returns (bool) {
    bytes32 messageDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hashDigest));

    address actualSigner = ECDSA.recover(
      messageDigest, // messageHash
      signatureData._v,
      signatureData._r,
      signatureData._s
    );

    require(_validators[actualSigner], "INV_VALIDATOR");
    require(signatureData.signer == actualSigner, "INV_SIGNER");

    return true;
  }

  function _hasCorrectNonce(address playerAddress, uint256 nonce) internal view returns (bool) {
    require(
      lastNonceUpBlock[playerAddress] == 0 || block.number > lastNonceUpBlock[playerAddress] + 8640 * 8,
      "INV_NONCE_UPD"
    );

    return nonce == nonces[playerAddress] + 1;
  }

  function _setValidator(address validatorAddress, bool isActive) internal {
    _validators[validatorAddress] = isActive;
  }
}
