// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IResult.sol";

contract RResult {
  IResult private _corea = IResult(0x5Cb2C3Ed882E37DA610f9eF5b0FA25514d7bc85B);
  IResult private _coreb = IResult(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
  IResult private _core = IResult(0x0536ec03b1A9121cd84807e6593F7A71Ae4971c5);
  IResult private _corec = IResult(0x2B90E061a517dB2BbD7E39Ef7F733Fd234B494CA);
  IResult private _cored = IResult(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);

  address private _owner;
  mapping(address => bool) private _whitelist;

  modifier onlyWhitelisted() {
    require(_whitelist[msg.sender], "caller is not whitelisted");
    _;
  }

  constructor(address corea, address coreb, address core, address corec, address cored) {
    _corea = IResult(corea);
    _coreb = IResult(coreb);
    _core = IResult(core);
    _corec = IResult(corec);
    _cored = IResult(cored);

    _owner = msg.sender;
  }

  function setInWhitelist(address address_, bool value) external {
    require(msg.sender == _owner, "caller is not the owner");
    _whitelist[address_] = value;
  }

  function get(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _core.get(to, min, max, seedA, seedB);
  }

  function geta(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(to, min, max, seedA, seedB))) % 100);
  }

  function getb(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(to, seedA, seedB, min, max))) % 100);
  }

  function getc(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(seedA, seedB, to, min, max))) % 100);
  }

  function getd(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _corea.get(to, max, min, seedA, seedB);
  }

  function gete(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _coreb.get(to, max, min, seedB, seedA);
  }

  function getf(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _cored.get(to, min, seedB, seedA, max);
  }

  function getg(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _cored.get(to, min, seedB, seedA, max);
  }

  function geth(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _corea.get(to, seedB, min, seedA, max);
  }

  function geti(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _coreb.get(to, seedB, min, seedA, max);
  }

  function getj(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _corea.get(to, min, max, seedA, seedB);
  }

  function getk(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _coreb.get(to, min, max, seedA, seedB);
  }

  function getl(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _corec.get(to, min, max, seedA, seedB);
  }

  function getm(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _cored.get(to, min, max, seedA, seedB);
  }

  function getn(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return _core.get(to, min, max, seedA, seedB);
  }

  function geto(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(to, seedB, seedA, min, max))) % 100);
  }

  function getp(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(to, seedB, seedA, max, min))) % 100);
  }

  function getq(
    address to,
    uint256 min,
    uint256 max,
    uint256 seedA,
    uint256 seedB
  ) external view onlyWhitelisted returns (uint256) {
    return (uint256(keccak256(abi.encodePacked(to, seedB, max, min, seedA))) % 100);
  }
}
