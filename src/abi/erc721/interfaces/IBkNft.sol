// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IBkChar.sol";

interface IBkNft {
  function totalSupply() external view returns (uint256);

  function ownerOf(uint256 tokenId) external view returns (address);

  function tokensOfOwner(address _owner) external view returns (uint256[] memory);

  function nftsOfOwner(address _owner) external view returns (IBkChar.BkChar[] memory);

  function getNft(uint256 tokenId) external view returns (IBkChar.BkChar memory);

  function getNfts(uint256[] memory tokenIds) external view returns (IBkChar.BkChar[] memory);

  function tokenURI(uint256 tokenId) external view returns (string memory);

  function getApproved(uint256 tokenId) external view returns (address);

  function isApprovedForAll(address owner, address operator) external view returns (bool);

  function isOnQuest(uint256 tokenId) external view returns (bool);

  function isInSquad(uint256 tokenId) external view returns (bool);

  function squadOf(uint256 tokenId) external view returns (uint256);

  function farmPerBlockOf(uint256 tokenId) external view returns (uint256);

  function attributeOf(uint256 tokenId, uint256 attribute) external view returns (uint256);

  function attributesOf(uint256 tokenId) external view returns (uint256[] memory);

  function attributesAndSkillsOf(uint256 tokenId) external view returns (uint256[] memory, uint256[] memory);

  function traitsOf(uint256 tokenId) external view returns (uint256[] memory);

  function collectionOf(uint256 tokenId) external view returns (uint256);

  function transferFrom(address from, address to, uint256 tokenId) external;

  function safeTransferFrom(address from, address to, uint256 tokenId) external;

  function setSquad(uint256 tokenId, uint256 squadId) external;

  function setBaseFarm(uint256 tokenId, uint256 newBaseFarm) external;

  function setSkills(uint256 tokenId, uint256[] memory _skills) external;

  function setAttributesAndSkills(uint256 tokenId, uint256[] memory attributes, uint256[] memory skills) external;

  function setAttributesAndBaseFarm(uint256 tokenId, uint256[] memory attributes, uint256 newBaseFarm) external;

  function setAttributesBaseFarmAndSkills(
    uint256 tokenId,
    uint256[] memory attributes,
    uint256 newBaseFarm,
    uint256[] memory skills
  ) external;

  function mint(address to, IBkChar.BkChar memory character) external;

  function migrateToPlayer(address to, IBkChar.BkChar[] memory characters) external;

  function migrate(IBkChar.BkChar[] memory characters) external;

  function setAttribute(uint256 tokenId, uint256 attribute, uint256 value) external;

  function setAttributes(uint256 tokenId, uint256[] memory attributes) external;

  function setCollection(uint256 tokenId, uint256 newCollection) external;

  function setTraits(uint256 tokenId, uint256[] memory traits) external;

  function setNameAndImage(uint256 tokenId, string memory newName, string memory newImageUrl) external;

  function burnFrom(address account, uint256 tokenId) external;

  function nextNftId() external view returns (uint256);

  function setIsDead(uint256 tokenId, bool isDead) external;
}
