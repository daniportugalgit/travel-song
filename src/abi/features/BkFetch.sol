// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../erc20/interfaces/IBkERC20.sol";
import "../interfaces/IBkStasher.sol";
import "../interfaces/ICommunityPool.sol";
import "../interfaces/IBkFarm.sol";
import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkPlayerBonus.sol";

contract BkFetch is AdministrableUpgradable2024 {
  // Contracts
  struct Contracts {
    IBkERC20 bct;
    IBkERC20 stabletoken;
    IBkStasher stasher;
    ICommunityPool pool;
    IBkFarm farm;
    IBkNft nft;
    IBkPlayerBonus playerBonus;
  }
  Contracts public contracts;

  struct InGameBalances {
    uint256 bct;
    uint256 eBct;
    uint256[] resources;
  }

  struct MetamaskBalances {
    uint256 bct;
    uint256 stabletoken;
  }

  uint256 public totalResources;
  mapping(uint256 => address) public resources;

  uint256 farmingScale;
  uint256 pricesScale;

  function initialize(
    address _operator,
    address _blocklist,
    address _bct,
    address _stabletoken,
    address _stasher,
    address _pool,
    address _farm,
    address _nft,
    address _playerBonus
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    contracts = Contracts({
      bct: IBkERC20(_bct),
      stabletoken: IBkERC20(_stabletoken),
      stasher: IBkStasher(_stasher),
      pool: ICommunityPool(_pool),
      farm: IBkFarm(_farm),
      nft: IBkNft(_nft),
      playerBonus: IBkPlayerBonus(_playerBonus)
    });
  }

  function balancesOf(address account) public view returns (InGameBalances memory, MetamaskBalances memory) {
    return (_inGameBalancesOf(account), _metamaskBalancesOf(account));
  }

  function inGameBalancesOf(address account) external view returns (InGameBalances memory) {
    return _inGameBalancesOf(account);
  }

  function metamaskBalancesOf(address account) external view returns (MetamaskBalances memory) {
    return _metamaskBalancesOf(account);
  }

  function supply()
    external
    view
    returns (uint256 bctTotalSupply, uint256 farm, uint256 pool, uint256[] memory _resources)
  {
    bctTotalSupply = contracts.bct.totalSupply();
    farm = contracts.bct.balanceOf(address(contracts.farm));
    (pool, ) = contracts.pool.getReserves();

    _resources = new uint256[](totalResources);
    for (uint256 i = 0; i < totalResources; i++) {
      _resources[i] = IBkERC20(resources[i]).totalSupply();
    }
  }

  function getResources() external view returns (address[] memory) {
    // transform mapping to array
    address[] memory result = new address[](totalResources);
    for (uint256 i = 0; i < totalResources; i++) {
      result[i] = resources[i];
    }

    return result;
  }

  function getPlayerNfts(address account) external view returns (IBkChar.BkChar[] memory nfts) {
    nfts = contracts.nft.nftsOfOwner(account);
  }

  function getBeasts(uint256[] memory nftIds) external view returns (IBkChar.BkChar[] memory nfts) {
    nfts = contracts.nft.getNfts(nftIds);
  }

  function getEverything(
    address account
  )
    external
    view
    returns (
      IBkPlayer.Player memory player,
      IBkSquad.Squad[] memory squads,
      IBkChar.BkChar[] memory nfts,
      InGameBalances memory ingameBalances,
      uint256 stasherBalance,
      IBkPlayerBonus.Player memory playerBonus,
      uint256[] memory masteries,
      uint256 bctMetamaskBalance,
      uint256 stabletokenBalance
    )
  {
    player = contracts.farm.getPlayer(account);
    squads = contracts.farm.squadsOf(account);
    nfts = contracts.nft.nftsOfOwner(account);

    ingameBalances = _inGameBalancesOf(account);
    stasherBalance = contracts.stasher.balanceOf(account);
    (playerBonus, masteries) = contracts.playerBonus.detailedBonusOf(account);

    bctMetamaskBalance = contracts.bct.balanceOf(account);
    stabletokenBalance = contracts.stabletoken.balanceOf(account);
  }

  function getContracts() external view returns (Contracts memory) {
    return contracts;
  }

  // Private functions
  function _inGameBalancesOf(address account) private view returns (InGameBalances memory) {
    IBkPlayer.Player memory player = contracts.farm.getPlayer(account);
    uint256[] memory originalInGameResources = contracts.farm.balancesOf(account);
    uint256[] memory finalInGameResources;

    // Get a new array with all elements but the first:
    if (originalInGameResources.length > 1) {
      finalInGameResources = new uint256[](originalInGameResources.length - 1);
      for (uint256 i = 1; i < originalInGameResources.length; i++) {
        finalInGameResources[i - 1] = originalInGameResources[i];
      }
    }

    return InGameBalances({bct: player.bctToClaim, eBct: player.etherealBct, resources: finalInGameResources});
  }

  function _metamaskBalancesOf(address account) private view returns (MetamaskBalances memory) {
    uint256 metamaskBct = contracts.bct.balanceOf(account);
    uint256 metamaskStabletoken = contracts.stabletoken.balanceOf(account);

    return MetamaskBalances({bct: metamaskBct, stabletoken: metamaskStabletoken});
  }

  // Operator functions
  function setResources(uint256 count) public onlyRole(OPERATOR_ROLE) {
    totalResources = count;
  }

  function setContracts(
    address farmAddress,
    address bctAddress,
    address stabletokenAddress,
    address poolAddress,
    address stasherAddress,
    address nftAddress,
    address playerBonusAddress
  ) external onlyRole(OPERATOR_ROLE) {
    contracts.bct = IBkERC20(bctAddress);
    contracts.stabletoken = IBkERC20(stabletokenAddress);
    contracts.stasher = IBkStasher(stasherAddress);
    contracts.pool = ICommunityPool(poolAddress);
    contracts.farm = IBkFarm(farmAddress);
    contracts.nft = IBkNft(nftAddress);
    contracts.playerBonus = IBkPlayerBonus(playerBonusAddress);
  }
}
