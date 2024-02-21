// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../erc721/interfaces/IBkNft.sol";
import "./RResult/interfaces/IResult.sol";
import "../utils/PaymentReceiver.sol";
import "../utils/AntiMevLock.sol";

/**
 * @title MhdaoStore
 * @dev Sells items
 */
contract BkBoosterCracker is PaymentReceiver, AntiMevLock, AdministrableUpgradable2024 {
  IResult private __result;

  // Contracts
  struct Contracts {
    IBkNft nft;
  }
  Contracts public contracts;

  /// @notice The rarity factor for each rarity level
  mapping(uint256 => uint256) public rarityAndTypeFactor;
  mapping(uint256 => uint256) public rarityAndQuantityFactor;

  // UPDATE VARS:
  uint256 public scale;

  function initialize(address _operator, address _blocklist, address _result) public initializer {
    __Administrable_init(_operator, _blocklist);

    __result = IResult(_result);

    rarityAndTypeFactor[1] = 1; // Common
    for (uint256 i = 1; i < 10; i++) {
      // Up to rarity 10, (1023 as multiplier is the max value)
      rarityAndTypeFactor[i + 1] = 2 ** (i + 1) - 1;
    }

    rarityAndQuantityFactor[1] = 1; // Common
    rarityAndQuantityFactor[3] = 2; // Rare
    rarityAndQuantityFactor[9] = 3; // Epic
    rarityAndQuantityFactor[27] = 4; // Legendary
    rarityAndQuantityFactor[81] = 5; // Mythic

    _setLockPeriod(1); // Up to one tx per wallet per block
  }

  function getIntegrationPrices(
    uint256 type_,
    uint256 howMany
  ) public view returns (uint256 bct, uint256 resourceCents) {
    if (howMany == 1) {
      // this is not an integration, it's just someone opening a booster
      // it costs no BCT, and it costs 100 resource cents of the booster box, but that is charged elsewhere
      // therefore, we return 0 BCT and 0 resource cents
      bct = 0;
      resourceCents = 0;
    } else if (howMany == 3) {
      // get a rare from 3 commons
      bct = 25 * type_ * 1 * 1E18;
      resourceCents = 1 * 25;
    } else if (howMany == 9) {
      // get an epic from 9 commons
      // First, 9 commons become 3 rares
      bct = 25 * type_ * 1 * 1E18 * 3;
      resourceCents = 1 * 25 * 3;

      // Then, 3 rares become 1 epic
      bct += 25 * type_ * 2 * 1E18;
      resourceCents += 2 * 25;
    } else if (howMany == 27) {
      // get a legendary from 27 commons
      // First, 27 commons become 9 rares
      bct = 25 * type_ * 1 * 1E18 * 9;
      resourceCents = 1 * 25 * 9;

      // Then, 9 rares become 3 epics
      bct += 25 * type_ * 2 * 1E18 * 3;
      resourceCents += 2 * 25 * 3;

      // Then, 3 epics become 1 legendary
      bct += 25 * type_ * 3 * 1E18;
      resourceCents += 3 * 25;
    } else if (howMany == 81) {
      // get a legendary from 81 commons
      // First, 81 commons become 27 rares
      bct = 25 * type_ * 1 * 1E18 * 27;
      resourceCents = 1 * 25 * 27;

      // Then, 27 rares become 9 epics
      bct += 25 * type_ * 2 * 1E18 * 9;
      resourceCents += 2 * 25 * 9;

      // Then, 9 epics become 3 legendaries
      bct += 25 * type_ * 3 * 1E18 * 3;
      resourceCents += 3 * 25 * 3;

      // Then, 3 legendaries become 1 mythic
      bct += 25 * type_ * 4 * 1E18;
      resourceCents += 4 * 25;
    } else {
      revert("Invalid quantity");
    }

    bct = ((bct * scale) / 100) / 2; // since scale was introduced at 2, we divide by 2 here
  }

  // The user can unbox 1, 3, 9, 27 or 81 boosters at once.
  // When more than one booster is unboxed, the user always gets only one NFT, but rarer.
  function unboxBooster(uint256 type_, uint256 quantity) external whenNotPaused onlyUnlockedSender {
    _unboxBooster(msg.sender, type_, quantity);
  }

  function unboxBoosterFor(address owner, uint256 type_, uint256 quantity) external onlyRole(OPERATOR_ROLE) {
    _unboxBooster(owner, type_, quantity);
  }

  function batchUnboxBooster(uint256 type_, uint256 quantity, uint256 times) external whenNotPaused onlyUnlockedSender {
    require(times > 0);
    require(times <= 100);

    for (uint256 i = 0; i < times; i++) {
      _unboxBooster(msg.sender, type_, quantity);
    }
  }

  //#############
  // Private functions
  function _unboxBooster(address owner, uint256 species, uint256 quantity) private {
    require(species >= 1 && species <= 4);
    require(quantity == 1 || quantity == 3 || quantity == 9 || quantity == 27 || quantity == 81);

    uint256[] memory priceInResources = new uint256[](26);
    (uint256 priceInBct, uint256 priceInResource) = getIntegrationPrices(species, quantity);
    priceInResources[species + 4] = priceInResource; // costs advanced resources of that type

    uint256 typeSlot = species > 2 ? species + 16 : species + 11;
    priceInResources[typeSlot] = quantity * 100; // costs boxes of that type (in cents here)
    _receivePayment(priceInBct, priceInResources, PaymentOptions(true, true, false, false));

    uint256 nftBalance = contracts.nft.nextNftId();

    uint256[] memory traits = new uint256[](2);
    traits[0] = (__result.get(owner, 1, 50, 3, owner.balance + nftBalance));
    traits[1] = (__result.get(owner, 1, 50, 7, owner.balance + nftBalance + 1));

    uint256[] memory skills = new uint256[](6);
    skills[0] = 1;
    skills[1] = 1;

    uint256[] memory attributes = new uint256[](6);
    attributes[0] = species;
    attributes[1] = rarityAndQuantityFactor[quantity]; // rarity

    contracts.nft.mint(
      msg.sender,
      IBkChar.BkChar({
        id: 0,
        name: "",
        imageUrl: "",
        currentOwner: msg.sender,
        squadId: 0,
        collection: 0,
        baseFarm: 0, // will be set automatically
        farmPerBlock: 0,
        attributes: attributes,
        traits: traits,
        skills: skills,
        isDead: false
      })
    );
  }

  //######################
  // OPERATOR functions
  function setContracts(address _nft) external onlyRole(OPERATOR_ROLE) {
    contracts = Contracts({nft: IBkNft(_nft)});
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

  function setScale(uint256 _scale) external onlyRole(OPERATOR_ROLE) {
    scale = _scale; // starts at 200, representing 2%
  }
}
