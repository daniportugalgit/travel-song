// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../interfaces/IBkDnaManager.sol";
import "../erc721/interfaces/IBkNft.sol";
import "../utils/PaymentReceiver.sol";

contract BkDnaMaster is AdministrableUpgradable2024, PaymentReceiver {
  IBkNft nft;
  IBkDnaManager dnaManager;

  bool public hasCreatedCollections;
  bool public hasIntegratedBeasts;
  bool public used;

  mapping(address => bool) public userUsed;

  function initialize(address _operator, address _blocklist, address _nft, address _dnaManager) public initializer {
    __Administrable_init(_operator, _blocklist);

    nft = IBkNft(_nft);
    dnaManager = IBkDnaManager(_dnaManager);
  }

  /*
  IBkChar:
      uint256 id; // the NFT ID
      string name; // is an empty string up until the owner sets it
      string imageUrl; // is an empty string up until the owner sets it
      address currentOwner; // the current owner
      uint256 squadId; // the squad ID this NFT is in
      uint256 collection; // the collection this NFT belongs to
      uint256 baseFarm; // how many Weis of BCT this NFT will generate per cycle
      uint256 farmPerBlock; // the final farm per block
      uint256[] attributes; // species, rarity, rank, agility, nuts, evos
      uint256[] traits; // from 0 to 3 traits, that are numbers from 1 to 50+
      uint256[] skills; // multipliers for the farming of specific kinds of resources
      bool isDead; // whether the NFT is dead or not
  */
  function _createFullCollection(
    address to,
    uint256 initialBeastId,
    string memory collectionName,
    uint256 species,
    uint256 rarity
  ) private {
    uint collectionId = dnaManager.getCollectionsCount() + 1;

    uint256[] memory attributes = new uint256[](6);
    attributes[0] = species;
    attributes[1] = rarity;

    uint256[] memory traits = new uint256[](2);
    traits[0] = 1;
    traits[1] = 1;

    uint256[] memory skills = new uint256[](6);
    skills[0] = 1;
    skills[1] = 1;

    for (uint i = 0; i < 18; i++) {
      // @NFT: function mint(address to, IBkChar.BkChar memory character)
      nft.mint(
        to,
        IBkChar.BkChar({
          id: initialBeastId + i,
          name: "",
          imageUrl: "",
          currentOwner: to,
          squadId: 0,
          collection: collectionId,
          baseFarm: 0, // will be calculated later
          farmPerBlock: 0, // will be calculated later
          attributes: attributes,
          traits: traits,
          skills: skills,
          isDead: false
        })
      );
    }

    IBkDnaManager.Collection[] memory collections = new IBkDnaManager.Collection[](1);
    uint256[] memory collectionNftIds = new uint256[](18);
    for (uint i = 0; i < 18; i++) {
      collectionNftIds[i] = initialBeastId + i;
    }

    collections[0] = IBkDnaManager.Collection(collectionId, collectionName, to, collectionNftIds);
    dnaManager.setCollections(collections);
  }

  /**
   * @dev Transforms 24 Beasts into power cats, and kills 12 other Beasts, sequentially.
   * @param initialBeastId the first Beast ID to be transformed into a power cat
   **/
  function _makePowerCats(uint256 initialBeastId) private {
    uint256[] memory attributes = new uint256[](6);
    attributes[1] = 2; // species: cat
    attributes[2] = 4; // rarity: legendary

    for (uint i = 0; i < 24; i++) {
      uint256 beastId = initialBeastId + i;
      nft.setAttributes(beastId, attributes);
      nft.setBaseFarm(beastId, 31575000000000);
    }

    for (uint i = 0; i < 12; i++) {
      uint256 beastId = initialBeastId + 24 + i;
      nft.burnFrom(msg.sender, beastId);
    }
  }

  /**
   * Creates two collections: the first is made of 18 power cats, and the second is made of 6 power cats and 12 dead cats.
   * @param collection1Name the name of the first collection
   * @param collection2Name the name of the second collection
   */
  function makePowerCatsCollections(string memory collection1Name, string memory collection2Name) public whenNotPaused {
    uint256 initialBeastId = nft.nextNftId();

    _createFullCollection(msg.sender, initialBeastId, collection1Name, 1, 4);
    _createFullCollection(msg.sender, initialBeastId + 18, collection2Name, 1, 4);
    _makePowerCats(initialBeastId);

    // all resource prices are in cents:
    uint256[] memory priceInResources = new uint256[](16);
    priceInResources[6] = 8300; // Milk
    priceInResources[8] = 108000; // mangoes
    priceInResources[11] = 19200; // gene therapy
    priceInResources[14] = 430000; // mouse DNA
    priceInResources[15] = 19200; // cat DNA

    _receivePayment(18167000000000000000000, priceInResources, PaymentOptions(true, true, false, false));
  }

  function createFullCatCollections(string[] memory collectionNames, uint256 numberOfCollections) public whenNotPaused {
    require(collectionNames.length == numberOfCollections, "BkDnaMaster: invalid collection names length");

    uint256 initialBeastId = nft.nextNftId();

    uint256 oneCollectionCostEbct = 1250 * 4 * 1E18;
    uint256 totalCostEbct = oneCollectionCostEbct * numberOfCollections;

    uint256 oneCollectionCatDnaCost = 50 * 4 * 100;
    uint256 totalCostCatDna = oneCollectionCatDnaCost * numberOfCollections;

    uint256[] memory priceInResources = new uint256[](16);
    priceInResources[15] = totalCostCatDna; // cat DNA in cents

    _receivePayment(totalCostEbct, priceInResources, PaymentOptions(true, true, false, false));

    for (uint256 i = 0; i < numberOfCollections; i++) {
      _createFullCollection(msg.sender, initialBeastId + i * 18, collectionNames[i], 2, 4);
    }

    uint256[] memory nftIds = new uint256[](numberOfCollections * 18);
    for (uint i = 0; i < numberOfCollections * 18; i++) {
      nftIds[i] = initialBeastId + i;
    }

    for (uint i = 0; i < numberOfCollections * 18; i++) {
      nft.setBaseFarm(nftIds[i], 11250000000000);
    }
  }

  function createFullMouseCollections(
    string[] memory collectionNames,
    uint256 numberOfCollections
  ) public whenNotPaused {
    require(collectionNames.length == numberOfCollections, "BkDnaMaster: invalid collection names length");

    uint256 initialBeastId = nft.nextNftId();

    uint256 oneCollectionCostEbct = 625 * 4 * 1E18;
    uint256 totalCostEbct = oneCollectionCostEbct * numberOfCollections;

    uint256 oneCollectionCatDnaCost = 50 * 4 * 100;
    uint256 totalCostMouseDna = oneCollectionCatDnaCost * numberOfCollections;

    uint256[] memory priceInResources = new uint256[](16);
    priceInResources[14] = totalCostMouseDna; // mouse DNA in cents

    _receivePayment(totalCostEbct, priceInResources, PaymentOptions(true, true, false, false));

    for (uint256 i = 0; i < numberOfCollections; i++) {
      _createFullCollection(msg.sender, initialBeastId + i * 18, collectionNames[i], 1, 4);
    }

    uint256[] memory nftIds = new uint256[](numberOfCollections * 18);
    for (uint i = 0; i < numberOfCollections * 18; i++) {
      nftIds[i] = initialBeastId + i;
    }

    for (uint i = 0; i < numberOfCollections * 18; i++) {
      nft.setBaseFarm(nftIds[i], 3750000000000);
    }
  }

  function setupPaymentModule(
    address _bct,
    address _busd,
    address _pool,
    address _farm,
    address _resourcesSource,
    uint256 _autoReturnRate
  ) external onlyRole(OPERATOR_ROLE) {
    _setupPaymentModule(_bct, _busd, _pool, _farm, _resourcesSource, _autoReturnRate);
  }
}
