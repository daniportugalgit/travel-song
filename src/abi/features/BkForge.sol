// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../utils/PaymentReceiver.sol";

/**
 * @title BkForge
 */
contract BkForge is AdministrableUpgradable2024, PaymentReceiver {
  mapping(uint256 => uint256) public baseBalanceOf;
  mapping(uint256 => uint256) public lastUpdateBlockOf;

  mapping(uint256 => uint256) public weights; // the weight of each resource (in cents)
  mapping(uint256 => uint256) public costEbct; // the extra cost in ebct of each resource (in cents)
  mapping(uint256 => uint256) public costDrasca; // the extra cost in drasca of each resource (in cents)

  mapping(address => uint256) public powderBalances; // the amount of powder each player has

  bool public craftEnabled;
  bool public meltEnabled;
  bool public buyEbctEnabled;

  // ERC20 features for Crafting Powder:
  string public constant name = "Crafting Powder";
  string public constant symbol = "BKCP";
  uint8 public constant decimals = 2; // like the other resources, this is in cents
  mapping(address => mapping(address => uint256)) public allowances;
  uint256 public totalSupply;

  event Transfer(address from, address to, uint256 value);
  event Approval(address owner, address spender, uint256 value);
  event Craft(address account, uint256 resourceIndex, uint256 amountInUnits, uint256 apeToolsUsed);
  event Melt(address account, uint256 resourceIndex, uint256 amountInUnits);
  event BuyEbct(address account, uint256 stableTokensIn, uint256 ebctAmount);
  event TransferResources(address from, address to, uint256[] resources);
  event TransferEbct(address from, address to, uint256 value);

  // When crafting a resource, it costs its weight, but it costs more the less balance there is (it's a "virtual" balance)
  // When "melting" (selling) a resource, it always pays 1/5 the resource's weight
  // Each Ape tool used grants you a 5% discount on the price of the resource
  // Cost in eBCT: 1/100 of the weight of the resource (unaffected by the kingdom scale)
  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    weights[0] = 100; // Super Cheese
    weights[1] = 150; // Shiny Fish
    weights[2] = 300; // Groovy Grass
    weights[3] = 400; // Happy Roots
    weights[4] = 500; // Bang Bananas

    weights[5] = 300; // Exotic Cheese
    weights[6] = 400; // Cat Milk
    weights[7] = 500; // Magic Mushrooms
    weights[8] = 3000; // Power Mangoes
    weights[9] = 500; // Ape Tools (can't melt)

    weights[10] = 200; // Golden Nuts

    weights[11] = 250; // Gene Therapy
    weights[12] = 300; // Mouse Box
    weights[13] = 400; // Cat Box

    weights[14] = 750; // Mouse Dna
    weights[15] = 1500; // Cat Dna
    weights[16] = 3000; // Cow Dna
    weights[17] = 4500; // Elephant Dna
    weights[18] = 6000; // Ape Dna

    //weights[19] = 0; // Cow Box
    //weights[20] = 0; // Elephant Box
    //weights[21] = 0; // Dragon Scales

    weights[22] = 12000; // Griffin Feathers (can't be melted, can be crafted)
    weights[23] = 20000; // Satyrn Horns (can't be melted, can be crafted)
    weights[24] = 30000; // Dinosaur Skulls (can't be melted, can be crafted)
    weights[25] = 50000; // Ai Chips (can't be melted, can be crafted)
    weights[98] = 10; // eBCT (can't be melted, can be crafted)

    costDrasca[22] = 100; // Griffin Feathers
    costDrasca[23] = 100; // Satyrn Horns
    costDrasca[24] = 100; // Dinosaur Skulls
    costDrasca[25] = 400; // Ai Chips
  }

  function balanceOf(address account) external view returns (uint256) {
    return powderBalances[account];
  }

  function priceOf(
    uint256 resourceIndex,
    uint256 amountInUnits,
    uint256 apeToolsUsed
  ) public view returns (uint256 priceInPowder) {
    require(amountInUnits > 0, "0");
    require(apeToolsUsed <= 10, "2"); // 5% discount per ape tool, up to 50% max discount

    priceInPowder = weights[resourceIndex] * amountInUnits;

    // then we'll apply a discount based on the number of ApeTools used
    // the discount is 5% per ApeTools used up to 50% max total discount
    uint256 discount = apeToolsUsed * 5;
    priceInPowder = (priceInPowder * (100 - discount)) / 100;
  }

  function craftMany(
    uint256[] memory resourceIndexes,
    uint256[] memory amountsInUnits,
    uint256 apeToolsUsed,
    uint256 eBctToCraft
  ) external notBlocklisted(msg.sender) mutex whenNotPaused {
    require(resourceIndexes.length == amountsInUnits.length, "10");
    require(craftEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    uint256 price = 0;
    uint256[] memory _resources = new uint256[](26);
    uint256 costInDrasca = 0;

    for (uint256 i = 0; i < resourceIndexes.length; i++) {
      uint256 resourceIndex = resourceIndexes[i];
      uint256 amountInUnits = amountsInUnits[i];

      require(weights[resourceIndex] > 0, "8"); // can't craft high boxes or Dragon Scales here

      price += priceOf(resourceIndex, amountInUnits, apeToolsUsed);

      // create an array where the resource is the index
      _resources[resourceIndex] = amountInUnits * 100; //the farm likes it in cents
      costInDrasca += amountInUnits * costDrasca[resourceIndex]; // drasca if needed
    }

    if (eBctToCraft > 0) {
      uint256 discount = apeToolsUsed * 5;
      price += ((10 * eBctToCraft) * (100 - discount)) / 100;
    }

    // charge the player
    require(powderBalances[msg.sender] >= price, "9");
    _burn(msg.sender, price);
    if (costInDrasca > 0 || apeToolsUsed > 0) {
      uint256[] memory _resourcesToCharge = new uint256[](22);
      _resourcesToCharge[9] = apeToolsUsed * 100; // Ape Tools
      _resourcesToCharge[21] = costInDrasca; // drasca if needed
      _receivePayment(0, _resourcesToCharge, PaymentOptions(true, true, false, false));
    }

    // send the resources to the player:
    _sendResourcesTo(msg.sender, eBctToCraft * 1e18, _resources);
  }

  function _sendResourcesTo(address to, uint256 eBct, uint256[] memory _resources) private {
    paymentContracts.farm.addTo(to, eBct, _resources);
    emit TransferResources(address(this), to, _resources);

    if (eBct > 0) {
      emit TransferEbct(address(this), to, eBct);
    }
  }

  function meltMany(
    uint256[] memory resourceIndexes,
    uint256[] memory amountsInUnits,
    uint256 apeToolsUsed
  ) external notBlocklisted(msg.sender) mutex whenNotPaused {
    require(resourceIndexes.length == amountsInUnits.length, "10");
    require(meltEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    uint256 yield = 0;
    uint256[] memory _resources = new uint256[](19);

    for (uint256 i = 0; i < resourceIndexes.length; i++) {
      uint256 resourceIndex = resourceIndexes[i];
      require(resourceIndex < 19, "8"); // can't melt high boxes or dream resources here
      require(resourceIndex != 9, "9"); // can't melt Ape Tools

      uint256 amountInUnits = amountsInUnits[i];

      yield += ((weights[resourceIndex] * amountInUnits) / 5);

      // create an array where the resource is the index
      _resources[resourceIndex] = amountInUnits * 100; //the farm likes it in cents
    }

    _resources[9] = apeToolsUsed * 100; // Ape Tools

    // charge the player
    _receivePayment(0, _resources, PaymentOptions(true, true, false, false));

    // Apply Ape Tools to the Yield:
    uint256 bonus = apeToolsUsed * 5;
    yield = (yield * (100 + bonus)) / 100;

    // send the yield to the player
    _mint(msg.sender, yield);
  }

  function buyEbct(uint256 stableTokensIn) external notBlocklisted(msg.sender) mutex whenNotPaused {
    uint256 bctAmount = paymentContracts.pool.quoteStableToGameTokens(stableTokensIn);
    require(buyEbctEnabled || hasRole(UPDATER_ROLE, msg.sender), "77");

    // charge the player
    _receivePayment(stableTokensIn, new uint256[](0), PaymentOptions(false, false, true, true));

    // create the resource array:
    uint256[] memory _resources = new uint256[](22);
    _resources[21] = (((stableTokensIn / 1e18) * 4) / 10) * 100; // 40% of the Stabletokens is converted to Drasca (and the farm likes it in cents)

    // send 4x as much eBCT to the player
    paymentContracts.farm.addTo(msg.sender, bctAmount * 4, _resources);
  }

  //######################
  // ERC20:
  function transfer(address recipient, uint256 amount) public returns (bool) {
    powderBalances[msg.sender] -= amount; // will revert if not enough balance
    powderBalances[recipient] += amount;

    emit Transfer(msg.sender, recipient, amount);

    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
    powderBalances[sender] -= amount; // will revert if not enough balance
    powderBalances[recipient] += amount;
    allowances[sender][msg.sender] -= amount; // will revert if not enough allowance

    emit Transfer(sender, recipient, amount);

    return true;
  }

  function approve(address spender, uint256 amount) public returns (bool) {
    allowances[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);

    return true;
  }

  function allowance(address owner, address spender) public view returns (uint256) {
    return allowances[owner][spender];
  }

  function _mint(address account, uint256 amount) private {
    powderBalances[account] += amount;
    totalSupply += amount;

    emit Transfer(address(0), account, amount);
  }

  function _burn(address account, uint256 amount) private {
    powderBalances[account] -= amount; // will revert if not enough balance
    totalSupply -= amount;

    emit Transfer(account, address(0), amount);
  }

  //######################
  // OPERATOR functions
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

  function setWeights(uint256[] memory _weights) external onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < _weights.length; i++) {
      weights[i] = _weights[i];
    }
  }

  function addTo(address to, uint256 amount) external onlyRole(UPDATER_ROLE) {
    _mint(to, amount);
  }

  function setCraftEnabled(bool _craftEnabled) external onlyRole(OPERATOR_ROLE) {
    craftEnabled = _craftEnabled;
  }

  function setMeltEnabled(bool _meltEnabled) external onlyRole(OPERATOR_ROLE) {
    meltEnabled = _meltEnabled;
  }

  function setBuyEbctEnabled(bool _buyEbctEnabled) external onlyRole(OPERATOR_ROLE) {
    buyEbctEnabled = _buyEbctEnabled;
  }

  function forceTotalSupply(uint256 _totalSupply) external onlyRole(OPERATOR_ROLE) {
    totalSupply = _totalSupply;
  }
}
