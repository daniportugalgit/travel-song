// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IBkERC20 {
  function decimals() external view returns (uint8);

  function balanceOf(address owner) external view returns (uint256 balance);

  function totalSupply() external view returns (uint256);

  function allowance(address owner, address spender) external view returns (uint256);

  function mint(address to, uint256 amount) external;

  function burn(uint256 amount) external;

  function burnFrom(address account, uint256 amount) external;

  function transfer(address recipient, uint256 amount) external returns (bool);

  function approve(address to, uint256 tokenId) external;

  function transferFrom(address from, address to, uint256 value) external returns (bool);

  function bridgeToChain(uint256 toChainId, address fromAddress, address toAddress, uint256 amount) external;

  function bridgeFromChain(uint256 fromChainId, address fromAddress, address toAddress, uint256 amount) external;
}
