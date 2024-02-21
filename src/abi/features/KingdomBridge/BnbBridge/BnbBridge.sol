// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../../utils/AdministrableUpgradable2024.sol";
import "../../../erc20/interfaces/IBkERC20.sol";
import "./sigGuardian/BnbBridgeSigGuardian.sol";

contract BnbBridge is BnbBridgeSigGuardian, AdministrableUpgradable2024 {
  IBkERC20 public stabletoken; // a trusted ERC20 token on the Binance Smart Chain

  mapping(address => uint256) public deposited;
  mapping(address => uint256) public withdrawn;
  mapping(address => uint256) public balances;
  mapping(address => uint256) public lastClaimReceivedBlock;

  event DepositStabletokens(address from, uint256 amount, bool convertToKozi);
  event AddClaim(address playerAddress, uint256 stabletokens, bytes32 depositHash);
  event Claim(address playerAddress, uint256 stabletokens);

  function initialize(
    address _operator,
    address _blocklist,
    address _stabletoken,
    address _initialValidator
  ) public initializer {
    __Administrable_init(_operator, _blocklist);
    _initSigGuardian(_initialValidator);

    stabletoken = IBkERC20(_stabletoken);
  }

  // Direction: from BNB Chain into the Kingdom Chain
  function depositStabletokens(
    uint256 amount,
    bool convertToKozi
  ) external payable mutex whenNotPaused notBlocklisted(msg.sender) {
    require(amount > 0, "amount=0");

    stabletoken.transferFrom(msg.sender, address(this), amount);
    deposited[msg.sender] += amount;

    emit DepositStabletokens(msg.sender, amount, convertToKozi);
  }

  // Direction: from the Kingdom Chain into the BNB Chain
  // The updater role is responsible for adding claims to the bridge
  function addClaim(
    bytes32 hashDigest,
    ClaimData memory claimData,
    SignatureData calldata signatureData
  ) external mutex whenNotPaused onlyRole(UPDATER_ROLE) {
    _validateClaim(hashDigest, claimData, signatureData);

    // Passed! Let's update the last claim block
    lastClaimReceivedBlock[claimData.playerAddress] = block.number;
    balances[claimData.playerAddress] += claimData.stabletokensOut;

    require(claimData.stabletokensOut <= stabletoken.balanceOf(address(this)), "not enough stabletokens");

    emit AddClaim(claimData.playerAddress, claimData.stabletokensOut, claimData.depositHash);
  }

  // Direction: from the BNB Chain to itself
  // The player can claim their stabletokens from the bridge, but only once per day
  function claim() external mutex whenNotPaused notBlocklisted(msg.sender) {
    require(balances[msg.sender] > 0, "no balance");
    require(block.number > lastClaimReceivedBlock[msg.sender] + 25920, "too soon"); // 25920 blocks = 3 days

    uint256 amount = balances[msg.sender];
    withdrawn[msg.sender] += amount;
    balances[msg.sender] = 0;

    stabletoken.transfer(msg.sender, amount);

    emit Claim(msg.sender, amount);
  }
}
