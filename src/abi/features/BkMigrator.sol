// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../erc20/interfaces/IBkERC20.sol";
import "../interfaces/IBkFarm.sol";
import "../interfaces/IBkStasher.sol";
import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkFetch.sol";
import "../interfaces/IBkPlayerBonus.sol";
import "../interfaces/IBkForge.sol";
import "../interfaces/IBkDnaManager.sol";

// TODO: este contrato precisa ser MINTER de BCT
// TODO: este contrato precisa ser MINTER e UPDATER de NFTs

contract BkMigrator is AdministrableUpgradable2024 {
  IBkERC20 public bct;
  IBkFarm public farm;
  IBkStasher public stasher;
  IBkNft public nft;
  IBkFetch public fetch;
  IBkPlayerBonus public playerBonus;
  IBkForge public forge;
  IBkDnaManager public dnaManager;

  mapping(address => uint256) public migratedAtBlockPlayer; // account => blockNumber
  mapping(address => uint256) public migratedAtBlockBctAndResources; // account => blockNumber
  mapping(address => uint256) public migratedAtBlockMarketplaceResources; // account => blockNumber
  mapping(address => uint256) public migratedAtPlayerBonus; // account => blockNumber
  mapping(address => uint256) public migratedAtBlockStash; // account => blockNumber
  mapping(address => uint256) public migratedAtBlockCraftingPowder; // account => blockNumber
  mapping(uint256 => uint256) public migratedAtBlockNft; // nftId => blockNumber

  event BnbChainSnapshot(address account, uint256 metamaskBct, uint256 ingameBct, uint256 eBct, uint256[] resources);
  event BctMigrated(address account, uint256 amount);
  event ResourcesMigrated(address account, uint256 eBct, uint256[] resources);
  event BeastsMigrated(uint256[] nftIds);
  event StashMigrated(address account, uint256 amount);
  event PlayerBonusMigrated(address account, uint256[] perks, uint256[] masteries);
  event CraftingPowderMigrated(address account, uint256 amount);
  event CollectionMigrated(address account, uint256 collectionId, uint256[] nftIds);

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);
  }

  ////////////////////////////
  // UPDATER functions:
  // Nfts that belong to non-verified players will be killed in the mgiration
  // It IS possible to revive them via the function nft.setIsDead(uint256 tokenId, bool isDead);
  function migrateNfts(IBkChar.BkChar[] memory beasts) external whenNotPaused onlyRole(UPDATER_ROLE) {
    for (uint256 i = 0; i < beasts.length; i++) {
      require(migratedAtBlockNft[beasts[i].id] == 0, "already migrated");
      migratedAtBlockNft[beasts[i].id] = block.number;
    }

    nft.migrate(beasts);

    uint256[] memory nftIds = new uint256[](beasts.length);
    for (uint256 i = 0; i < beasts.length; i++) {
      nftIds[i] = beasts[i].id;
    }
    emit BeastsMigrated(nftIds);
  }

  function migrateSquads(
    address account,
    uint256[] memory squadSlots,
    uint256[] memory squadTypes,
    uint256[] memory squadTraits
  ) external whenNotPaused onlyRole(UPDATER_ROLE) {
    require(migratedAtBlockPlayer[account] == 0, "already migrated");

    migratedAtBlockPlayer[account] = block.number;

    // register the player
    farm.registerPlayer(account, false);

    for (uint256 i = 0; i < squadSlots.length; i++) {
      farm.addSquadToPlayer(account, squadTypes[i], squadSlots[i]);

      if (squadTraits[i] > 0) {
        farm.setSquadTrait(squadSlots[i], squadTraits[i]);
      }
    }
  }

  // InGameBalances:  {bct, eBct, resources};
  // MetmaskBalances:  {bct, stabletoken};
  function migrateBctAndResources(
    address account,
    IBkFetch.InGameBalances memory inGameBalances,
    IBkFetch.MetamaskBalances memory metamaskBalances
  ) external whenNotPaused onlyRole(UPDATER_ROLE) {
    require(migratedAtBlockBctAndResources[account] == 0, "already migrated");

    migratedAtBlockBctAndResources[account] = block.number;
    emit BnbChainSnapshot(
      account,
      metamaskBalances.bct,
      inGameBalances.bct,
      inGameBalances.eBct,
      inGameBalances.resources
    );

    // all the BCT the user has, adding together the BCT to claim and the metamask BCT
    uint256 bctToMigrate = inGameBalances.bct + metamaskBalances.bct;
    bct.mint(account, bctToMigrate);
    emit BctMigrated(account, bctToMigrate);

    // all the resources the user has, and the eBct, are added to the user on the Farm
    farm.addTo(account, inGameBalances.eBct, inGameBalances.resources);
    emit ResourcesMigrated(account, inGameBalances.eBct, inGameBalances.resources);
  }

  function migrateStash(address account, uint256 amount) external whenNotPaused onlyRole(UPDATER_ROLE) {
    require(migratedAtBlockStash[account] == 0, "already migrated");

    migratedAtBlockStash[account] = block.number;
    stasher.migrateStash(account, amount);

    emit StashMigrated(account, amount);
  }

  function migratePlayerBonus(
    address account,
    uint256[] memory perks,
    uint256[] memory masteries
  ) external whenNotPaused onlyRole(UPDATER_ROLE) {
    require(migratedAtPlayerBonus[account] == 0, "already migrated");

    migratedAtPlayerBonus[account] = block.number;

    IBkPlayerBonus.Player memory player = IBkPlayerBonus.Player({
      stash: perks[0],
      mythicMints: perks[1],
      item: perks[2],
      special: perks[3],
      fortuneLevel: perks[4],
      total: perks[5]
    });

    playerBonus.setAllOf(account, player, masteries);

    emit PlayerBonusMigrated(account, perks, masteries);
  }

  function migrateCraftingPowder(address account, uint256 amount) external whenNotPaused onlyRole(UPDATER_ROLE) {
    require(migratedAtBlockCraftingPowder[account] == 0, "already migrated");

    migratedAtBlockCraftingPowder[account] = block.number;

    forge.addTo(account, amount);

    emit CraftingPowderMigrated(account, amount);
  }

  function migrateCollections(
    IBkDnaManager.Collection[] memory _collections
  ) external whenNotPaused onlyRole(UPDATER_ROLE) {
    dnaManager.setCollections(_collections);

    for (uint256 i = 0; i < _collections.length; i++) {
      emit CollectionMigrated(_collections[i].creator, _collections[i].id, _collections[i].nftIds);
    }
  }

  ////////////////////////////
  // Operator Functions
  function setContracts(
    address _bct,
    address _farm,
    address _stasher,
    address _nft,
    address _fetch,
    address _playerBonus,
    address _forge,
    address _dnaManager
  ) public onlyRole(OPERATOR_ROLE) {
    bct = IBkERC20(_bct);
    farm = IBkFarm(_farm);
    stasher = IBkStasher(_stasher);
    nft = IBkNft(_nft);
    fetch = IBkFetch(_fetch);
    playerBonus = IBkPlayerBonus(_playerBonus);
    forge = IBkForge(_forge);
    dnaManager = IBkDnaManager(_dnaManager);
  }
}
