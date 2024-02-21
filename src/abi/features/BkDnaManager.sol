// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../utils/PaymentReceiver.sol";

import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkSquad.sol";
import "../interfaces/IBkStasher.sol";
import "../interfaces/IBkPlayer.sol";
import "./RResult/interfaces/IResult.sol";

import "../interfaces/IBkTraitReroller.sol";

contract BkDnaManager is AdministrableUpgradable2024, PaymentReceiver {
  IResult private __result;

  // Contracts
  struct Contracts {
    IBkNft nft;
    IBkStasher stasher;
  }
  Contracts public contracts;

  struct Collection {
    uint256 id;
    string name;
    address creator;
    uint256[] nftIds;
  }
  uint256 collectionsCount; // total number of collections
  mapping(uint256 => Collection) public collections; // all the existing collections

  // player => slot index => collection id
  mapping(address => mapping(uint256 => uint256)) public collectionsIdsByOwner;
  // player => collection count
  mapping(address => uint256) public playerCollectionsCount;

  uint256 hybridCollectionthreshold;

  event TraitReroll(address account, uint256 nftId, uint256 chosenTrait);
  event AddExtraTrait(address account, uint256 nftId, uint256 chosenTrait);
  event Evolve(address account, uint256 nftId, uint256 chosenTrait, uint256 evolutions);
  event NutsToBaseFarm(address account, uint256 nftId, uint256 howManyNuts, uint256 newBaseFarm);
  event NewCollection(address account, uint256 collectionId, string name, uint256 type_);
  event ExpandCollection(address account, uint256 collectionId, uint256 type_);
  event ReplaceTrait(
    address account,
    uint256 targetNftId,
    uint256 traitRemovedFromTarget,
    uint256 sacrificeNftId,
    uint256 traitExtractedFromSacrifice
  );

  // UPDATED VARIABLES:
  IBkTraitReroller public traitReroller;

  struct CollectionRequestBasics {
    uint256 species;
    uint256 rarity;
    uint256 chosenTrait;
    uint256 collectionId; // if its zero, we are creating a new collection
  }

  uint256 public scale;

  function initialize(address _operator, address _blocklist, address _result) public initializer {
    __Administrable_init(_operator, _blocklist);

    __result = IResult(_result);

    hybridCollectionthreshold = 5;
  }

  function getIntegrationPrices(
    uint256 type_,
    uint256 rarity
  ) public view returns (uint256 bct, uint256 resourceCents) {
    return (((25 * type_ * rarity * 1E18 * scale) / 100) / 2, rarity * 25);
  }

  function evolve(
    uint256 nftId,
    uint256 chosenTrait,
    string memory newName,
    string memory newImageUrl
  ) public whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(!contracts.nft.isOnQuest(nftId));
    require(nft.attributes[1] > 1); // Can't evolve commons

    uint256 currentEvos = nft.attributes[uint256(IBkChar.ATTRIBUTE.EVOS)];
    require(currentEvos < 11); // Can't evolve more than 11 times

    uint256 species = nft.attributes[0];

    // it costs 1 Gene Therapy (index 11) + 1 DNA of the type of NFT (indexes 14,15,16,17,18)
    uint256[] memory priceInResources = new uint256[](species + 14);
    priceInResources[11] = 100; // Gene Therapy in cents
    priceInResources[species + 13] = 100; // DNA in cents

    _receivePayment(
      ((100 * species * nft.attributes[1] * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );

    if (chosenTrait != 0) {
      uint256 validTraitsCount = _countValidTraits(nft.traits);
      uint256 finalTraitCount = validTraitsCount < 2 ? 2 : validTraitsCount;
      _doReroll(nftId, chosenTrait, finalTraitCount);
    }

    contracts.nft.setNameAndImage(nftId, newName, newImageUrl);

    // But everyone gets the base farm improved
    // If the NFT has never evolved before, the bonus is 25%, else is 2%
    uint256 bonus = currentEvos == 0 ? 25 : 2;
    contracts.nft.setAttribute(nftId, uint256(IBkChar.ATTRIBUTE.EVOS), currentEvos + 1);

    // Apply the bonus to the NFT's basefarm:
    uint256 newBaseFarm = (nft.baseFarm * (100 + bonus)) / 100;

    // Set the new base farm
    contracts.nft.setBaseFarm(nftId, newBaseFarm);

    emit Evolve(msg.sender, nftId, chosenTrait, currentEvos + 1);
  }

  function evolveSequentially(
    uint256 nftId,
    uint256 chosenTrait,
    string memory newName,
    string memory newImageUrl,
    uint256 times
  ) external whenNotPaused {
    for (uint256 i = 0; i < times; i++) {
      if (i < times - 1) {
        evolve(nftId, chosenTrait, "", "");
      } else {
        // last iteration (with name and image
        evolve(nftId, chosenTrait, newName, newImageUrl);
      }
    }
  }

  function _countValidTraits(uint256[] memory traits) private pure returns (uint256) {
    uint256 validTraits = 0;
    for (uint256 i = 0; i < traits.length; i++) {
      if (traits[i] != 0) {
        validTraits++;
      }
    }
    return validTraits;
  }

  function improveBaseFarmWithNuts(uint256 nftId, uint256 howManyNuts) public whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(contracts.nft.ownerOf(nftId) == msg.sender);

    uint256 currentNuts = nft.attributes[4]; // nuts
    require(currentNuts + howManyNuts < 51);

    uint256 species = nft.attributes[0];

    contracts.nft.setAttribute(nftId, uint256(IBkChar.ATTRIBUTE.NUTS), currentNuts + howManyNuts);

    // it costs 1 Gold Nut (index 10) per 1% increase in base farm
    uint256[] memory priceInResources = new uint256[](11);
    priceInResources[10] = howManyNuts * 100; // in cents
    if (species >= 6 && species <= 10) {
      priceInResources[10] = priceInResources[10] * 5;
    } else if (species > 10) {
      priceInResources[10] = priceInResources[10] * 10;
    }

    _receivePayment(
      ((2 * species * nft.attributes[1] * 1e18 * howManyNuts * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );

    // Apply the bonus to the NFT's basefarm:
    uint256 newBaseFarm = (nft.baseFarm * (100 + howManyNuts)) / 100;

    // Set the new base farm
    contracts.nft.setBaseFarm(nftId, newBaseFarm);

    emit NutsToBaseFarm(msg.sender, nftId, howManyNuts, newBaseFarm);
  }

  function maxOutNuts(uint256 nftId, bool sequentially) public whenNotPaused {
    uint256 nutsConsumed = contracts.nft.attributeOf(nftId, uint256(IBkChar.ATTRIBUTE.NUTS));

    require(nutsConsumed < 50);
    uint256 howManyNuts = 50 - nutsConsumed;

    if (sequentially) {
      for (uint256 i = 0; i < howManyNuts; i++) {
        improveBaseFarmWithNuts(nftId, 1);
      }
    } else {
      improveBaseFarmWithNuts(nftId, howManyNuts);
    }
  }

  function addExtraTrait(uint256 nftId, uint256 chosenTrait) external whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(_countValidTraits(nft.traits) == 2);
    require(chosenTrait > 0 && chosenTrait <= 50);

    uint256 species = nft.attributes[0];

    // it costs 25 Magic Mushrooms (index 7) + 1 DNA of the type of NFT (indexes 14,15,16,17,18)
    uint256[] memory priceInResources = new uint256[](species + 14);
    priceInResources[7] = 2500; // Magic Mushrooms in cents
    priceInResources[species + 13] = 100; // DNA in cents

    _receivePayment(
      ((100 * species * nft.attributes[1] * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );

    // We add the new trait to the NFT
    uint256[] memory newTraitList = new uint256[](3);
    newTraitList[0] = nft.traits[0];
    newTraitList[1] = nft.traits[1];
    newTraitList[2] = chosenTrait;
    contracts.nft.setTraits(nftId, newTraitList);

    emit AddExtraTrait(msg.sender, nftId, chosenTrait);
  }

  function integrate(uint256[] memory nftIds, bool usePowerMangoes, bool transform) external whenNotPaused {
    IBkChar.BkChar memory target = contracts.nft.getNft(nftIds[0]);
    require(target.currentOwner == msg.sender);
    uint256 targetSpecies = target.attributes[0];

    IBkChar.BkChar memory subject1 = contracts.nft.getNft(nftIds[1]);
    require(subject1.currentOwner == msg.sender);
    require(subject1.attributes[1] == target.attributes[1]);
    require(subject1.attributes[0] == targetSpecies);
    require(target.id != subject1.id);

    contracts.nft.burnFrom(msg.sender, subject1.id);

    uint256[] memory priceInResources = new uint256[](19);
    IBkChar.BkChar memory subject2;
    if (usePowerMangoes) {
      subject2 = target;
      // pay and don't burn a second nft
      priceInResources[8] = 300; // 3 Power Mangoes
    } else {
      subject2 = contracts.nft.getNft(nftIds[2]);
      require(contracts.nft.ownerOf(subject2.id) == msg.sender);
      require(subject2.attributes[1] == subject1.attributes[1]);
      require(subject2.attributes[0] == subject1.attributes[0]);
      contracts.nft.burnFrom(msg.sender, subject2.id);
    }

    uint256 finalNuts = _ceilDiv(target.attributes[4] + subject1.attributes[4] + subject2.attributes[4], 3);
    uint256 finalEvos = _ceilDiv(target.attributes[5] + subject1.attributes[5] + subject2.attributes[5], 3);
    uint256 finalRank = (target.attributes[2] + subject1.attributes[2] + subject2.attributes[2]) / 3;
    uint256 finalAgility = (target.attributes[3] + subject1.attributes[3] + subject2.attributes[3]) / 3;
    uint256 finalBaseFarm = (((target.baseFarm + subject1.baseFarm + subject2.baseFarm) / 3) * 17) / 10; // plus 70%

    uint256[] memory finalSkills = new uint256[](4);
    finalSkills[0] = (target.skills[0] + subject1.skills[0] + subject2.skills[0]) / 3;
    finalSkills[1] = (target.skills[1] + subject1.skills[1] + subject2.skills[1]) / 3;
    finalSkills[2] = (target.skills[2] + subject1.skills[2] + subject2.skills[2]) / 3;
    finalSkills[3] = (target.skills[3] + subject1.skills[3] + subject2.skills[3]) / 3;

    (uint256 priceInBct, uint256 priceInResource) = getIntegrationPrices(targetSpecies, target.attributes[1]);

    target.attributes[uint256(IBkChar.ATTRIBUTE.RANK)] = finalRank;
    target.attributes[uint256(IBkChar.ATTRIBUTE.AGILITY)] = finalAgility;
    target.attributes[uint256(IBkChar.ATTRIBUTE.NUTS)] = finalNuts;
    target.attributes[uint256(IBkChar.ATTRIBUTE.EVOS)] = finalEvos;

    if (target.attributes[1] == 4 && transform) {
      require(targetSpecies < 5); // can only integrate until Elephant->Ape
      priceInResources[11] = 100; // 1 Gene Therapy
      priceInResources[14 + targetSpecies] = 100; // 1 DNA above the current type
      _receivePayment(priceInBct, priceInResources, PaymentOptions(true, true, false, false));
      target.attributes[uint256(IBkChar.ATTRIBUTE.SPECIES)] = targetSpecies + 1;
      target.attributes[uint256(IBkChar.ATTRIBUTE.RARITY)] = 1;
      contracts.nft.setAttributesAndSkills(target.id, target.attributes, finalSkills);
      contracts.nft.setNameAndImage(target.id, "", "");
    } else {
      priceInResources[targetSpecies + 4] += priceInResource; // costs advanced resources of that type
      _receivePayment(priceInBct, priceInResources, PaymentOptions(true, true, false, false));
      // contracts.nft.setRarityAndType(target.id, target.attributes[1] + 1, targetSpecies, finalBaseFarm);
      target.attributes[uint256(IBkChar.ATTRIBUTE.RARITY)] = target.attributes[1] + 1;
      contracts.nft.setAttributesAndSkills(target.id, target.attributes, finalSkills);

      if (target.attributes[1] == 4) {
        contracts.nft.setNameAndImage(target.id, target.name, "");
      }

      // if the nft had only one trait, give it another random one
      uint256 validTraits = _countValidTraits(target.traits);
      if (validTraits == 1) {
        _doReroll(target.id, target.traits[0], 2);
      } else if (validTraits == 0) {
        // if it had 0 traits, it gains 2 at random
        _doReroll(target.id, 0, 2);
      }
    }

    contracts.nft.setBaseFarm(target.id, finalBaseFarm);
  }

  function createCollection(
    string memory collectionName,
    string[] memory names,
    uint256 species,
    uint256 rarity,
    uint256 chosenTrait,
    string[] memory imageUrls,
    bool withBusd
  ) external whenNotPaused {
    uint256 stasherLevel = contracts.stasher.levelOf(msg.sender);

    require(names.length == 3); // we only allow creating 3 NFTs at a time

    // This function doesn't create Hybrid Collections
    require(species > 0 && species < 6);

    // Lvls 9, and 10 can create type 1; Lvl 10 can create all types
    require(stasherLevel >= 10 || stasherLevel >= species + 8);

    _receivePaymentForCollection(species, rarity, withBusd);

    // create the collection itself:
    uint256 initialnextNftId = contracts.nft.nextNftId();
    collectionsCount++;
    //_mintMany(names, species, rarity, chosenTrait, imageUrls, initialnextNftId, collectionsCount);
    _mintMany(
      CollectionRequestBasics({
        species: species,
        rarity: rarity,
        chosenTrait: chosenTrait,
        collectionId: collectionsCount
      }),
      names,
      imageUrls,
      initialnextNftId
    );

    // mount the nftIds array
    uint256[] memory nftIds = new uint256[](3);
    nftIds[0] = initialnextNftId;
    nftIds[1] = initialnextNftId + 1;
    nftIds[2] = initialnextNftId + 2;

    collections[collectionsCount] = Collection({
      id: collectionsCount,
      name: collectionName,
      creator: msg.sender,
      nftIds: nftIds
    });

    // Index the collection
    collectionsIdsByOwner[msg.sender][playerCollectionsCount[msg.sender]] = collectionsCount;
    playerCollectionsCount[msg.sender]++;

    emit NewCollection(msg.sender, collectionsCount, collectionName, species);
  }

  // Players who already own a collection may expand it, adding 5 more NFTs to it; it costs the same as creating one
  function expandCollection(
    uint256 collectionId,
    string[] memory names,
    uint256 species,
    uint256 rarity,
    uint256 chosenTrait,
    string[] memory imageUrls,
    bool withBusd
  ) external whenNotPaused {
    uint256 stasherLevel = contracts.stasher.levelOf(msg.sender);

    // This function doesn't create Hybrid Collections
    require(species > 0 && species < 6);

    // Lvls 9, 10, and 11 can create type 1; Lvls 10 and 11 can create type 2; Lvl 11 can create types 3, 4 and 5
    require(stasherLevel >= 10 || stasherLevel >= species + 8);

    Collection memory collection = collections[collectionId];
    require(collection.creator == msg.sender);
    require(collection.nftIds.length < 14); // max is 18 NFTs per collection
    require(names.length == 5); // we only allow expanding by 5 NFTs at a time

    _receivePaymentForCollection(species, rarity, withBusd);

    // create the collection itself:
    uint256 initialnextNftId = contracts.nft.nextNftId();
    //_mintMany(names, species, rarity, chosenTrait, imageUrls, initialnextNftId, collectionId);
    _mintMany(
      CollectionRequestBasics({species: species, rarity: rarity, chosenTrait: chosenTrait, collectionId: collectionId}),
      names,
      imageUrls,
      initialnextNftId
    );

    for (uint i = 0; i < 5; i++) {
      collections[collectionId].nftIds.push(initialnextNftId + i);
    }

    emit ExpandCollection(msg.sender, collectionId, species);
  }

  // Get a collection count by address
  function collectionsCountOfOwner(address player) external view returns (uint256) {
    return playerCollectionsCount[player];
  }

  function getCollectionsByAccount(
    address account
  ) external view returns (Collection[] memory _collections, IBkChar.BkChar[][] memory _nfts) {
    uint256 _collectionsCount = playerCollectionsCount[account];
    uint256[] memory collectionsIds = new uint256[](_collectionsCount);

    for (uint i = 0; i < _collectionsCount; i++) {
      collectionsIds[i] = collectionsIdsByOwner[account][i];
    }

    return getCollections(collectionsIds);
  }

  function getCollections(
    uint256[] memory collectionIds
  ) public view returns (Collection[] memory _collections, IBkChar.BkChar[][] memory _nfts) {
    uint256 _collectionsCount = collectionIds.length;
    _collections = new Collection[](_collectionsCount);
    _nfts = new IBkChar.BkChar[][](_collectionsCount);

    for (uint256 i = 0; i < _collectionsCount; i++) {
      Collection memory collection = collections[collectionIds[i]];

      _collections[i] = collection;
      uint256 nftsCount = collection.nftIds.length;
      _nfts[i] = new IBkChar.BkChar[](nftsCount);

      for (uint256 j = 0; j < nftsCount; j++) {
        _nfts[i][j] = contracts.nft.getNft(collection.nftIds[j]);
      }
    }
  }

  function getCollectionNames(uint256[] memory collectionIds) external view returns (string[] memory) {
    uint256 length = collectionIds.length;
    string[] memory result = new string[](length);

    for (uint256 i = 0; i < length; i++) {
      result[i] = collections[collectionIds[i]].name;
    }

    return result;
  }

  function getCollectionsCount() external view returns (uint256) {
    return collectionsCount;
  }

  //#############
  // Private functions
  function _setContracts(address _nft, address _stasher) private {
    contracts = Contracts({nft: IBkNft(_nft), stasher: IBkStasher(_stasher)});
  }

  function _doReroll(uint256 nftId, uint256 chosenTrait, uint256 traitCount) private {
    uint256[] memory newTraits = traitReroller.getRerolledTraits(chosenTrait, traitCount);
    contracts.nft.setTraits(nftId, newTraits);
  }

  function _receivePaymentForCollection(uint256 type_, uint256 rarity, bool withBusd) private {
    // We find out how much we should charge in BUSD
    // In BCT: Rarity 4: Mouse: 5k; Cat: 10k; Cow: 20k; Elephant: 40k (times scale)
    // In BCT: Rarity 5: Mouse: 10k; Cat: 20k; Cow: 40k; Elephant: 80k (times scale)
    // In BUSD: 2x the BCT price
    uint256 priceInBct = (((2 ** (type_ - 1)) * 10000 * 1e18 * scale) / 100) / 2;
    priceInBct = rarity == 4 ? priceInBct : priceInBct * 2; // mythics cost double
    uint256 priceInDna;

    if (rarity == 4) {
      priceInDna = type_ <= 2 ? 5000 : 12000;
    } else {
      priceInDna = type_ <= 2 ? 15000 : 36000;
    }

    if (withBusd) {
      priceInBct = priceInBct * 2;
      // now let's account for the Dream Resources
      // They cost 20 or 40 busd, depending on the rarity and type; let's get the value of 20 busd in bct
      uint256 twentyBusdInBct = stabletokenToBct(20 ether);

      if (rarity == 5) {
        priceInBct = priceInBct + twentyBusdInBct * 2;
      } else if (type_ > 2) {
        priceInBct = priceInBct + twentyBusdInBct;
      }
      _receivePayment(priceInBct, new uint256[](0), PaymentOptions(true, false, true, false));
    } else {
      // it costs 50 DNA of the type of NFT (indexes 14,15,16,17,18)
      uint256[] memory priceInResources = new uint256[](25);
      priceInResources[type_ + 13] = priceInDna; // DNA in cents

      if (rarity == 5) {
        priceInResources[type_ + 20] = 4000; // Dream Resources in cents
      } else if (type_ > 2) {
        priceInResources[type_ + 20] = 2000; // Dream Resources in cents
      }

      _receivePayment(priceInBct, priceInResources, PaymentOptions(true, false, false, false));
    }
  }

  function _ceilDiv(uint a, uint b) internal pure returns (uint) {
    if (a % b == 0) {
      return a / b;
    }

    return a / b + 1;
  }

  function _mintMany(
    CollectionRequestBasics memory basics,
    string[] memory names,
    string[] memory imageUrls,
    uint256 initialnextNftId
  ) private {
    for (uint i = 0; i < names.length; i++) {
      // create the traits array:
      uint256[] memory traits = new uint256[](2);
      traits[0] = basics.chosenTrait;
      traits[1] = (__result.get(msg.sender, 1, 50, basics.collectionId + i, initialnextNftId + i));

      uint256[] memory attributes = new uint256[](6);
      attributes[0] = basics.species;
      attributes[1] = basics.rarity;

      uint256[] memory skills = new uint256[](6);
      skills[0] = 1;
      skills[1] = 1;

      contracts.nft.mint(
        msg.sender,
        IBkChar.BkChar({
          id: 0,
          name: names[i],
          imageUrl: imageUrls[i],
          currentOwner: msg.sender,
          squadId: 0,
          collection: basics.collectionId,
          baseFarm: 0, // will be set automatically
          farmPerBlock: 0,
          attributes: attributes,
          traits: traits,
          skills: skills,
          isDead: false
        })
      );

      IBkChar.BkChar memory nft = contracts.nft.getNft(initialnextNftId + i);
      contracts.nft.setBaseFarm(initialnextNftId + i, (nft.baseFarm * 125) / 100);
    }
  }

  //######################
  // OPERATOR functions
  function setCollections(Collection[] memory _collections) external onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < _collections.length; i++) {
      collections[_collections[i].id] = _collections[i];
    }

    // set the current id
    collectionsCount = _collections[_collections.length - 1].id > collectionsCount
      ? _collections[_collections.length - 1].id
      : collectionsCount;
  }

  function setContracts(address _nft, address _stasher) external onlyRole(OPERATOR_ROLE) {
    _setContracts(_nft, _stasher);
  }

  function setRResult(address _result) external onlyRole(OPERATOR_ROLE) {
    __result = IResult(_result);
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

  function updateResources(address sourceContract) external onlyRole(OPERATOR_ROLE) {
    _updateResources(sourceContract);
  }

  function setTraitReroller(address _reroller) external onlyRole(OPERATOR_ROLE) {
    traitReroller = IBkTraitReroller(_reroller);
  }

  function setScale(uint256 _scale) external onlyRole(OPERATOR_ROLE) {
    scale = _scale; // starts at 200, representing 2x
  }
}
