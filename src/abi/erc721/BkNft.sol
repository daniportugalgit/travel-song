// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./standard/AdminUpgradeableERC721.sol";
import "./interfaces/IBkChar.sol";

interface FarmSimplified {
  function recalculateSquadFarming(uint256 squadId) external;

  function isSquadOnQuest(uint256 squadIndex) external view returns (bool);
}

contract BkNft is AdminUpgradeableERC721 {
  bytes32 private constant UPDATER_ROLE = keccak256("UPDATER_ROLE"); // contracts that can change the properties of a BkChar
  uint256 private constant DEFAULT_MIN_BASE_FARM = 200 * 1E9; // 200 gwei
  uint256 private constant MAX_AGILITY = 5;
  uint256 private constant AGILITY_CEILING = 6;

  FarmSimplified public farm;

  /// @notice NFTs minted by this contract, along with their metadata
  mapping(uint256 => IBkChar.BkChar) public bkChars;

  /// @notice The rarity factor for each rarity level
  mapping(uint256 => uint256) public rarityAndTypeFactor;

  function initialize(
    string memory _name,
    string memory _symbol,
    string memory _baseTokenURI,
    address _operator,
    address _blocklistAddress
  ) public initializer {
    __AdminUpgradeableERC721_init(_name, _symbol, _baseTokenURI, _operator, _blocklistAddress);

    rarityAndTypeFactor[1] = 1; // Common
    for (uint256 i = 1; i < 10; i++) {
      // Up to rarity 10, (1023 as multiplier is the max value)
      rarityAndTypeFactor[i + 1] = 2 ** (i + 1) - 1;
    }
  }

  function getNft(uint256 tokenId) public view returns (IBkChar.BkChar memory) {
    return bkChars[tokenId];
  }

  function getNfts(uint256[] memory tokenIds) public view returns (IBkChar.BkChar[] memory) {
    IBkChar.BkChar[] memory nfts = new IBkChar.BkChar[](tokenIds.length);

    for (uint i = 0; i < tokenIds.length; i++) {
      nfts[i] = bkChars[tokenIds[i]];
    }

    return nfts;
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    return bkChars[tokenId].imageUrl;
  }

  function squadOf(uint256 tokenId) external view returns (uint256) {
    return bkChars[tokenId].squadId;
  }

  function farmPerBlockOf(uint256 tokenId) external view returns (uint256) {
    return bkChars[tokenId].farmPerBlock;
  }

  // attribute is an index of the IBkChar.ATTRIBUTE enum
  function attributeOf(uint256 tokenId, uint256 attribute) external view returns (uint256) {
    return bkChars[tokenId].attributes[attribute];
  }

  function attributesOf(uint256 tokenId) external view returns (uint256[] memory) {
    return bkChars[tokenId].attributes;
  }

  function attributesAndSkillsOf(uint256 tokenId) external view returns (uint256[] memory, uint256[] memory) {
    return (bkChars[tokenId].attributes, bkChars[tokenId].skills);
  }

  function traitsOf(uint256 tokenId) external view returns (uint256[] memory) {
    return bkChars[tokenId].traits;
  }

  function nftsOfOwner(address _owner) external view returns (IBkChar.BkChar[] memory) {
    uint256 tokenCount = balanceOf(_owner);
    IBkChar.BkChar[] memory nfts = new IBkChar.BkChar[](tokenCount);
    for (uint256 i = 0; i < tokenCount; i++) {
      nfts[i] = getNft(tokenOfOwnerByIndex(_owner, i));
    }

    return nfts;
  }

  function isOnQuest(uint256 tokenId) public view returns (bool) {
    if (bkChars[tokenId].squadId == 0) return false;

    return farm.isSquadOnQuest(bkChars[tokenId].squadId);
  }

  function isInSquad(uint256 tokenId) public view returns (bool) {
    return (bkChars[tokenId].squadId != 0);
  }

  function collectionOf(uint256 tokenId) external view returns (uint256) {
    return bkChars[tokenId].collection;
  }

  /*
  struct BkChar {
    uint256 id; // the NFT ID
    string name; // is an empty string up until the owner sets it
    string imageUrl; // is an empty string up until the owner sets it
    address currentOwner; // the current owner
    uint256 squadId; // the squad ID this NFT is in
    uint256 collection; // the collection this NFT belongs to
    uint256 baseFarm; // how many Weis of BCT this NFT will generate per cycle
    uint256 farmPerBlock; // the final farm per block
    uint256[] attributes; // species, rarity, rank, agility, nuts, evos (not greater than 255)
    uint256[] traits; // from 0 to 3 traits, that are numbers from 1 to 50+ (not greater than 255)
    uint256[] skills; // multipliers for the farming of specific kinds of resources (not greater than 255)
    bool isDead; // whether the NFT is dead or not
  }
  */
  function migrateToPlayer(address to, IBkChar.BkChar[] memory characters) public onlyRole(MINTER_ROLE) {
    uint256 tempId = nextNftId;
    for (uint256 i = 0; i < characters.length; i++) {
      _newBkChar(to, characters[i], tempId + i);
    }

    _doMintMany(to, characters.length);
  }

  function migrate(IBkChar.BkChar[] memory characters) public onlyRole(MINTER_ROLE) {
    uint256 tempId = nextNftId;
    address[] memory owners = new address[](characters.length);
    for (uint256 i = 0; i < characters.length; i++) {
      _newBkChar(characters[i].currentOwner, characters[i], tempId + i);
      owners[i] = characters[i].currentOwner;
    }

    _doMintForMany(owners);
  }

  function burnFrom(address account, uint256 tokenId) external override {
    require(ownerOf(tokenId) == account, "owner");

    _burn(tokenId);

    // mark as dead:
    bkChars[tokenId].isDead = true;
  }

  function setAttribute(uint256 tokenId, uint256 attribute, uint256 value) public onlyRole(UPDATER_ROLE) {
    require(!isOnQuest(tokenId), "onQ");

    bkChars[tokenId].attributes[attribute] = value;

    _updateFarmPerBlock(tokenId);
  }

  function setAttributes(uint256 tokenId, uint256[] memory attributes) public onlyRole(UPDATER_ROLE) {
    require(!isOnQuest(tokenId), "onQ");

    bkChars[tokenId].attributes = attributes;

    _updateFarmPerBlock(tokenId);
  }

  function setCollection(uint256 tokenId, uint256 newCollection) public onlyRole(UPDATER_ROLE) {
    require(!isInSquad(tokenId), "inSquad");

    bkChars[tokenId].collection = newCollection;
  }

  function setTraits(uint256 tokenId, uint256[] memory traits) public onlyRole(UPDATER_ROLE) {
    require(!isOnQuest(tokenId), "onQ");

    bkChars[tokenId].traits = traits;

    _updateSquadFarming(tokenId);
  }

  function setNameAndImage(
    uint256 tokenId,
    string memory newName,
    string memory newImageUrl
  ) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].name = newName;
    bkChars[tokenId].imageUrl = newImageUrl;
  }

  function setSquad(uint256 tokenId, uint256 squadId) external onlyRole(UPDATER_ROLE) {
    require(bkChars[tokenId].squadId == 0 || squadId == 0, "inSquad"); // cannot move from a squad to another
    bkChars[tokenId].squadId = squadId;
  }

  function setBaseFarm(uint256 tokenId, uint256 newBaseFarm) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].baseFarm = newBaseFarm;

    _updateFarmPerBlock(tokenId);
  }

  function setSkills(uint256 tokenId, uint256[] memory _skills) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].skills = _skills;
  }

  function setAttributesAndSkills(
    uint256 tokenId,
    uint256[] memory attributes,
    uint256[] memory skills
  ) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].attributes = attributes;
    bkChars[tokenId].skills = skills;

    _updateFarmPerBlock(tokenId);
  }

  function setAttributesAndBaseFarm(
    uint256 tokenId,
    uint256[] memory attributes,
    uint256 newBaseFarm
  ) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].attributes = attributes;
    bkChars[tokenId].baseFarm = newBaseFarm;

    _updateFarmPerBlock(tokenId);
  }

  function setAttributesBaseFarmAndSkills(
    uint256 tokenId,
    uint256[] memory attributes,
    uint256 newBaseFarm,
    uint256[] memory skills
  ) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].attributes = attributes;
    bkChars[tokenId].baseFarm = newBaseFarm;
    bkChars[tokenId].skills = skills;

    _updateFarmPerBlock(tokenId);
  }

  function setIsDead(uint256 tokenId, bool isDead) external onlyRole(UPDATER_ROLE) {
    bkChars[tokenId].isDead = isDead;
  }

  function mint(address to, IBkChar.BkChar memory character) external onlyRole(UPDATER_ROLE) {
    _newBkChar(to, character, nextNftId);
    _doMint(to);
  }

  //////////////////////////
  // Internal functions

  function _newBkChar(address to, IBkChar.BkChar memory character, uint256 _id) private {
    if (character.baseFarm == 0) {
      character.baseFarm = _getBaseFarm(character.attributes[0], character.attributes[1]);
    }

    bkChars[_id] = IBkChar.BkChar({
      id: _id,
      name: character.name,
      imageUrl: character.imageUrl,
      currentOwner: to,
      squadId: 0,
      collection: character.collection,
      baseFarm: character.baseFarm,
      farmPerBlock: 0,
      attributes: character.attributes,
      traits: character.traits,
      skills: character.skills,
      isDead: false
    });

    bkChars[_id].farmPerBlock = _calculateFarmPerBlock(
      character.baseFarm,
      character.attributes[2], // rank
      character.attributes[3] // agility
    );
  }

  function _updateSquadFarming(uint256 tokenId) internal {
    if (bkChars[tokenId].squadId != 0) {
      farm.recalculateSquadFarming(bkChars[tokenId].squadId);
    }
  }

  // Farm per block without rank and synergy
  function _getBaseFarm(uint256 type_, uint256 rarity) private view returns (uint256) {
    return DEFAULT_MIN_BASE_FARM * rarityAndTypeFactor[rarity] * rarityAndTypeFactor[type_];
  }

  function _updateFarmPerBlock(uint256 tokenId) internal {
    bkChars[tokenId].farmPerBlock = _calculateFarmPerBlock(tokenId);
    _updateSquadFarming(tokenId);
  }

  // Farm per block with rank and agility
  function _calculateFarmPerBlock(uint256 tokenId) internal view returns (uint256) {
    IBkChar.BkChar memory bkChar = bkChars[tokenId];

    return
      _calculateFarmPerBlock(
        bkChar.baseFarm,
        bkChar.attributes[uint256(IBkChar.ATTRIBUTE.RANK)],
        bkChar.attributes[uint256(IBkChar.ATTRIBUTE.AGILITY)]
      );
  }

  // Overload with all params
  function _calculateFarmPerBlock(uint256 baseFarm, uint256 rank, uint256 agility) internal pure returns (uint256) {
    return baseFarm + ((baseFarm * rank) / 10) / (AGILITY_CEILING - agility);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal virtual override {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);

    require(bkChars[tokenId].squadId == 0, "inSquad");
    require(!bkChars[tokenId].isDead, "dead");

    // set the new owner in the character:
    bkChars[tokenId].currentOwner = to;
  }

  //////////////////////////
  // OPERATOR functions
  function setFarm(address _farm) external onlyRole(OPERATOR_ROLE) {
    farm = FarmSimplified(_farm);
  }
}
