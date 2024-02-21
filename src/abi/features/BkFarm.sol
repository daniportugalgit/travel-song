// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../erc20/interfaces/IBkERC20.sol";
import "../erc721/interfaces/IBkNft.sol";

import "../interfaces/IBkPlayerBonus.sol";
import "../interfaces/IBkPlayer.sol";
import "../interfaces/IBkSquad.sol";
import "../interfaces/IBkQuest.sol";
import "../interfaces/IBkQuestRewardCalculator.sol";

contract BkFarm is AdministrableUpgradable2024 {
  // Interfaces
  struct Contracts {
    IBkERC20 bct;
    IBkNft bkNft;
    IBkPlayerBonus playerBonus;
    IBkQuestRewardCalculator questRewardCalculator;
  }
  Contracts public contracts;

  mapping(address => IBkPlayer.Player) public players;
  mapping(uint256 => IBkSquad.Squad) public squads;
  mapping(uint256 => IBkQuest.Quest) public quests;
  uint256 public totalSquads; // total squads ever, counting all players
  mapping(uint256 => uint256) public raritySumOfSquad; // sum of all NFTs rarities in a squad
  uint256 totalResources; // total resources registered
  mapping(address => mapping(uint256 => uint256)) public resourceBalances; // player => resource => amount
  mapping(address => uint256) public changeMentorBlock; // player => block number

  Config public config;

  struct Config {
    uint256 scale; // 100 is 1.00, multiplies the farm per block
    uint256 withdrawalInterval; // minimum number of blocks between withdraws
    uint256 maxSquads; // max squads per player
  }

  event PlayerRegistered(address player);
  event QuestStarted(address player, uint256 squadId, uint256 questId, uint256 farmPerBlock);
  event QuestEnded(address player, uint256 squadId, uint256 questId, uint256 duration);
  event Withdraw(address player, uint256 amount, uint256 burnAmount);
  event Transfer(address from, address to, uint256 bct, uint256 ebct, uint256[] resources);
  event BurnBct(uint256 amount);

  function initialize(
    address _operator,
    address _blocklist,
    address _bct,
    address _bkNft,
    address _playerBonus,
    address _questRewardCalculator
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    contracts = Contracts({
      bct: IBkERC20(_bct),
      bkNft: IBkNft(_bkNft),
      playerBonus: IBkPlayerBonus(_playerBonus),
      questRewardCalculator: IBkQuestRewardCalculator(_questRewardCalculator)
    });

    config = Config({
      scale: 1,
      withdrawalInterval: 8640 * 15, // 15 days
      maxSquads: 20
    });
  }

  //################
  // User functions
  function _onlyOwnerNotPausedOrUpdater(address account) internal view {
    require((account == msg.sender && !paused()) || hasRole(UPDATER_ROLE, msg.sender));
  }

  function registerPlayer(address account, bool autocreateSquads) public whenNotPaused {
    require(players[account].squads.length == 0, "1");
    require(msg.sender == account || hasRole(UPDATER_ROLE, msg.sender), "2");

    players[account] = IBkPlayer.Player({
      bctToClaim: 0,
      etherealBct: players[account].etherealBct,
      lastWithdrawalBlock: block.number,
      registeredAt: block.number,
      mentor: address(0),
      mentorLevel: 1,
      merchantLevel: 0,
      squads: new uint256[](0) // a dynamic list of squad ids
    });

    if (autocreateSquads) {
      _createNewSquad(account, 6);
      _createNewSquad(account, 6);
      _createNewSquad(account, 6);
      _createNewSquad(account, 6);
    }

    contracts.playerBonus.resetBonusOf(account);

    emit PlayerRegistered(account);
  }

  function addToSquad(uint256[] memory nftIds, uint256 squadId) external {
    IBkSquad.Squad storage squad = squads[squadId];
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    require(squad.currentQuest == 0);
    require(squad.nftIds.length + nftIds.length <= squad.size);

    uint256 raritySum;
    for (uint256 i = 0; i < nftIds.length; i++) {
      uint256 nftId = nftIds[i];
      require(contracts.bkNft.ownerOf(nftId) == squad.owner);
      require(contracts.bkNft.squadOf(nftId) == 0);

      // get the NFT's metadata to check whether this is a mouse, cat, or another beast
      IBkChar.BkChar memory nft = contracts.bkNft.getNft(nftId);
      require(_isAllowedToEnter(nft.attributes[0], squadId));

      // add the NFT id to the squad
      squad.nftIds.push(nftId);

      // add the NFT's traits to the squad
      for (uint256 j = 0; j < nft.traits.length; j++) {
        if (nft.traits[j] > 0) {
          squad.traits.push(nft.traits[j]);
        }
      }

      if (nft.collection > 0) {
        squad.collections.push(nft.collection);
      }

      // update the squad's raritySum
      raritySum += nft.attributes[1];

      // update the NFT's squad
      contracts.bkNft.setSquad(nftId, squadId);
    }

    raritySumOfSquad[squadId] += raritySum;

    // update the squad's farming
    _updateSquadFarming(squadId);
  }

  function removeFromSquad(uint256[] memory nftIds, uint256 squadId) external {
    IBkSquad.Squad storage squad = squads[squadId];
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    require(squad.currentQuest == 0);
    require(squad.nftIds.length > 0);

    uint256 raritySum;
    for (uint256 i = 0; i < nftIds.length; i++) {
      uint256 nftId = nftIds[i];
      IBkChar.BkChar memory nft = contracts.bkNft.getNft(nftId);

      require(nft.currentOwner == squad.owner);
      require(nft.squadId == squadId);

      // remove the NFT from the squad
      bool removed;
      for (uint256 j = 0; j < squad.nftIds.length; j++) {
        if (squad.nftIds[j] == nftId) {
          squad.nftIds[j] = squad.nftIds[squad.nftIds.length - 1];
          squad.nftIds.pop();
          removed = true;
          break;
        }
      }
      require(removed);

      if (nft.collection > 0) {
        for (uint256 j = 0; j < squad.collections.length; j++) {
          if (squad.collections[j] == nft.collection) {
            squad.collections[j] = squad.collections[squad.collections.length - 1];
            squad.collections.pop();
            removed = true;
            break;
          }
        }

        require(removed);
      }

      // update the NFT's squad
      contracts.bkNft.setSquad(nftId, 0);

      // Accumulate the NFT's rarity
      raritySum += nft.attributes[1];
    }

    // update the squad's raritySum
    raritySumOfSquad[squadId] -= raritySum;

    // remove the NFT's traits from the squad and update the squad's synergy bonus
    _recalculateSquadTraits(squadId);
    _updateSquadFarming(squadId);
  }

  function clearSquad(uint256 squadId) external {
    IBkSquad.Squad storage squad = squads[squadId];
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    require(squad.currentQuest == 0);
    require(squad.nftIds.length > 0);

    for (uint i = 0; i < squad.nftIds.length; i++) {
      contracts.bkNft.setSquad(squad.nftIds[i], 0);
    }

    squad.nftIds = new uint256[](0);
    squad.collections = new uint256[](0);
    squad.traits = new uint256[](0);
    raritySumOfSquad[squadId] = 0;

    squad.baseFarmPerBlock = 0;
    squad.synergyBonus = 0;
    squad.farmPerBlock = 0;
  }

  function withdraw(uint256 amount) public whenNotPaused {
    IBkPlayer.Player storage player = players[msg.sender];
    require(player.bctToClaim >= amount);
    require(player.lastWithdrawalBlock + config.withdrawalInterval <= block.number);

    uint256 burnAmount = ((amount * 15) / 100);
    uint256 remainingAmount = amount - burnAmount;

    player.bctToClaim -= amount;
    player.lastWithdrawalBlock = block.number;

    contracts.bct.transfer(msg.sender, remainingAmount);

    emit Withdraw(msg.sender, amount, burnAmount);
  }

  function transfer(address to, uint256 bct, uint256 ebct, uint256[] memory _resources) public {
    _transfer(msg.sender, to, bct, ebct, _resources);
  }

  //################
  // UPDATER functions
  function startQuestFor(uint256 squadId, uint256 questId) external onlyRole(UPDATER_ROLE) {
    IBkSquad.Squad storage squad = squads[squadId];
    require(squad.currentQuest == 0);

    // get the quest's metadata
    IBkQuest.Quest memory quest = quests[questId];
    require(quest.id > 0);

    // check if the squad has the required amount of NFTs
    require(squad.nftIds.length > 0);

    if (quest.minSynergyMultiplier > 0) {
      require(squad.synergyBonus >= quest.minSynergyMultiplier);
    }

    // check if the squad has at least one of each of the required traits
    if (quest.traits.length > 0) {
      for (uint256 i = 0; i < quest.traits.length; i++) {
        bool hasTrait;
        for (uint256 j = 0; j < squad.traits.length; j++) {
          if (squad.traits[j] == quest.traits[i]) {
            hasTrait = true;
            break;
          }
        }

        if (squad.squadTrait != 0) {
          if (squad.squadTrait == quest.traits[i]) {
            hasTrait = true;
          }
        }

        require(hasTrait);
      }
    }

    // check if the squad has at least one of each of the required collections
    if (quest.collections.length > 0 || quest.anyCollection) {
      for (uint256 i = 0; i < quest.collections.length; i++) {
        bool hasCollection;
        for (uint256 j = 0; j < squad.collections.length; j++) {
          if (squad.collections[j] == quest.collections[i] || quest.anyCollection) {
            hasCollection = true;
            break;
          }
        }

        require(hasCollection);
      }
    }

    // update the squad's current quest
    squad.currentQuest = questId;
    squad.questStartedAt = block.number;

    // emit event
    emit QuestStarted(squad.owner, squadId, questId, squad.farmPerBlock);
  }

  function finishQuestFor(uint256 squadId) external onlyRole(UPDATER_ROLE) {
    IBkSquad.Squad storage squad = squads[squadId];
    uint256 currentQuestId = squad.currentQuest;
    require(currentQuestId > 0);

    // get the quest's metadata
    IBkQuest.Quest memory quest = quests[currentQuestId];

    uint256 durationInBlocks = block.number - squad.questStartedAt;
    require(durationInBlocks >= 8640); // minimum is 1 day

    // update the squad's current quest
    squad.currentQuest = 0;
    squad.questStartedAt = 0;

    IBkPlayer.Player storage player = players[squad.owner];

    // Fetch all multipliers:
    uint256[] memory multipliers = contracts.questRewardCalculator.getBaseMultipliers(
      IBkQuestRewardCalculator.MultiplierRequest({
        squadType: squad.type_,
        numberOfNtfs: squad.nftIds.length,
        raritySum: raritySumOfSquad[squadId],
        synergyBonus: squad.synergyBonus,
        traits: squad.traits.length,
        collections: squad.collections.length,
        durationInBlocks: durationInBlocks,
        account: squad.owner
      })
    );

    uint256 totalBctFarmed;
    if (quest.bctPercentage > 0) {
      totalBctFarmed = (squad.farmPerBlock * quest.bctPercentage * config.scale) / 10000;
      totalBctFarmed = (totalBctFarmed * multipliers[0]) / 100;

      player.bctToClaim += totalBctFarmed;
    }

    uint256 totalEtherealFarmed;
    if (quest.etherealPercentage > 0) {
      totalEtherealFarmed = (squad.farmPerBlock * quest.etherealPercentage * config.scale) / 10000;
      totalEtherealFarmed = (totalEtherealFarmed * multipliers[1]) / 100;

      player.etherealBct += totalEtherealFarmed;
    }

    uint256[] memory resourceCentsFarmed = new uint256[](26);
    for (uint256 i = 0; i < squad.nftIds.length; i++) {
      // get the NFT's data
      IBkChar.BkChar memory nft = contracts.bkNft.getNft(squad.nftIds[i]);

      uint256 species = nft.attributes[0];
      uint256 rarity = nft.attributes[1];

      // Skills: 'Loot' 1 and 2
      resourceCentsFarmed[species - 1] += (quest.resourceMultipliers[0] * rarity * nft.skills[0] * multipliers[2]);

      resourceCentsFarmed[species + 4] += (quest.resourceMultipliers[1] * rarity * nft.skills[1] * multipliers[3]);

      // if type >= 6, it's a special NFT that has a second Basic Loot Skill:
      if (species >= 6) {
        resourceCentsFarmed[species] += (quest.resourceMultipliers[0] * rarity * nft.skills[4] * multipliers[2]);
      }

      // if type >= 11, it's a special NFT that has a second Advanced Loot Skill:
      if (species >= 11) {
        resourceCentsFarmed[species + 5] += (quest.resourceMultipliers[1] * rarity * nft.skills[5] * multipliers[3]);
      }

      // Skill: 'Nuts'
      resourceCentsFarmed[10] += (quest.resourceMultipliers[2] * rarity * nft.skills[2] * multipliers[4]);

      // Skill: Crafting
      for (uint256 j = 3; j < 11; j++) {
        resourceCentsFarmed[j + 8] += (quest.resourceMultipliers[j] * rarity * nft.skills[3] * multipliers[5]);
      }

      // Skill: Crafting Cow and Elephant Boxes
      if (quest.resourceMultipliers.length >= 12) {
        uint256 base = (quest.resourceMultipliers[11] * rarity * nft.skills[3] * multipliers[5]);
        resourceCentsFarmed[19] += species >= 14 ? base * 50 : base; // species 14 (Kaiju) and 15 farm cow boxes as any other resource
      }

      if (quest.resourceMultipliers.length >= 13) {
        uint256 base = (quest.resourceMultipliers[12] * rarity * nft.skills[3] * multipliers[5]);
        resourceCentsFarmed[20] += species >= 15 ? base * 50 : base; // species 15 (Cacodemon) farms elephant boxes as any other resource
      }
    }

    for (uint i = 0; i < resourceCentsFarmed.length; i++) {
      // we divide by day (/8640) and by percentage (/100) only at the end to avoid rounding errors
      resourceBalances[squad.owner][i] += i < 19
        ? resourceCentsFarmed[i] / 864000
        : (resourceCentsFarmed[i] / 864000) / 50; // Cow Box and Elephant box have their farm divided by 50 (so 1 becomes 0.02)
    }

    // emit event
    emit QuestEnded(squad.owner, squadId, currentQuestId, durationInBlocks);
    emit Transfer(address(this), squad.owner, totalBctFarmed, totalEtherealFarmed, resourceCentsFarmed);
  }

  function cancelQuestFor(uint256 squadId) external onlyRole(UPDATER_ROLE) {
    IBkSquad.Squad storage squad = squads[squadId];

    // update the squad's current quest
    squad.currentQuest = 0;
    squad.questStartedAt = 0;
  }

  function addSquadToPlayer(
    address playerAddress,
    uint256 type_,
    uint256 slots
  ) external onlyRole(UPDATER_ROLE) returns (uint256) {
    uint256 squadId = _createNewSquad(playerAddress, type_);
    if (slots > 3) {
      setSquadSize(squadId, slots);
    }
    return squadId;
  }

  function increaseSquadSize(uint256 squadId) external onlyRole(UPDATER_ROLE) {
    squads[squadId].size++;
  }

  function setSquadSize(uint256 squadId, uint256 size) public onlyRole(UPDATER_ROLE) {
    squads[squadId].size = size;
  }

  // Must have tokens in-game; Won't accept BCT directly from Metamask
  function payWithBalance(
    address account,
    uint256 bctAmount,
    uint256[] memory _resources
  ) public onlyRole(UPDATER_ROLE) returns (bool success) {
    IBkPlayer.Player storage player = players[account];
    uint256 totalBctBalance = player.etherealBct + player.bctToClaim;
    require(bctAmount <= totalBctBalance, "noFunds");

    // Pay BCT
    if (bctAmount <= player.etherealBct) {
      _spendBct(account, bctAmount, true);
    } else {
      _spendBct(account, bctAmount - player.etherealBct, false);
      _spendBct(account, player.etherealBct, true);
    }

    // Pay other _Resources
    for (uint i = 0; i < _resources.length; i++) {
      if (_resources[i] <= resourceBalances[account][i]) {
        resourceBalances[account][i] -= _resources[i];
      } else {
        revert("missingResources");
      }
    }

    emit Transfer(account, address(0), 0, 0, _resources);

    return true;
  }

  function spendBctFrom(address account, uint256 amount, bool ethereal) public onlyRole(UPDATER_ROLE) {
    _spendBct(account, amount, ethereal);
  }

  function transferFrom(
    address from,
    address to,
    uint256 bct,
    uint256 ebct,
    uint256[] memory _resources
  ) public onlyRole(UPDATER_ROLE) {
    _transfer(from, to, bct, ebct, _resources);
  }

  function recalculateSquadFarming(uint256 squadId) public onlyRole(UPDATER_ROLE) {
    _recalculateSquadTraits(squadId);
    _updateSquadFarming(squadId);
  }

  function addTo(address playerAddress, uint256 ebct, uint256[] memory _resources) external onlyRole(UPDATER_ROLE) {
    players[playerAddress].etherealBct += ebct;
    for (uint i = 0; i < _resources.length; i++) {
      resourceBalances[playerAddress][i] += _resources[i];
    }

    emit Transfer(address(this), playerAddress, 0, ebct, _resources);
  }

  function setSquadType(uint256 squadId, uint256 type_) external onlyRole(UPDATER_ROLE) {
    squads[squadId].type_ = type_;
  }

  function setSquadTrait(uint256 squadId, uint256 squadTrait) external onlyRole(UPDATER_ROLE) {
    squads[squadId].squadTrait = squadTrait;
  }

  function burnBct(uint256 amount) external onlyRole(UPDATER_ROLE) {
    // do nothing;
  }

  //################
  // Internal/private functions
  function _createNewSquad(address playerAddress, uint256 type_) internal returns (uint256) {
    uint256[] storage playerSquads = players[playerAddress].squads;
    require(playerSquads.length < config.maxSquads);

    uint256 squadId = totalSquads + 1;
    playerSquads.push(squadId);

    uint256 squadBonus = playerSquads.length < 4 ? 0 : (playerSquads.length - 4) * 5;

    squads[squadId] = IBkSquad.Squad({
      owner: playerAddress,
      type_: type_,
      size: 3,
      baseFarmPerBlock: 0,
      synergyBonus: 0,
      squadBonus: squadBonus,
      squadTrait: 0,
      farmPerBlock: 0,
      currentQuest: 0,
      questStartedAt: 0,
      questEndsAt: 0,
      nftIds: new uint256[](0),
      traits: new uint256[](0),
      collections: new uint256[](0)
    });

    totalSquads++;

    return squadId;
  }

  function _updateSquadFarming(uint256 squadId) internal whenNotPaused {
    IBkSquad.Squad storage squad = squads[squadId];
    require(squad.currentQuest == 0, "onQ");

    // update the squad's synergy bonus and farm per block
    squad.baseFarmPerBlock = calculateSquadBaseFarmPerBlock(squadId);
    squad.synergyBonus = calculateTraitSynergy(squad.traits, squad.squadTrait);
    squad.synergyBonus += calculateTraitSynergy(squad.collections, 0);
    squad.farmPerBlock = calculateSquadFarmPerBlock(squadId);
  }

  function _recalculateSquadTraits(uint256 squadId) internal whenNotPaused {
    IBkSquad.Squad storage squad = squads[squadId];

    squad.traits = new uint256[](0);
    for (uint256 i = 0; i < squad.nftIds.length; i++) {
      uint256[] memory traits = contracts.bkNft.traitsOf(squad.nftIds[i]);
      for (uint256 j = 0; j < traits.length; j++) {
        squad.traits.push(traits[j]);
      }
    }
  }

  function _isAllowedToEnter(uint256 type_, uint256 squadId) internal view returns (bool) {
    uint256 squadType = squads[squadId].type_;
    return (type_ == squadType || squadType == 6 || type_ >= 6);
  }

  function _transfer(address from, address to, uint256 bct, uint256 ebct, uint256[] memory _resources) private {
    require((from == msg.sender && !paused()) || hasRole(UPDATER_ROLE, msg.sender));

    if (bct > 0) {
      players[from].bctToClaim -= bct; // will revert if negative
      players[to].bctToClaim += bct;
    }

    if (ebct > 0) {
      players[from].etherealBct -= ebct; // will revert if negative
      players[to].etherealBct += ebct;
    }

    if (_resources.length > 0) {
      for (uint i = 0; i < _resources.length; i++) {
        if (_resources[i] > 0) {
          resourceBalances[from][i] -= _resources[i];
          resourceBalances[to][i] += _resources[i];
        }
      }
    }

    emit Transfer(from, to, bct, ebct, _resources);
  }

  function _spendBct(address account, uint256 amount, bool ethereal) private {
    if (ethereal) {
      players[account].etherealBct -= amount;
      emit Transfer(account, address(0), 0, amount, new uint256[](0));
    } else {
      players[account].bctToClaim -= amount;
      emit Transfer(account, address(0), amount, 0, new uint256[](0));
    }
  }

  //################
  // OPERATOR functions
  function setQuests(uint256[] memory questIds, IBkQuest.Quest[] memory quests_) public onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < quests_.length; i++) {
      quests[questIds[i]] = quests_[i];
    }
  }

  function setScale(uint256 _scale) external onlyRole(OPERATOR_ROLE) {
    config.scale = _scale;
  }

  function setResources(uint256 count) public onlyRole(OPERATOR_ROLE) {
    totalResources = count;
  }

  function approveBctSpending(address to, uint256 amount) external onlyRole(OPERATOR_ROLE) {
    contracts.bct.approve(to, amount);
  }

  function setQuestRewardsCalculator(address questRewardsCalculator_) external onlyRole(OPERATOR_ROLE) {
    contracts.questRewardCalculator = IBkQuestRewardCalculator(questRewardsCalculator_);
  }

  //################
  // Public view/pure functions
  function calculateSquadBaseFarmPerBlock(uint256 squadId) public view returns (uint256) {
    IBkSquad.Squad memory squad = squads[squadId];
    uint256 baseFarmPerBlock = 0;

    // sum the base farm of each NFT that is in this squad
    for (uint256 i = 0; i < squad.nftIds.length; i++) {
      baseFarmPerBlock += contracts.bkNft.farmPerBlockOf(squad.nftIds[i]);
    }

    return baseFarmPerBlock;
  }

  function calculateTraitSynergy(uint256[] memory traits, uint256 extraTrait) public pure returns (uint256) {
    uint256 highestTrait = 0;
    for (uint256 i = 0; i < traits.length; i++) {
      if (traits[i] > highestTrait) {
        highestTrait = traits[i];
      }
    }

    if (extraTrait > highestTrait) {
      highestTrait = extraTrait;
    }

    uint256[] memory _tempTraits = new uint256[](highestTrait + 1);

    for (uint256 i = 0; i < traits.length; i++) {
      _tempTraits[traits[i]]++;
    }

    if (extraTrait != 0) {
      _tempTraits[extraTrait]++;
    }

    uint256 synergy = 0;
    for (uint256 i = 0; i <= highestTrait; i++) {
      if (_tempTraits[i] > 1) {
        if (_tempTraits[i] > 6) {
          _tempTraits[i] = 6;
        }
        synergy += _tempTraits[i] ** 2;
      }
    }
    return synergy * 10;
  }

  function calculateSquadFarmPerBlock(uint256 squadId) public view returns (uint256) {
    IBkSquad.Squad storage squad = squads[squadId];

    // Multiply the base farm by the synergy bonus and add that to the base farm
    uint256 farming = squad.baseFarmPerBlock + (squad.baseFarmPerBlock * squad.synergyBonus) / 100;

    // Apply the squad bonus
    farming = farming + (farming * squad.squadBonus) / 100;

    return farming;
  }

  function getSquad(uint256 squadId) public view returns (IBkSquad.Squad memory) {
    IBkSquad.Squad memory squad = squads[squadId];

    return squad;
  }

  function squadsOf(address playerAddress) public view returns (IBkSquad.Squad[] memory) {
    uint totalPlayerSquads = players[playerAddress].squads.length;
    IBkSquad.Squad[] memory playerSquads = new IBkSquad.Squad[](totalPlayerSquads);
    for (uint i = 0; i < totalPlayerSquads; i++) {
      playerSquads[i] = getSquad(players[playerAddress].squads[i]);
    }

    return playerSquads;
  }

  function isSquadOnQuest(uint256 squadId) public view returns (bool) {
    return squads[squadId].currentQuest > 0;
  }

  function getPlayer(address playerAddress) public view returns (IBkPlayer.Player memory) {
    IBkPlayer.Player memory player = players[playerAddress];

    return player;
  }

  function getQuest(uint256 questId) public view returns (IBkQuest.Quest memory) {
    IBkQuest.Quest memory quest = quests[questId];

    return quest;
  }

  function mentorOf(address playerAddress) public view returns (address mentor, uint256 mentorLevel) {
    mentor = players[playerAddress].mentor;
    return (mentor, players[mentor].mentorLevel);
  }

  function balancesOf(address playerAddress) public view returns (uint256[] memory) {
    IBkPlayer.Player memory player = players[playerAddress];
    uint256[] memory balances = new uint256[](totalResources + 1);

    balances[0] = player.bctToClaim + player.etherealBct;

    for (uint256 i = 0; i < totalResources; i++) {
      balances[i + 1] = resourceBalances[playerAddress][i];
    }

    return balances;
  }

  function singleBalanceOf(address playerAddress, uint256 resourceId) public view returns (uint256) {
    return resourceBalances[playerAddress][resourceId];
  }

  function bctBalanceOf(address playerAddress) public view returns (uint256) {
    return players[playerAddress].bctToClaim;
  }
}
