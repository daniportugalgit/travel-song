// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./standard/AdminUpBridgeERC20.sol";

contract NativeERC20 is AdminUpBridgeERC20 {
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
    // We store the tokens in this contract until someone claims them by means of bridgeFromChain
    _transfer(fromAddress, address(this), amount);

    emit BridgeToChain(toChainId, fromAddress, toAddress, amount);
  }

  function bridgeFromChain(
    uint256 fromChainId,
    address fromAddress,
    address toAddress,
    uint256 amount
  ) public override onlyRole(BRIDGE_ROLE) whenNotPaused nonReentrant {
    // We transfer the tokens from this contract to the recipient
    _transfer(address(this), toAddress, amount);

    emit BridgeFromChain(fromChainId, fromAddress, toAddress, amount);
  }
}
