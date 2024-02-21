// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

interface ERC20 {
  function transfer(address to, uint256 amount) external;

  function transferFrom(address from, address to, uint256 amount) external;
}

contract BkTimelock is AdministrableUpgradable2024 {
  address private constant KOZIKA = 0x6F165B30ee4bFc9565E977Ae252E4110624ab147;

  uint256 public unlockBlock;
  mapping(address => uint256) public balances;

  ERC20 public bct;

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    bct = ERC20(0x6c93500E8BEf8C806cF5228A352F8C0Af439370f);
  }

  function deposit(uint256 amount) public {
    require(msg.sender == KOZIKA, "Only KOZIKA can deposit");

    balances[msg.sender] += amount;
    unlockBlock = block.number + 8640000; // 10 months

    bct.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint256 amount) public {
    require(msg.sender == KOZIKA, "Only KOZIKA can withdraw");
    require(block.number >= unlockBlock, "Tokens are locked");

    balances[msg.sender] -= amount;

    bct.transfer(msg.sender, amount);
  }
}
