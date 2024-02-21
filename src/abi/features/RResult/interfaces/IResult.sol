// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IResult {
  function get(address a, uint256 b, uint256 c, uint256 d, uint256 e) external view returns (uint256);
}
