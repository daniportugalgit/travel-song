// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IResult.sol";

contract ResultCore {
  IResult private _coreA = IResult(0x0025239389B524762c97842Cc4e1648a095a8E40);
  IResult private _coreB = IResult(0x69637a2085B628480447B0c898d3dea28A5C36B1);
  IResult private _coreC = IResult(0x9D5c6721cf602c5EAeAcfA5dF7bDfbe96A69F88C);
  IResult private _coreD = IResult(0x5d9544D59041BB074D97e12a7E969991A5Cf322a);

  uint256 private _chainId = 39916801;

  address private _owner;
  mapping(address => bool) private _whitelist;

  modifier onlyWhitelisted() {
    require(_whitelist[msg.sender], "caller is not whitelisted");
    _;
  }

  constructor(address coreA, address coreB, address coreC, address coreD) {
    _coreA = IResult(coreA);
    _coreB = IResult(coreB);
    _coreC = IResult(coreC);
    _coreD = IResult(coreD);

    _owner = msg.sender;
  }

  function setInWhitelist(address address_, bool value) external {
    require(msg.sender == _owner, "caller is not the owner");
    _whitelist[address_] = value;
  }

  function geta(address to, uint256 max, uint256 seedA, uint256 seedB) external view onlyWhitelisted returns (uint256) {
    return (uint256(
      keccak256(abi.encodePacked(to, block.number + seedB + seedA + max, seedA + _chainId, block.timestamp))
    ) % 100);
  }

  function get(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return
      (uint256(keccak256(abi.encodePacked(block.number, to, seedB + seedA, seedA + block.number))) % (max - min + 1)) +
      min;
  }

  function getb(address to, uint256 seedA, uint256 seedB) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(seedB + seedA, block.number, to, block.timestamp, seedA))) % 100);
  }

  function getc(uint256 seedA, uint256 seedB) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(block.number + seedB + seedA, block.timestamp, seedA))) % 100);
  }
}
