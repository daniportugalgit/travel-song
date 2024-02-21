// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../utils/PaymentReceiver.sol";
import "../utils/AntiMevLock.sol";

import "../erc721/interfaces/IBkNft.sol";
import "./RResult/interfaces/IResult.sol";

import "../erc721/EasyBkChar.sol";

/**
 * @title BkTraitReroller
 * @dev Rerolls traits
 */
contract BkTraitReroller is AntiMevLock, PaymentReceiver, AdministrableUpgradable2024 {
  using EasyBkChar for IBkChar.BkChar;

  IResult private __result;
  IBkNft private _nftContract;

  mapping(address => uint256) public playerNonce;

  event TraitReroll(
    address account,
    uint256 nftId,
    uint256 oldTrait1,
    uint256 oldTrait2,
    uint256 oldTrait3,
    uint256 newTrait1,
    uint256 newTrait2,
    uint256 newTrait3
  );

  // UPDATE VARS:
  uint256 public scale;

  function initialize(address _operator, address _blocklist, address _nft, address _result) public initializer {
    __Administrable_init(_operator, _blocklist);

    _nftContract = IBkNft(_nft);
    __result = IResult(_result);

    lockPeriod = 1;
  }

  // Costs 1 Trait Reroll Token
  function traitReroll(uint256 nftId, uint256 chosenTrait) external whenNotPaused {
    IBkChar.BkChar memory nft = _nftContract.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(!_nftContract.isOnQuest(nftId));

    uint256 traitCount = _countValidTraits(nft.traits);
    uint256[] memory newTraits = _getRerolledTraits(chosenTrait, traitCount);

    if (traitCount == 3) {
      emit TraitReroll(
        msg.sender,
        nftId,
        nft.traits[0],
        nft.traits[1],
        nft.traits[2],
        newTraits[0],
        newTraits[1],
        newTraits[2]
      );
    } else if (traitCount == 2) {
      emit TraitReroll(msg.sender, nftId, nft.traits[0], nft.traits[1], 0, newTraits[0], newTraits[1], 0);
    } else {
      emit TraitReroll(msg.sender, nftId, nft.traits[0], 0, 0, newTraits[0], 0, 0);
    }

    _nftContract.setTraits(nftId, newTraits);

    // it costs only 1 Gene Therapy (index 11)
    uint256[] memory priceInResources = new uint256[](12);
    priceInResources[11] = 100; // in cents
    _receivePayment(
      ((1 * nft.species() * nft.rarity() * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );
  }

  function reassemble(
    uint256 nftId,
    uint256 chosenTrait1,
    uint256 chosenTrait2
  ) external whenNotPaused onlyUnlocked(msg.sender) {
    // if the nft has only 1 trait, or if the nft has 2 traits, it will end up having exactly the 2 chosen traits
    // if the nft has 3 traits, it will end up having exactly the 2 chosen traits and a random trait
    // it always costs 50 trait rerolls

    IBkChar.BkChar memory nft = _nftContract.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(!_nftContract.isOnQuest(nftId));
    require(chosenTrait1 > 0 && chosenTrait1 <= 50);
    require(chosenTrait2 > 0 && chosenTrait2 <= 50);

    uint256 traitCount = _countValidTraits(nft.traits);
    if (traitCount < 3) {
      uint256[] memory newTraits = new uint256[](2);
      newTraits[0] = chosenTrait1;
      newTraits[1] = chosenTrait2;

      if (traitCount == 1) {
        emit TraitReroll(msg.sender, nftId, nft.traits[0], 0, 0, newTraits[0], newTraits[1], 0);
      } else {
        emit TraitReroll(msg.sender, nftId, nft.traits[0], nft.traits[1], 0, newTraits[0], newTraits[1], 0);
      }

      _nftContract.setTraits(nftId, newTraits);
    } else {
      uint256 currentPlayerNonce = playerNonce[msg.sender];
      playerNonce[msg.sender]++;

      uint256[] memory newTraits = new uint256[](3);
      newTraits[0] = chosenTrait1;
      newTraits[1] = chosenTrait2;
      newTraits[2] = (__result.get(msg.sender, 1, 50, currentPlayerNonce + 97, currentPlayerNonce + 7));

      emit TraitReroll(
        msg.sender,
        nftId,
        nft.traits[0],
        nft.traits[1],
        nft.traits[2],
        newTraits[0],
        newTraits[1],
        newTraits[2]
      );

      _nftContract.setTraits(nftId, newTraits);
    }

    // it costs only 50 Gene Therapy (index 11)
    uint256[] memory priceInResources = new uint256[](12);
    priceInResources[11] = 5000; // in cents
    _receivePayment(
      ((750 * nft.species() * nft.rarity() * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );
  }

  // now a function that simply sets the 3 traits of any beast that already has 3 traits
  // it costs 100 Gene Therapy (index 11) + 25 Mushrooms (index 7) + 1 Dna of the nft type (index from 14 to 18) + (1000 * nft.type_ * nft.rarity * 1e18 * scale) BCT
  function transmute(
    uint256 nftId,
    uint256 trait1,
    uint256 trait2,
    uint256 trait3
  ) external whenNotPaused onlyUnlocked(msg.sender) {
    IBkChar.BkChar memory nft = _nftContract.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(!_nftContract.isOnQuest(nftId));
    require(trait1 > 0 && trait1 <= 54); // this is intentional ^.^
    require(trait2 > 0 && trait2 <= 54);
    require(trait3 > 0 && trait3 <= 54);
    require(_countValidTraits(nft.traits) == 3);

    uint8 specialTraits = 0;
    if (trait1 > 50) {
      specialTraits++;
    }
    if (trait2 > 50) {
      specialTraits++;
    }
    if (trait3 > 50) {
      specialTraits++;
    }
    uint256 dragonScalesNeeded = (specialTraits * 3) ** 2;

    uint256[] memory newTraits = new uint256[](3);
    newTraits[0] = trait1;
    newTraits[1] = trait2;
    newTraits[2] = trait3;

    emit TraitReroll(
      msg.sender,
      nftId,
      nft.traits[0],
      nft.traits[1],
      nft.traits[2],
      newTraits[0],
      newTraits[1],
      newTraits[2]
    );

    _nftContract.setTraits(nftId, newTraits);

    // it costs 50 Golden Nuts (index 10) + 100 Gene Therapy (index 11) + 25 Mushrooms (index 7) + 1 Dna of the nft type (index from 14 to 18)
    uint256[] memory priceInResources = new uint256[](26);
    priceInResources[10] = 2500; // Golden Nuts in cents
    priceInResources[11] = 10000; // Gene Therapy in cents
    priceInResources[7] = 2500; // Mushroom in cents
    priceInResources[9] = 100; // Ape Tools in cents
    priceInResources[13 + nft.species()] = 100; // DNA in cents
    priceInResources[21] = dragonScalesNeeded * 100; // Dragon Scales in cents

    _receivePayment(
      ((1500 * nft.species() * nft.rarity() * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, true, false, false)
    );
  }

  function getRerolledTraits(
    uint256 chosenTrait,
    uint256 traitCount
  ) external onlyRole(OPERATOR_ROLE) returns (uint256[] memory traits) {
    return _getRerolledTraits(chosenTrait, traitCount);
  }

  //#############
  // Private functions
  function _countValidTraits(uint256[] memory traits) private pure returns (uint256) {
    uint256 validTraits = 0;
    for (uint256 i = 0; i < traits.length; i++) {
      if (traits[i] != 0) {
        validTraits++;
      }
    }
    return validTraits;
  }

  function _getRerolledTraits(uint256 chosenTrait, uint256 traitCount) private returns (uint256[] memory traits) {
    require(chosenTrait >= 0 && chosenTrait <= 50);

    playerNonce[msg.sender]++;
    uint256 currentPlayerNonce = playerNonce[msg.sender];

    uint256 seed = __result.get(msg.sender, 1, 100, currentPlayerNonce + 3597, currentPlayerNonce * 3);
    currentPlayerNonce++;

    if (chosenTrait == 0) {
      // reroll it!
      chosenTrait = (__result.get(msg.sender, 1, 50, seed + 97, seed + 579 + currentPlayerNonce));
    }

    if (traitCount == 3) {
      // reroll 2 and set the trait 0 as the chosenTrait
      traits = new uint256[](3);
      traits[0] = chosenTrait;
      traits[1] = (__result.get(msg.sender, 1, 50, seed + 93, seed + 127 + currentPlayerNonce));
      traits[2] = (__result.get(msg.sender, 1, 50, seed + 77, seed + 323 + currentPlayerNonce));
    } else if (traitCount == 2) {
      // reroll 1 and set the trait 0 as the chosenTrait
      traits = new uint256[](2);
      traits[0] = chosenTrait;
      traits[1] = (__result.get(msg.sender, 1, 50, seed + 277, seed + 997 + currentPlayerNonce));
    } else {
      // reroll 0 and set the trait 0 as the chosenTrait
      traits = new uint256[](1);
      traits[0] = chosenTrait;
    }
  }

  //######################
  // OPERATOR functions
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

  function setScale(uint256 _scale) external onlyRole(OPERATOR_ROLE) {
    scale = _scale; // starts at 200, representing 2%
  }
}
