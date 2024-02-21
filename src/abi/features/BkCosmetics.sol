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

contract BkCosmetics is AdministrableUpgradable2024, PaymentReceiver {
  using EasyBkChar for IBkChar.BkChar;

  struct Contracts {
    IBkFarm farm;
    IBkNft nft;
    IBkStasher stasher;
    IBkFetch balances;
  }
  Contracts public contracts;

  mapping(uint256 => uint256[]) public beastIdToSpecialProps; // beastId => [what, ever, comes, here, but, only, uint256]

  uint256 scale;

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    scale = 50; // starting scale
  }

  function getChangeNameCosts(uint256 beastType) public view returns (uint256 _bct, uint256[] memory _resources) {
    // it costs (10 * beastType) eBCT, plus 1 Golden Nut (index 10), plus 1 Gene Therapy (resource index 11) to change the name
    _bct = 32 * beastType;
    _resources = new uint256[](12);
    _resources[10] = 1;
    _resources[11] = 1;

    return ((_bct * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function getChangeImageCosts(uint256 beastType) public view returns (uint256 _bct, uint256[] memory _resources) {
    // it costs (10 * beastType) eBCT, plus 1 Golden Nut (index 10), plus 1 Gene Therapy (resource index 11) to change the name
    _bct = 32 * beastType;
    _resources = new uint256[](12);
    _resources[10] = 1;
    _resources[11] = 1;

    return ((_bct * 1e18 * scale) / 50, _resources); // we divide by 50 because it was the original scale
  }

  function changeName(uint256[] calldata beastIds, string[] calldata newNames, bool withBusd) public {
    for (uint i = 0; i < beastIds.length; i++) {
      IBkChar.BkChar memory beast = contracts.nft.getNft(beastIds[i]);
      require(beast.evos() >= 1, "1"); // must have gone through at least one evolution
      require(beast.currentOwner == msg.sender, "2"); // must be the owner of the beast

      // let's charge the player:
      (uint256 _bct, uint256[] memory _resources) = getChangeNameCosts(beast.species());
      _receivePayment(_bct, _resources, PaymentOptions(true, false, withBusd, false));

      // We'll set the beast's name and keep its current image
      contracts.nft.setNameAndImage(beast.id, newNames[i], beast.imageUrl);
    }
  }

  function changeImage(uint256[] calldata beastIds, string[] calldata newImageUrls, bool withBusd) public {
    for (uint i = 0; i < beastIds.length; i++) {
      IBkChar.BkChar memory beast = contracts.nft.getNft(beastIds[i]);
      require(beast.evos() >= 1, "1"); // must have gone through at least one evolution
      require(beast.currentOwner == msg.sender, "2"); // must be the owner of the beast

      // let's charge the player:
      (uint256 _bct, uint256[] memory _resources) = getChangeImageCosts(beast.species());
      _receivePayment(_bct, _resources, PaymentOptions(true, false, withBusd, false));

      // We'll set the beast's name and keep its current image
      contracts.nft.setNameAndImage(beast.id, beast.name, newImageUrls[i]);
    }
  }

  ////////////////////
  // Operator Functions:
  function setContracts(
    address _farm,
    address _nft,
    address _stasher,
    address _balances
  ) external onlyRole(OPERATOR_ROLE) {
    contracts = Contracts({
      farm: IBkFarm(_farm),
      nft: IBkNft(_nft),
      stasher: IBkStasher(_stasher),
      balances: IBkFetch(_balances)
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
}
