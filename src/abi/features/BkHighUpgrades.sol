// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../utils/PaymentReceiver.sol";

import "../interfaces/IBkFarm.sol";
import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkStasher.sol";
import "../interfaces/IBkFetch.sol";
import "../interfaces/IBkPlayerBonus.sol";

import "../erc721/EasyBkChar.sol";

contract BkHighUpgrades is AdministrableUpgradable2024, PaymentReceiver {
  using EasyBkChar for IBkChar.BkChar;

  struct Contracts {
    IBkFarm farm;
    IBkNft nft;
    IBkStasher stasher;
    IBkFetch balances;
    IBkPlayerBonus playerBonus;
  }
  Contracts public contracts;

  bool deifyEnabled;
  bool masteriesEnabled;
  bool aiChipsEnabled;
  bool globalFarmingBonusEnabled;

  uint256 public scale;
  uint256 public maxDeifySpecies;

  mapping(uint256 => uint256) public priceInEbctPerSpecies; // level => priceInEbct
  mapping(uint256 => uint256) public typeToTrait; // type_ => trait
  mapping(uint256 => uint256) public typeToBaseFarm; // type_ => baseFarm
  mapping(uint256 => uint256) public masteryIndexToDreamResourceIndex; // masteryIndex => dreamResourceIndex

  event Deify(address account, uint256 beastId, uint256 oldSpecies, uint256 newSpecies);
  event BuyMastery(address account, uint256 masteryIndex, uint256 oldLevel, uint256 newLevel);
  event TransferAiChips(address to, uint256 amount);
  event DismantleAiChips(address to, uint256 amount);
  event TransferResources(address to, uint256[] resources);
  event GlobalFarmingBonus(address account, uint256 oldLevel, uint256 newLevel);

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    scale = 50; // starting scale

    typeToTrait[6] = 44; // All Dragons are born Greedy
    typeToTrait[7] = 49; // All Griffins are born Fancy
    typeToTrait[8] = 5; // All Satyrs are born Magical
    typeToTrait[9] = 19; // All Dinosaurs are born Imposing
    typeToTrait[10] = 31; // All Apedroids are born Clever
    typeToTrait[11] = 37; // All Hydras are born Foodie
    typeToTrait[12] = 51; // All Chimeras are born Pyromaniac
    typeToTrait[13] = 53; // All Ents are born Healers
    typeToTrait[14] = 52; // All Kaijus are born Runesmiths
    typeToTrait[15] = 54; // All Cacodemons are born Sacavenger

    typeToBaseFarm[6] = 100000 * 1e9; // this much per block (100k gwei)
    typeToBaseFarm[7] = 125000 * 1e9;
    typeToBaseFarm[8] = 150000 * 1e9;
    typeToBaseFarm[9] = 175000 * 1e9;
    typeToBaseFarm[10] = 500000 * 1e9;
    typeToBaseFarm[11] = 600000 * 1e9;
    typeToBaseFarm[12] = 700000 * 1e9;
    typeToBaseFarm[13] = 800000 * 1e9;
    typeToBaseFarm[14] = 1000000 * 1e9;
    typeToBaseFarm[15] = 1250000 * 1e9;

    masteryIndexToDreamResourceIndex[0] = 25; // bct => AiChips
    masteryIndexToDreamResourceIndex[1] = 21; // eBct => Dragon Scales
    masteryIndexToDreamResourceIndex[2] = 21; // BL => Dragon Scales
    masteryIndexToDreamResourceIndex[3] = 23; // AL => Satyr Horns
    masteryIndexToDreamResourceIndex[4] = 22; // Nuts => Griffin Feathers
    masteryIndexToDreamResourceIndex[5] = 24; // Evos => Dinosaur Skulls

    maxDeifySpecies = 5; // the max species that can be deified
  }

  function getDeifyCosts(uint256 originalType) public view returns (uint256, uint256[] memory) {
    uint256 bct = originalType <= 8 ? 10000 + 5000 * (originalType - 1) : originalType == 9 ? 75000 : 100000;
    uint256 dnas = originalType <= 5 ? 25 : originalType <= 8 ? 50 : 250;
    uint256 dnaIndex = originalType <= 5 ? originalType + 13 : originalType + 8;
    uint256 dreamResources = originalType <= 5 ? 50 : originalType <= 8 ? 100 : 250;
    uint256 dreamResourceIndex = originalType <= 5 ? originalType + 20 : originalType + 15;

    // set the resource array:
    uint256[] memory _resources = new uint256[](26);
    _resources[9] = 100; // Ape Tools in cents
    _resources[dnaIndex] = dnas * 100; // in cents
    _resources[dreamResourceIndex] = dreamResources * 100; // in cents

    return ((bct * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function deify(uint256 beastId) external whenNotPaused {
    // let's get the beast from the balances contract
    IBkChar.BkChar memory beast = contracts.nft.getNft(beastId);
    address owner = contracts.nft.ownerOf(beastId);
    require(owner == msg.sender, "0"); // can only deify your own beasts
    require(beast.squadId == 0, "1"); // can't deify a beast that is in a squad
    require(beast.rarity() == 5, "2");

    uint256 species = beast.species();
    require(species <= maxDeifySpecies, "3"); // can't do that to high dream beasts, as they are the endgame

    uint256 stasherLevel = contracts.stasher.levelOf(msg.sender);
    require(stasherLevel == 10 || stasherLevel >= 8 + species, "4");

    uint256 newSpecies = species + 5;

    // let's charge the player:
    (uint256 _bct, uint256[] memory _resources) = getDeifyCosts(species);
    _receivePayment(_bct, _resources, PaymentOptions(true, true, false, false));

    // We'll reset the beast's name and image
    contracts.nft.setNameAndImage(beastId, "", "");

    // reset the evolutions and nuts consumed:
    beast.attributes[uint(IBkChar.ATTRIBUTE.NUTS)] = 0;
    beast.attributes[uint(IBkChar.ATTRIBUTE.EVOS)] = 0;

    // set the rarity to 5 and the species to newSpecies
    beast.attributes[uint(IBkChar.ATTRIBUTE.RARITY)] = 5;
    beast.attributes[uint(IBkChar.ATTRIBUTE.SPECIES)] = newSpecies;

    // create a new array to set the skills:
    uint256[] memory newSkills = new uint256[](6);
    newSkills[0] = 1;
    newSkills[1] = 1;

    // set the new skills and reset rank and agility:
    contracts.nft.setAttributesAndSkills(beastId, beast.attributes, newSkills);

    // create a new array to set the traits:
    uint256[] memory newTraits = new uint256[](3);
    newTraits[0] = typeToTrait[newSpecies];
    newTraits[1] = typeToTrait[newSpecies];
    newTraits[2] = typeToTrait[newSpecies];
    contracts.nft.setTraits(beastId, newTraits);

    // Finally set the correct baseFarm:
    contracts.nft.setBaseFarm(beastId, typeToBaseFarm[newSpecies]);

    emit Deify(owner, beastId, species, newSpecies);
  }

  function getMasteryCosts(
    uint256 masteryIndex,
    uint256 currentLevel,
    uint256 targetLevel
  ) public pure returns (uint256, uint256[] memory) {
    uint256 maxStep;
    if (masteryIndex == 0) {
      maxStep = 5;
    } else if (masteryIndex == 1 || masteryIndex == 5) {
      maxStep = 4;
    } else {
      maxStep = 3;
    }

    uint256 aiChips;
    for (uint i = currentLevel; i < targetLevel; i++) {
      if (i < maxStep) {
        aiChips += i + 1;
      } else {
        aiChips += maxStep;
      }
    }

    // set the resource array:
    uint256[] memory _resources = new uint256[](26);
    _resources[21] = (targetLevel - currentLevel) * 100; // Drasca in cents
    _resources[25] = aiChips * 100; // AI Chips in cents

    return (0, _resources);
  }

  // buy masteries
  // this is a player property, not a beast property
  // We use this function in tandem with the PlayerBonus contract:
  // function bonusWithFortuneAndMasteryOf(address account) external view returns (uint256, uint256, uint256[] memory);
  // the last param there is what matters to us: [BCT,eBCT,BL,AL,NUT,EVO] :: percentage bonus farm to that
  function buyMastery(uint256 masteryIndex, uint256 levels) external whenNotPaused {
    require(masteriesEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    // get the current player (msg.sender) masteries
    (, , uint256[] memory _masteries) = contracts.playerBonus.bonusWithFortuneAndMasteryOf(msg.sender);

    // get the costs:
    (uint256 _bct, uint256[] memory _resources) = getMasteryCosts(
      masteryIndex,
      _masteries[masteryIndex],
      _masteries[masteryIndex] + levels
    );

    // charge the user:
    _receivePayment(_bct, _resources, PaymentOptions(true, true, false, false));

    // change the masteries array:
    _masteries[masteryIndex] += levels;

    // set the new mastery array in the PlayerBonus contract:
    contracts.playerBonus.setMasteryLevelsOf(msg.sender, _masteries);

    emit BuyMastery(msg.sender, masteryIndex, _masteries[masteryIndex] - levels, _masteries[masteryIndex]);
  }

  function getAiChipCosts(uint256 howMany) public view returns (uint256, uint256[] memory) {
    uint256 bct = 0;
    uint256[] memory _resources = new uint256[](26);
    _resources[21] = howMany * 100; // Dragon Scales
    _resources[22] = howMany * 100; // Griffin Feathers
    _resources[23] = howMany * 100; // Satyr Horns
    _resources[24] = howMany * 100; // Dinosaur Skulls

    return ((bct * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function produceAiChips(uint256 howMany) public whenNotPaused {
    require(aiChipsEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    // charge the user:
    (uint256 _bct, uint256[] memory _resources) = getAiChipCosts(howMany);
    _receivePayment(_bct, _resources, PaymentOptions(true, true, false, false));

    // make the farm give it to the user:
    _resources[21] = 0;
    _resources[22] = 0;
    _resources[23] = 0;
    _resources[24] = 0;
    _resources[25] = howMany * 100; // Ai Chips

    contracts.farm.addTo(msg.sender, 0, _resources);

    emit TransferAiChips(msg.sender, howMany);
  }

  function getDismantleAiChipCosts(uint256 howMany) public view returns (uint256, uint256[] memory) {
    // Each costs 0 eBCT + 1 Ai Chip to dismantle
    uint256 bct = 0;
    uint256[] memory _resources = new uint256[](26);
    _resources[25] = howMany * 100; // Ai Chips

    return ((bct * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function dismantleAiChips(uint256 howMany) public whenNotPaused {
    require(aiChipsEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    // charge `howMany` Ai Chips from the user:
    (uint256 _bct, uint256[] memory _resources) = getDismantleAiChipCosts(howMany);
    _receivePayment(_bct, _resources, PaymentOptions(true, true, false, false));

    _resources[22] = howMany * 100; // Griffin Feathers
    _resources[23] = howMany * 100; // Satyr Horns
    _resources[24] = howMany * 100; // Dinosaur Skulls
    _resources[25] = 0; // Zero the number of Ai Chips

    // make the farm give it to the user:
    contracts.farm.addTo(msg.sender, 0, _resources);

    emit DismantleAiChips(msg.sender, howMany);
    emit TransferResources(msg.sender, _resources);
  }

  function getGlobalFarmingBonusCosts(
    uint256 currentLevel,
    uint256 targetLevel
  ) public view returns (uint256, uint256[] memory) {
    uint256 baseBctPrice = 1000;
    uint256 baseDreamResources = 2;
    uint256 baseApeTools = 1;

    uint256 bctPrice;
    uint256 dreamResourcesPrice;
    uint256 apeToolsPrice;
    for (uint i = currentLevel; i < currentLevel + targetLevel; i++) {
      bctPrice += baseBctPrice * (i + 1);
      dreamResourcesPrice += baseDreamResources * (i * 2);
      apeToolsPrice += baseApeTools * (i + 1);
    }

    // set the resource array:
    uint256[] memory _resources = new uint256[](26);

    _resources[9] = apeToolsPrice * 100; // in cents, ape tools
    _resources[25] = dreamResourcesPrice * 100; // in cents, always Ai Chips

    return ((bctPrice * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function buyGlobalFarmingBonus(uint256 levels) external whenNotPaused {
    require(globalFarmingBonusEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    // get the player object from the player's detailed bonus:
    // function detailedBonusOf(address _playerAddress) external view returns (Player memory, uint256[] memory _masteryLevels);
    (IBkPlayerBonus.Player memory player, ) = contracts.playerBonus.detailedBonusOf(msg.sender);

    // charge the user:
    (uint256 _bct, uint256[] memory _resources) = getGlobalFarmingBonusCosts(player.special, player.special + levels);
    _receivePayment(_bct, _resources, PaymentOptions(true, true, false, false));

    // change the special level:
    contracts.playerBonus.setSpecialOf(msg.sender, player.special + levels);

    emit GlobalFarmingBonus(msg.sender, player.special, player.special + levels);
  }

  ////////////////////
  // Operator Functions:
  function setContracts(
    address _farm,
    address _nft,
    address _stasher,
    address _balances,
    address _playerBonus
  ) external onlyRole(OPERATOR_ROLE) {
    contracts = Contracts({
      farm: IBkFarm(_farm),
      nft: IBkNft(_nft),
      stasher: IBkStasher(_stasher),
      balances: IBkFetch(_balances),
      playerBonus: IBkPlayerBonus(_playerBonus)
    });
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

  function setScale(uint256 _scale) external onlyRole(OPERATOR_ROLE) {
    scale = _scale;
  }

  function enableDeify(bool _enable) external onlyRole(OPERATOR_ROLE) {
    deifyEnabled = _enable;
  }

  function enableMasteries(bool _enable) external onlyRole(OPERATOR_ROLE) {
    masteriesEnabled = _enable;
  }

  function enableAiChips(bool _enable) external onlyRole(OPERATOR_ROLE) {
    aiChipsEnabled = _enable;
  }

  function enableGlobalFarmingBonus(bool _enable) external onlyRole(OPERATOR_ROLE) {
    globalFarmingBonusEnabled = _enable;
  }
}
