// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../utils/PaymentReceiver.sol";

import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkFarm.sol";
import "../interfaces/IBkSquad.sol";
import "../interfaces/IBkStasher.sol";
import "../interfaces/IBkPlayer.sol";
import "../interfaces/IBkSquad.sol";

import "../erc721/EasyBkChar.sol";

contract BkUpgrades is PaymentReceiver, AdministrableUpgradable2024 {
  using EasyBkChar for IBkChar.BkChar;

  struct Config {
    uint256 autoReturnRate;
    uint256 cooldownInBlocks;
    uint256 depositBonus;
    uint256 rankUpPrice;
    uint256 agilityUpPrice;
    uint256 extraSquadPrice;
    uint256 mentorPrice;
    uint256 merchantPrice;
    uint256 skillPrice;
    uint256 ritualPrice;
    uint256 maxIntegrationType;
  }
  Config public config;

  // Contracts
  struct Contracts {
    IBkFarm farm;
    IBkNft nft;
    IBkStasher stasher;
  }
  Contracts public contracts;

  event RankUp(uint256 nftId, uint256 ranks, address owner);

  // UPDATE VARS:
  uint256 public scale;

  event Deposit(address sender, uint256 amount, uint256 amountWithBonus);

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    config = Config({
      autoReturnRate: 100,
      cooldownInBlocks: 100,
      depositBonus: 3,
      rankUpPrice: 2,
      agilityUpPrice: 5,
      extraSquadPrice: 5000,
      mentorPrice: 550,
      merchantPrice: 100,
      skillPrice: 125,
      ritualPrice: 25,
      maxIntegrationType: 3
    });
  }

  function getRankUpPrices(uint256 species, uint256 rarity) public view returns (uint256 bct, uint256 resourceCents) {
    species = species > 5 ? 5 : species;
    uint256 bctPrice = config.rankUpPrice * (2 ** species - 1) * (2 ** rarity - 1);
    return (((bctPrice * 1E18 * scale) / 100) / 2, bctPrice);
  }

  function getAgilityUpPrices(
    uint256 species,
    uint256 rarity,
    uint256 currentAgility,
    uint256 levels
  ) public view returns (uint256 bct, uint256 resourceCents) {
    species = species > 5 ? 5 : species;
    uint256 baseBctPrice = config.agilityUpPrice * (2 ** species - 1) * (2 ** rarity - 1);

    uint256 bctPrice;
    for (uint i = currentAgility; i < currentAgility + levels; i++) {
      bctPrice += baseBctPrice * ((i + 1) ** 2);
    }

    return (((bctPrice * 1E18 * scale) / 100) / 2, (bctPrice * 10) / 25);
  }

  function getMaxOutRankAgilityPrices(
    uint256 species,
    uint256 rarity,
    uint256 currentRank,
    uint256 currentAgility
  ) public view returns (uint256 bct, uint256 resourceCents) {
    (uint256 rankUpBct, uint256 rankUpResource) = getRankUpPrices(species, rarity);
    rankUpBct *= 99 - currentRank;
    rankUpResource *= 99 - currentRank;

    (uint256 agilityUpBct, uint256 agilityUpResource) = getAgilityUpPrices(
      species,
      rarity,
      currentAgility,
      5 - currentAgility
    );

    return (rankUpBct + agilityUpBct, rankUpResource + agilityUpResource);
  }

  function getExtraSquadPrices(uint256 currentSquads) public view returns (uint256 bct, uint256 resourceCents) {
    uint256 priceInBct = (currentSquads - 3) * config.extraSquadPrice;
    uint256 priceInCheese = currentSquads <= 3 ? 0 : (currentSquads - 4) * 12;

    return (((priceInBct * 1E18 * scale) / 100) / 2, priceInCheese * 100);
  }

  function getExtraSlotPrices(
    uint256 currentSize,
    uint256 squadBonus
  ) public view returns (uint256 bct, uint256 resourceCents) {
    uint256 priceInBct;
    uint256 priceInCheese;

    if (currentSize == 3) {
      priceInBct = 10000;
      priceInCheese = 11;
    } else if (currentSize == 4) {
      priceInBct = 15000;
      priceInCheese = 22;
    } else if (currentSize == 5) {
      priceInBct = 25000;
      priceInCheese = 44;
    }

    priceInBct = (priceInBct * (100 + squadBonus)) / 100;
    priceInCheese = (priceInCheese * (100 + squadBonus)) / 100;

    return (((priceInBct * 1E18 * scale) / 100) / 2, priceInCheese * 100);
  }

  function getSkillLevelPrices(
    uint256 rarity,
    uint256 weight,
    uint256 levels
  ) public view returns (uint256 bct, uint256 resourceCents) {
    uint256 priceInBct = 125 * rarity * weight * levels;

    // resourceCents is exactly 1/100 of the BCT price, so we skip the multiplication by 100; it should be divided by 500 in units, so we just divide it by 5
    resourceCents = priceInBct / 5;

    return (((priceInBct * 1E18 * scale) / 100) / 2, resourceCents);
  }

  function deposit(uint256 amount) public whenNotPaused {
    require(amount > 10 * 1E18, "1");

    paymentContracts.bct.burnFrom(msg.sender, amount);

    uint256 stasherLevel = contracts.stasher.levelOf(msg.sender);

    uint256 bonus = 50 + stasherLevel * 25; // max: 300% bonus
    uint256 amountWithBonus = amount + (amount * bonus) / 100;

    // initalize the resource array
    uint256[] memory res = new uint256[](26);

    // for each ~1000~ 100 units of BCT deposited, we give 25 cents of resources
    uint256 resourceBonus = ((amount * 25) / 100) / 1E18;
    for (uint i = 0; i < 16; i++) {
      res[i] = resourceBonus;
    }

    // for each ~10000~ 1000 units, we give 1 Cow Box (resource 19), 4 Griffin Feathers, 2 Satyr Horns, and 1 Dinosaur Skulls
    // baseAmountInCents is 1 unit for every 10k BCT deposited
    uint256 oneUnitPer10k = ((amount / 1000) * 100) / 1E18; // 100 cents = 1 unit
    if (amount >= 1000 * 1E18) {
      res[19] = oneUnitPer10k; // Cow Box
      res[22] = oneUnitPer10k * 4; // 4 Griffin Feathers
      res[23] = oneUnitPer10k * 2; // 2 Satyr Horns
      res[24] = oneUnitPer10k; // 1 Dinosaur Skull
    }

    // for each ~50000~ 5000 units, we give 1 Elephant Box (resource 20), and 5 Ai Chips
    if (amount >= 5000 * 1E18) {
      res[20] = ((amount / 5000) / 1E18) * 100;
      res[25] = oneUnitPer10k; // Ai Chips
    }

    contracts.farm.addTo(msg.sender, amountWithBonus, res);

    emit Deposit(msg.sender, amount, amountWithBonus);
  }

  function buyRankUp(uint256 nftId, uint256 ranks) external whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(nft.rank() < 100 - ranks, "7");

    // Multiply rarity and price factors by the basePrice to get the finalPrice
    (uint256 price, uint256 basePriceInResources) = getRankUpPrices(nft.species(), nft.rarity());

    uint256[] memory priceInResources = new uint256[](nft.species());
    priceInResources[nft.species() - 1] = basePriceInResources * ranks;

    _receivePayment(price * ranks, priceInResources, PaymentOptions(true, true, false, false));

    nft.attributes[uint(IBkChar.ATTRIBUTE.RANK)] = nft.rank() + ranks;

    contracts.nft.setAttributes(nftId, nft.attributes);

    emit RankUp(nftId, ranks, msg.sender);
  }

  function buyAgilityUp(uint256 nftId, uint256 levels, bool withBusd) external whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(nft.agility() + levels < 6);
    require(levels > 0);

    // Multiply rarity and price factors by the basePrice to get the finalPrice
    (uint256 price, uint256 basePriceInResources) = getAgilityUpPrices(
      nft.species(),
      nft.rarity(),
      nft.agility(),
      levels
    );

    uint256[] memory priceInResources = new uint256[](nft.species());
    priceInResources[nft.species() - 1] = basePriceInResources;

    _receivePayment(price, priceInResources, PaymentOptions(true, false, withBusd, false));

    nft.attributes[uint(IBkChar.ATTRIBUTE.AGILITY)] = nft.agility() + levels;
    contracts.nft.setAttributes(nftId, nft.attributes);
  }

  function buyMaxOutRankAgility(uint256 nftId) external whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);
    require(nft.rank() < 99);
    require(nft.agility() < 5);

    // Multiply rarity and price factors by the basePrice to get the finalPrice
    (uint256 price, uint256 basePriceInResources) = getMaxOutRankAgilityPrices(
      nft.species(),
      nft.rarity(),
      nft.rank(),
      nft.agility()
    );

    uint256[] memory priceInResources = new uint256[](nft.species());
    priceInResources[nft.species() - 1] = basePriceInResources;

    _receivePayment(price, priceInResources, PaymentOptions(true, true, false, false));

    nft.attributes[uint(IBkChar.ATTRIBUTE.RANK)] = 99;
    nft.attributes[uint(IBkChar.ATTRIBUTE.AGILITY)] = 5;
    contracts.nft.setAttributes(nftId, nft.attributes);
  }

  function buyExtraSquad(bool withBusd) external whenNotPaused {
    IBkPlayer.Player memory player = contracts.farm.getPlayer(msg.sender);
    require(player.squads.length < 20);

    uint256 stasherLevel = contracts.stasher.levelOf(msg.sender);
    require(player.squads.length <= stasherLevel || stasherLevel >= 8);

    (uint256 priceInBct, uint256 priceInCheese) = getExtraSquadPrices(player.squads.length);

    // Always costs Exotic Cheese (index 5)
    uint256[] memory priceInResources = new uint256[](6);
    priceInResources[5] = priceInCheese;

    _receivePayment(priceInBct, priceInResources, PaymentOptions(true, false, withBusd, false));

    if ((player.squads.length + 1) % 2 != 0) {
      // it's a mixed squad
      contracts.farm.addSquadToPlayer(msg.sender, 6, 3);
    } else {
      if (player.squads.length == 9 || player.squads.length == 15 || player.squads.length == 19) {
        // it's a Cat squad
        contracts.farm.addSquadToPlayer(msg.sender, 2, 3);
      } else {
        // it's a Mouse squad
        contracts.farm.addSquadToPlayer(msg.sender, 1, 3);
      }
    }
  }

  function buyExtraSlot(uint256 squadId, bool withBusd) external whenNotPaused {
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);
    require(squad.owner == msg.sender);
    require(squad.size < 6);

    (uint256 priceInBct, uint256 priceInCheese) = getExtraSlotPrices(squad.size, squad.squadBonus);

    // Always costs Cat Milk (index 6)
    uint256[] memory priceInResources = new uint256[](7);
    priceInResources[6] = priceInCheese;

    _receivePayment(priceInBct, priceInResources, PaymentOptions(true, false, withBusd, false));

    contracts.farm.increaseSquadSize(squadId);
  }

  function buySkillLevel(uint256 nftId, uint256 skillIndex, uint256 levels, bool withBusd) external whenNotPaused {
    IBkChar.BkChar memory nft = contracts.nft.getNft(nftId);
    require(nft.currentOwner == msg.sender);

    require(!contracts.nft.isOnQuest(nftId), "onQ");

    if (nft.species() <= 5) {
      require(skillIndex <= 3);
      require(nft.skills[skillIndex] + levels <= 5);
    } else if (nft.species() <= 10) {
      require(skillIndex <= 4);
      require(nft.skills[skillIndex] + levels <= 7);
    } else {
      require(skillIndex <= 5);
      require(nft.skills[skillIndex] + levels <= 10);
    }

    (uint256 priceInBct, uint256 priceInResource) = getSkillLevelPrices(nft.rarity(), skillIndex + 1, levels);
    uint256[] memory priceInResources = new uint256[](26);

    if (skillIndex == 0) {
      // first row of 5 resources (BL: super cheese, shiny fish, groovy grass, happy roots, and sweet bananas)
      priceInResources[nft.species() - 1] = priceInResource;
    } else if (skillIndex == 1) {
      // second row of 5 resources (AL: exotic cheese, cat milk, magic mushrooms, happy roots, and ape tools)
      priceInResources[nft.species() + 4] = priceInResource;
    } else if (skillIndex == 2) {
      // The skill is (Extra Farm of Golden Nuts), it costs both BL and AL
      priceInResources[nft.species() - 1] = priceInResource;
      priceInResources[nft.species() + 4] = priceInResource;
    } else if (skillIndex == 3) {
      // The skill is (Extra Farm of Crafting Material), it costs Golden Nuts
      priceInResources[10] = priceInResource;
    } else if (skillIndex == 4) {
      // The skill is the second basic loot of a Dream Beast. It costs whatever it farms
      priceInResources[nft.species()] = priceInResource;
    } else {
      // The skill is the second advanced loot of a Dream Beast. It costs whatever it farms
      priceInResources[nft.species() + 5] = priceInResource;
    }

    _receivePayment(priceInBct, priceInResources, PaymentOptions(true, false, withBusd, false));

    nft.skills[skillIndex] = nft.skills[skillIndex] + levels;

    contracts.nft.setSkills(nftId, nft.skills);
  }

  function extractTrait(
    uint256 nftId,
    uint256 traitToExtract,
    uint256 squadToGetTrait,
    bool withBusd
  ) public whenNotPaused {
    IBkChar.BkChar memory target = contracts.nft.getNft(nftId);
    require(target.currentOwner == msg.sender);

    // Get the squad
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadToGetTrait);

    // Check the squad is owned by the sender
    require(squad.owner == msg.sender);

    // Check that the squad is not on a quest
    require(squad.currentQuest == 0);

    // Check the NFT has the traitToExtract
    bool hasTrait;
    for (uint i = 0; i < target.traits.length; i++) {
      if (target.traits[i] == traitToExtract) {
        hasTrait = true;
        break;
      }
    }
    require(hasTrait);

    // Burn the NFT
    contracts.nft.burnFrom(msg.sender, nftId);

    uint256[] memory priceInResources = new uint256[](10);
    uint256 maxRarity = target.rarity() > 5 ? 5 : target.rarity();
    priceInResources[8] = (26 - 5 * maxRarity) * 100; // costs Power Mangoes
    priceInResources[9] = 100; // 1 Ape Tool

    _receivePayment(
      (((5000 - maxRarity * 1000) * 1e18 * scale) / 100) / 2,
      priceInResources,
      PaymentOptions(true, false, withBusd, false)
    );

    contracts.farm.setSquadTrait(squadToGetTrait, traitToExtract);
    contracts.farm.recalculateSquadFarming(squadToGetTrait);
  }

  function setSquadType(uint256 squadId, uint256 newType) public whenNotPaused {
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);
    require(squad.owner == msg.sender);

    uint256[] memory priceInResources = new uint256[](10);
    priceInResources[9] = 5000; // 50 Ape Tools

    _receivePayment(((10000 * 1e18 * scale) / 100) / 2, priceInResources, PaymentOptions(true, true, false, false));

    contracts.farm.setSquadType(squadId, newType);
    contracts.farm.recalculateSquadFarming(squadId);
  }

  //#############
  // Private functions
  function _setContracts(address _farm, address _nft, address _stasher) private {
    contracts = Contracts({farm: IBkFarm(_farm), nft: IBkNft(_nft), stasher: IBkStasher(_stasher)});
  }

  //######################
  // OPERATOR functions
  function setAutoReturnRate(uint256 _autoReturnRate) external onlyRole(OPERATOR_ROLE) {
    config.autoReturnRate = _autoReturnRate;
  }

  function setConfig(Config memory _config) external onlyRole(OPERATOR_ROLE) {
    config = _config;
  }

  function setContracts(address _farm, address _nft, address _stasher) external onlyRole(OPERATOR_ROLE) {
    _setContracts(_farm, _nft, _stasher);
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
