// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./AdminUpgradeableERC20.sol";

abstract contract AdminUpBridgeERC20 is AdminUpgradeableERC20 {
  bytes32 internal constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

  uint256 public originChainId;

  event BridgeToChain(
    uint256 indexed toChainId,
    address indexed fromAddress,
    address indexed toAddress,
    uint256 amount
  );

  event BridgeFromChain(
    uint256 indexed fromChainId,
    address indexed fromAddress,
    address indexed toAddress,
    uint256 amount
  );

  function __AdminUpBridgeERC20_init(
    string memory _name,
    string memory _symbol,
    address _operator,
    uint256 _totalSupply,
    address _blocklistAddress,
    uint256 _originChainId
  ) public onlyInitializing {
    __AdminUpgradeableERC20_init(_name, _symbol, _operator, _totalSupply, _blocklistAddress);

    originChainId = _originChainId;
  }

  function bridgeToChain(uint256 toChainId, address fromAddress, address toAddress, uint256 amount) external virtual {}

  function bridgeFromChain(
    uint256 fromChainId,
    address fromAddress,
    address toAddress,
    uint256 amount
  ) external virtual {}
}
