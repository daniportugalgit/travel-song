// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// @dev: remove require messages from the 3 following contracts to save on bytecode (you must)
import "../utils/AdministrableUpgradable2024.sol";
import "../utils/PaymentReceiver.sol";

import "../interfaces/IBkFarm.sol";

import "../interfaces/IBkStasher.sol";
import "../interfaces/IBkPlayerBonus.sol";
import "../erc721/interfaces/IBkNft.sol";

import "../erc721/EasyBkChar.sol";

contract BkQuestManager is AdministrableUpgradable2024, PaymentReceiver {
  using EasyBkChar for IBkChar.BkChar;

  struct Contracts {
    IBkFarm farm;
    IBkNft nft;
    IBkStasher stasher;
    IBkPlayerBonus playerBonus;
  }
  Contracts public contracts;

  struct SpecialQuest {
    uint256 id;
    uint256 costInBct; // cost in BCT /eBCT
    uint256[] costInResources;
    uint8[] requiredDreamBeasts; // an array with up to 10 integers ranging from 0 to 6
    uint8 requiredMaxedOutNfts; // minimum number of maxedOutNfts to enter the quest
    uint256[] extraRewardInResources;
    uint256 extraRewardInBct; // extra reward in BCT
    uint256 extraRewardInEbct; // extra reward in eBCT
  }
  mapping(uint256 => SpecialQuest) specialQuests; // questId => specialQuest
  mapping(address => mapping(uint256 => bool)) public ongoingSpecialQuestIdsPerPlayer; // player => questId => isOngoing

  event ResourcesTransfered(address indexed player, uint256 eBct, uint256[] resources);
  event BctTransfered(address indexed player, uint256 bct);

  // UPGRADED VARS:
  mapping(uint256 => bool) public deletedQuests; // questId => isDeleted

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);
  }

  function startQuest(uint256 squadId, uint256 questId) external {
    require(!deletedQuests[questId], "88");

    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    // check if this is a specialQuest; if it is, we want to check conditions to enter
    SpecialQuest memory specialQuest = specialQuests[questId];
    if (specialQuest.id > 0) {
      // first, check if this player is already doing this quest with any other squad:
      require(!ongoingSpecialQuestIdsPerPlayer[squad.owner][questId], "0");

      // check if the squad has the required beasts:
      if (specialQuest.requiredMaxedOutNfts > 0 || specialQuest.requiredDreamBeasts.length > 0) {
        (uint8 maxedOutCount, uint8[] memory dreamBeastsCount) = _getSquadSpecialBeastCount(squadId);

        require(maxedOutCount >= specialQuest.requiredMaxedOutNfts, "1");

        for (uint256 i = 0; i < specialQuest.requiredDreamBeasts.length; i++) {
          require(dreamBeastsCount[i] >= specialQuest.requiredDreamBeasts[i], "2");
        }
      }

      // finally, if the quest costs dream resources or BCT, we need to charge the user:
      if (specialQuest.costInResources.length > 0) {
        uint256 stasherLevel = contracts.stasher.levelOf(squad.owner);
        require(stasherLevel >= 9, "4");
        _receivePayment(specialQuest.costInBct, specialQuest.costInResources, PaymentOptions(true, true, false, false));
      }

      ongoingSpecialQuestIdsPerPlayer[squad.owner][questId] = true;
    }

    contracts.farm.startQuestFor(squadId, questId);
  }

  function _getSquadSpecialBeastCount(
    uint256 squadId
  ) internal view returns (uint8 maxedOutCount, uint8[] memory dreamBeastsCount) {
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);

    dreamBeastsCount = new uint8[](10);
    // let's check if each beast is maxed out
    for (uint256 i = 0; i < squad.nftIds.length; i++) {
      bool isMaxedOut = true;
      IBkChar.BkChar memory nft = contracts.nft.getNft(squad.nftIds[i]);
      if (nft.rank() < 99) isMaxedOut = false;
      if (nft.agility() < 5) isMaxedOut = false;
      if (nft.nuts() < 50) isMaxedOut = false;
      if (nft.evos() < 11) isMaxedOut = false;
      if (nft.rarity() < 4) isMaxedOut = false;
      if (nft.traits.length < 3) isMaxedOut = false;

      uint8 extraSkillLevels = nft.species() < 6 ? 0 : nft.species() < 11 ? 2 : 5;
      if (nft.skills[0] < 5 + extraSkillLevels) isMaxedOut = false;
      if (nft.skills[1] < 5 + extraSkillLevels) isMaxedOut = false;
      if (nft.skills[2] < 5 + extraSkillLevels) isMaxedOut = false;
      if (nft.skills[3] < 5 + extraSkillLevels) isMaxedOut = false;
      if (nft.species() > 5 && nft.skills[4] < 5 + extraSkillLevels) isMaxedOut = false;
      if (nft.species() > 10 && nft.skills[5] < 5 + extraSkillLevels) isMaxedOut = false;

      if (isMaxedOut) maxedOutCount++;

      // let's check if each beast is a dream beast
      if (nft.species() >= 6) dreamBeastsCount[nft.species() - 6]++;
    }

    return (maxedOutCount, dreamBeastsCount);
  }

  function finishQuest(uint256 squadId) external {
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);
    require(squad.currentQuest > 0, "3");
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    if (deletedQuests[squad.currentQuest]) {
      contracts.farm.cancelQuestFor(squadId);
      return;
    }

    // Give extra rewards, if any:
    SpecialQuest memory specialQuest = specialQuests[squad.currentQuest];
    if (specialQuest.id > 0) {
      if (specialQuest.extraRewardInResources.length > 0 || specialQuest.extraRewardInEbct > 0) {
        contracts.farm.addTo(squad.owner, specialQuest.extraRewardInEbct, specialQuest.extraRewardInResources);
        emit ResourcesTransfered(squad.owner, specialQuest.extraRewardInEbct, specialQuest.extraRewardInResources);
      }
      if (specialQuest.extraRewardInBct > 0) {
        contracts.farm.addBctToClaim(squad.owner, specialQuest.extraRewardInBct);
        emit BctTransfered(squad.owner, specialQuest.extraRewardInBct);
      }
    }

    // Finish the quest in our Farm contract:
    contracts.farm.finishQuestFor(squadId);

    // remove the quest from the ongoingSpecialQuestIdsPerPlayer mapping:
    if (ongoingSpecialQuestIdsPerPlayer[squad.owner][squad.currentQuest]) {
      ongoingSpecialQuestIdsPerPlayer[squad.owner][squad.currentQuest] = false;
    }
  }

  function cancelQuest(uint256 squadId) external {
    IBkSquad.Squad memory squad = contracts.farm.getSquad(squadId);
    require(squad.currentQuest > 0, "3");
    _onlyOwnerNotPausedOrUpdater(squad.owner);

    // remove the quest from the ongoingSpecialQuestIdsPerPlayer mapping:
    if (ongoingSpecialQuestIdsPerPlayer[squad.owner][squad.currentQuest]) {
      ongoingSpecialQuestIdsPerPlayer[squad.owner][squad.currentQuest] = false;
    }

    contracts.farm.cancelQuestFor(squadId);
  }

  function _onlyOwnerNotPausedOrUpdater(address account) internal view {
    require((account == msg.sender && !paused()) || hasRole(UPDATER_ROLE, msg.sender));
  }

  ////////////////////
  // Operator Functions:
  function setContracts(
    address _farm,
    address _nft,
    address _stasher,
    address _playerBonus
  ) external onlyRole(OPERATOR_ROLE) {
    contracts = Contracts({
      farm: IBkFarm(_farm),
      nft: IBkNft(_nft),
      stasher: IBkStasher(_stasher),
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

  function setQuests(uint256[] memory questIds, SpecialQuest[] memory quests_) public onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < quests_.length; i++) {
      specialQuests[questIds[i]] = quests_[i];
    }
  }

  function setDeletedQuests(uint256[] memory questIds, bool[] memory isDeleted) public onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < questIds.length; i++) {
      deletedQuests[questIds[i]] = isDeleted[i];
    }
  }
}
