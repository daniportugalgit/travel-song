// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IBkChar.sol";

library EasyBkChar {
  function getAttribute(IBkChar.BkChar memory _char, IBkChar.ATTRIBUTE _attribute) internal pure returns (uint256) {
    return _char.attributes[uint256(_attribute)];
  }

  function species(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.SPECIES);
    return _char.attributes[0];
  }

  function rarity(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.RARITY);
    return _char.attributes[1];
  }

  function rank(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.RANK);
    return _char.attributes[2];
  }

  function agility(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.AGILITY);
    return _char.attributes[3];
  }

  function nuts(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.NUTS);
    return _char.attributes[4];
  }

  function evos(IBkChar.BkChar memory _char) internal pure returns (uint256) {
    //return getAttribute(_char, IBkChar.ATTRIBUTE.EVOS);
    return _char.attributes[5];
  }
}
