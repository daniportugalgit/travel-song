// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../../utils/AdministrableUpgradable2024.sol";
import "../../../erc20/interfaces/IBkERC20.sol";
import "../../../interfaces/IKoziPool.sol";
import "./sigGuardian/KingdomBridgeSigGuardian.sol";

/**
 * @title Kingdom Bridge
 * @author Kozika
 * @notice Hosted on the Kingdom Chain, this contract allows users to deposit stabletokens from the Kingdom Chain into the BNB Chain
 *         and to claim stabletokens from the BNB Chain into the Kingdom Chain.
 *         It also allows users to convert their BNB chain Stabletokens into Kozi, receiving it directly on the Kingdom Chain.
 */
contract KingdomBridge is KingdomBridgeSigGuardian, AdministrableUpgradable2024 {
  IBkERC20 public stabletoken; // a trusted ERC20 token on the Kingdom Chain
  IKoziPool public koziPool; // a trusted KoziPool contract on the Kingdom Chain

  mapping(address => uint256) public stabletokensDepositedBy;
  mapping(address => uint256) public stabletokensWithdrawnBy;
  mapping(address => uint256) public stabletokensBalanceOf;
  mapping(address => uint256) public totalKoziReceivedBy;
  mapping(address => uint256) public lastClaimReceivedBlock;

  event DepositStabletokens(address from, uint256 amount); // Direction: from the Kingdom Chain into the BNB Chain
  event NewClaim(address playerAddress, uint256 stabletokens, bool convertToKozi, bytes32 depositHash); // Direction: from the BNB Chain into the Kingdom Chain
  // These events are the claim resolution events:
  event TransferStabletokens(address from, address to, uint256 amount);
  event TransferKozi(address from, address to, uint256 amount);
  event ReceiveKozi(address from, uint256 amount);

  function initialize(
    address _operator,
    address _blocklist,
    address _stabletoken,
    address _koziPool,
    address _initialValidator
  ) public initializer {
    __Administrable_init(_operator, _blocklist);
    _initSigGuardian(_initialValidator);

    stabletoken = IBkERC20(_stabletoken);
    koziPool = IKoziPool(_koziPool);
    stabletoken.approve(_koziPool, type(uint256).max);
  }

  // Direction: from the Kingdom Chain into the BNB Chain
  function depositStabletokens(uint256 amount) external payable mutex whenNotPaused notBlocklisted(msg.sender) {
    require(amount > 0, "amount=0");

    stabletoken.transferFrom(msg.sender, address(this), amount);
    stabletokensDepositedBy[msg.sender] += amount;

    // now burn the received tokens:
    stabletoken.burn(amount);

    emit DepositStabletokens(msg.sender, amount);
  }

  // Direction: from the BNB Chain into the Kingdom Chain
  // The updater role is responsible for adding claims to the bridge
  // Claims resolve immediately, sending either Kozi or Stabletokens to the player
  function transpose(
    bytes32 hashDigest,
    ClaimData memory claimData,
    SignatureData calldata signatureData
  ) external mutex whenNotPaused onlyRole(UPDATER_ROLE) notBlocklisted(claimData.playerAddress) {
    require(claimData.stabletokens > 0, "stabletokens=0");
    _validateClaim(hashDigest, claimData, signatureData);

    // Passed! Let's update the last claim block
    lastClaimReceivedBlock[claimData.playerAddress] = block.number;

    emit NewClaim(claimData.playerAddress, claimData.stabletokens, claimData.convertToKozi, claimData.depositHash);

    if (claimData.convertToKozi) {
      // mint the stabletokens to this contract
      // function bridgeFromChain(uint256 fromChainId,address fromAddress,address toAddress,uint256 amount)
      stabletoken.bridgeFromChain(56, claimData.playerAddress, address(this), claimData.stabletokens);

      // figure out how much Kozi we can get for the stabletokens
      uint256 koziOut = koziPool.quoteStableToKozi(claimData.stabletokens);

      // buy Kozi with the stabletokens
      koziPool.buyKozi(koziOut);

      // send the Kozi to the player
      payable(claimData.playerAddress).transfer(koziOut);
      emit TransferKozi(address(this), claimData.playerAddress, koziOut);
    } else {
      // mint the stabletokens to the player
      // function bridgeFromChain(uint256 fromChainId,address fromAddress,address toAddress,uint256 amount)
      stabletoken.bridgeFromChain(56, claimData.playerAddress, claimData.playerAddress, claimData.stabletokens);

      // update the player's stabletokens balance
      stabletokensWithdrawnBy[claimData.playerAddress] += claimData.stabletokens;
      emit TransferStabletokens(address(this), claimData.playerAddress, claimData.stabletokens);
    }
  }

  // receive function:
  receive() external payable {
    emit ReceiveKozi(msg.sender, msg.value);
  }
}
