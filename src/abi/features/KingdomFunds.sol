// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../erc20/interfaces/IBkERC20.sol";

/*
Known Funds at deployment:
1: Cosmic Fund (4%)
2: Beast Kingdom Commonwealth Fund (4%)
3: Crystal Ball Fund (3%)
4: Noble Fortune Saga Fund (1.5%)
*/

contract KingdomFunds is AdministrableUpgradable2024 {
  IBkERC20 public stableToken; // a trusted ERC20 token

  struct Fund {
    uint256 number; // 1-indexed
    uint256 stabletoken;
    address directTransferBeneficiary; // if set, this address will receive the funds directly, instead of having to withdraw them
  }
  mapping(uint256 => Fund) public funds;
  mapping(uint256 => mapping(address => bool)) private _fundBeneficiaries; // fundNumber => => account => isBeneficiary

  uint256 public totalAccumulatedStabletokens;

  event Deposit(address from, uint256 fundNumber, uint256 stabletokens);
  event Withdraw(address to, uint256 fundNumber, uint256 amount);
  event SetBeneficiary(uint256 fundNumber, address beneficiary, bool isActive);

  function initialize(address _operator, address _blocklist, address _stableToken) public initializer {
    __Administrable_init(_operator, _blocklist);

    stableToken = IBkERC20(_stableToken);

    // Set the BK Commonwealth Fund wallet as direct beneficiary of the Beast Kingdom Commonwealth Fund
    // @dev: direct beneficiaries *must* be trusted EOAs or contracts
    funds[2] = Fund(2, 0, 0x4BD1e4cdDf8862cDC0D51A282110F65Af2D1E4f6);
  }

  ////////////////////////////
  // View functions:
  function getFund(uint256 fundNumber) external view returns (Fund memory) {
    return funds[fundNumber];
  }

  function balanceOf(uint256 fundNumber) external view returns (uint256) {
    return funds[fundNumber].stabletoken;
  }

  function getFundDirectTransferBeneficiary(uint256 fundNumber) external view returns (address) {
    return funds[fundNumber].directTransferBeneficiary;
  }

  function isFundBeneficiary(uint256 fundNumber, address account) public view returns (bool) {
    return _fundBeneficiaries[fundNumber][account];
  }

  ////////////////////////////
  // UPDATER functions:
  function deposit(uint256 fundNumber, uint256 amount) external onlyRole(UPDATER_ROLE) {
    require(fundNumber > 0, "1");
    require(amount > 0, "2");

    // transfer amount from msg.sender to this contract
    stableToken.transferFrom(msg.sender, address(this), amount);

    if (funds[fundNumber].directTransferBeneficiary != address(0)) {
      // if the fund has a directTransferBeneficiary, we'll transfer the amount to them
      stableToken.transfer(funds[fundNumber].directTransferBeneficiary, amount);
    } else {
      // update the fund
      funds[fundNumber].stabletoken += amount;
    }

    // update the totalAccumulatedStabletokens
    totalAccumulatedStabletokens += amount;

    emit Deposit(msg.sender, fundNumber, amount);
  }

  function withdraw(uint256 fundNumber, uint256 amount) external mutex whenNotPaused {
    require(amount > 0, "5");
    require(funds[fundNumber].stabletoken >= amount, "6");
    require(isFundBeneficiary(fundNumber, msg.sender), "7");

    // update the fund
    funds[fundNumber].stabletoken -= amount;

    // transfer `amount` from this contract to msg.sender
    stableToken.transfer(msg.sender, amount);

    emit Withdraw(msg.sender, fundNumber, amount);
  }

  ////////////////////////////
  // Operator Functions
  function setBeneficiary(uint256 fundNumber, address beneficiary, bool isActive) external onlyRole(OPERATOR_ROLE) {
    require(fundNumber > 0, "12");

    _fundBeneficiaries[fundNumber][beneficiary] = isActive;

    emit SetBeneficiary(fundNumber, beneficiary, isActive);
  }

  function setBkCommonwealthFund(address beneficiary) external onlyRole(OPERATOR_ROLE) {
    funds[2].directTransferBeneficiary = beneficiary;
  }
}
