// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./standard/AdminUpBridgeERC20.sol";

contract ExternalERC20 is AdminUpBridgeERC20 {
  function initialize(
    string memory _name,
    string memory _symbol,
    address _operator,
    uint256 _totalSupply,
    address _blocklistAddress,
    uint256 _originChainId
  ) public initializer {
    __AdminUpBridgeERC20_init(_name, _symbol, _operator, _totalSupply, _blocklistAddress, _originChainId);
  }

  function bridgeToChain(
    uint256 toChainId,
    address fromAddress,
    address toAddress,
    uint256 amount
  ) public override onlyRole(BRIDGE_ROLE) whenNotPaused nonReentrant {
    require(toChainId == originChainId, "Only back to origin chain");

    // we burn the metatokens
    _burn(fromAddress, amount);

    emit BridgeToChain(toChainId, fromAddress, toAddress, amount);
  }

  function bridgeFromChain(
    uint256 fromChainId,
    address fromAddress,
    address toAddress,
    uint256 amount
  ) public override onlyRole(BRIDGE_ROLE) whenNotPaused nonReentrant {
    require(fromChainId == originChainId, "Only from origin chain");

    // we mint the metatokens
    _mint(toAddress, amount);

    emit BridgeFromChain(fromChainId, fromAddress, toAddress, amount);
  }
}
