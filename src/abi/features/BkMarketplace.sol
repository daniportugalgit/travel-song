// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../utils/AntiGasWars.sol";
import "../utils/AntiMevLock.sol";

import "../erc20/interfaces/IBkERC20.sol";
import "../erc721/interfaces/IBkNft.sol";
import "../interfaces/IBkFarm.sol";
import "../interfaces/ICommunityPool.sol";

/**
 * @title Marketplace
 */
contract BkMarketplace is AntiMevLock, AntiGasWars, AdministrableUpgradable2024 {
  bytes32 internal constant MERCHANT_ROLE = keccak256("MERCHANT_ROLE");

  struct Contracts {
    IBkERC20 bct;
    IBkERC20 stabletoken;
    IBkNft nft;
    ICommunityPool pool;
    IBkFarm farm;
  }
  Contracts public contracts;

  struct Merchant {
    uint256 auctions;
    uint256 sales;
    uint256 poolFuel; // how much STABLETOKEN the merchant has manually or automatically used to fuel the pool (2% of each sale + donations)
  }
  mapping(address => Merchant) public merchants;

  struct PaymentProportions {
    uint256 sellerPct;
    uint256 secondaryReceiverPct;
    uint256 merchantPct;
    uint256 communityPct;
  }

  struct PaymentConditions {
    bool payingWithStabletoken;
    bool payingWithEbct;
    bool isPoolFuel;
  }

  struct PaymentRequest {
    address payer;
    Players players;
    Price price;
    PaymentConditions paymentConditions;
  }

  // Assets may be NFTs or virtual ERC20s, called RESOURCEs
  // RESOURCEs are managed by the farm, so they are just ids for us
  // It means that both NFTs and RESOURCEs have an id
  // The id for RESOURCEs is the order of that resource in the resource list
  // The quantity for RESOURCEs is the amount of that resource
  struct Asset {
    bool isNft; // RESOURCE or NFT
    uint256 id; // ERC721 token id or RESOURCE id
    uint256 quantity; // ERC721 token quantity (always 1) or RESOURCE quantity
  }

  // The price is always UNITARY! If it's a resource, the available quantity is in the asset object
  struct Price {
    bool isNominalInStabletoken; // if false, the "amount" field is in BCT
    bool isStabletokenOnly;
    bool allowEbct; // the price in eBCT is proportional to the price in BCT
    uint256 amount;
    uint256 secondaryReceiverPct; // secondaryReceiver share in percentage of the price (0 to 100)
  }

  struct Players {
    address seller;
    address secondaryReceiver;
    address privateFor; // if it's a private sale, who is it for (0x0 if it's a public)
  }

  struct Order {
    uint256 id; // Order ID (starts at 1)
    uint256 createdAt; // Block when the order was created; In Dutch Acutions, the price will reach `price` in 7200 blocks
    bool isActive; // if false, it's cancelled or executed
    bool isDutchAuction;
    bool isPoolFuel; // if true, the order proceeds will go to the pool (must be a stabletokenOnly order)
    Asset asset; // the Asset object of what's being sold
    Price price; // the Price object of what's being sold
    Players players; // the Players object of who's involved in the order
  }
  Order[] public orders;
  uint256 public totalOrderCountEver;
  mapping(uint256 => uint256) public orderIdToOrderIndex;

  uint256 public gracePeriod; // how many blocks an order must exist before being executable
  uint256 public burnFeePct;
  uint256 public eBctPct; //how much eBCT to charge for a given amount of BCT;
  mapping(uint256 => uint256) public orderIdToAllowedBlock; // the block when the order can be executed

  event OrderCreated(
    uint256 orderId,
    uint256 createdAt,
    uint256 assetId,
    uint256 assetQuantity,
    address seller,
    address privateFor,
    uint256 priceInWei,
    bool allowEbct,
    bool isNft,
    bool isPriceInStabletoken,
    bool isStabletokenOnly,
    bool isDutchAuction,
    bool isPoolFuel
  );
  event OrderExecuted(
    uint256 orderId,
    uint256 assetId,
    uint256 availableQuantity,
    uint256 boughtQuantity,
    address seller,
    address buyer,
    uint256 originalPriceInWei,
    uint256 pricePaidInWei,
    bool originalPriceInStabletoken,
    bool paidInStabletoken,
    bool paidInEbct,
    bool isNft
  );
  event OrderUpdated(uint256 orderId, uint256 previousQuantity, uint256 newQuantity);
  event OrderCancelled(uint256 orderId);
  event eBctTransferred(address from, address to, uint256 amount);
  event drascaTransferred(address from, address to, uint256 amount);

  // UPGRADE v2 NOTES:
  // We are changing Dutch Auctions into normal auctions;
  // We are going to use the properties that already exist in the Order struct to do that;
  // Order.isDutchAuction will be used to indicate if it's a normal order or a NORMAL auction;
  // Order.price.amount will be used to indicate the CURRENT price of the auction; It's always in Stabletokens (USDC).
  // Order.createdAt will be used to indicate when the LATEST bid (or the creation) happened;
  // Order.players.privateFor will be used to indicate the address of the highest bidder;
  event AuctionBidPlaced(
    uint256 orderId,
    address bidder,
    uint256 bid,
    address prevBidder,
    uint256 prevBidderCashback,
    uint256 blockNumber
  );
  event PrizePaid(uint256 orderId, address winner, uint256 ebct, uint256[] resources);

  mapping(uint256 => uint256) public orderIdToBids; // the amount of bids for a given order
  mapping(uint256 => uint256) public orderIdToRemainingStabletokens; // the amount of stable tokens that are left to be used for a given order
  uint256 public reservedStabletokens; // the amount of stable tokens that are reserved for gamedev

  function initialize(address _operator, address _blocklist) public initializer {
    __Administrable_init(_operator, _blocklist);

    Order memory dummyOrder = Order({
      id: 0,
      createdAt: 0,
      isActive: false,
      isDutchAuction: false,
      isPoolFuel: false,
      asset: Asset({isNft: false, id: 0, quantity: 0}),
      price: Price({
        isNominalInStabletoken: false,
        isStabletokenOnly: false,
        allowEbct: false,
        amount: 0,
        secondaryReceiverPct: 0
      }),
      players: Players({seller: address(0), secondaryReceiver: address(0), privateFor: address(0)})
    });
    _addOrder(dummyOrder); // Add a dummy order to the first index of the orders array
    totalOrderCountEver++; // order IDs start at 1 so that the null value is considered an invalid order ID

    burnFeePct = 2; // 2% of the price is burned on order execution
    gracePeriod = 2; // an order cannot be bought before this number of blocks have passed since its creation
    _setLockPeriod(4); // users have a 4-block cooldown after creating, executing or cancelling an order
    _setGasPriceLimit(5 * 1e9); // transactions to this contract cannot have a greater gas price than this
    eBctPct = 130; // 130% of the price in BCT is charged in eBCT
  }

  //###############
  // Getters
  function getOrder(uint256 orderId) public view returns (Order memory) {
    return orders[orderIdToOrderIndex[orderId]];
  }

  function getOrders(uint256[] memory orderIds) public view returns (Order[] memory _orders) {
    _orders = new Order[](orderIds.length);
    for (uint256 i = 0; i < orderIds.length; i++) {
      _orders[i] = getOrder(orderIds[i]);
    }
  }

  function getLatestOrders(uint256 limit) public view returns (Order[] memory _orders) {
    uint256 length = orders.length;
    uint256 start = length > limit ? length - limit : 0;
    _orders = new Order[](length - start);
    for (uint256 i = start; i < length; i++) {
      _orders[i - start] = orders[i];
    }
  }

  function getAllOrders() public view returns (Order[] memory) {
    return orders;
  }

  function getMerchant(address merchant) public view returns (Merchant memory) {
    return merchants[merchant];
  }

  //###############
  // Public Functions
  function createOrder(
    Asset memory asset,
    Price memory price,
    Players memory players,
    bool isDutchAuction,
    bool isPoolFuel
  ) external mutex whenNotPaused onlyFairGas onlyUnlockedSender {
    require(!_isBlocklisted(msg.sender), "16");
    require(price.amount > 0, "a"); // price must be greater than 0
    require(price.secondaryReceiverPct <= 100, "b"); // secondaryReceiverPct must be less than or equal to 100%
    require((asset.isNft && asset.quantity == 1) || asset.quantity > 0, "c");

    if (!hasRole(MERCHANT_ROLE, msg.sender)) {
      require(players.privateFor == address(0), "d"); // only merchants can create private orders
      require(!isDutchAuction, "e"); // only merchants can create dutch auctions
    } else {
      if (isDutchAuction) {
        require(players.privateFor == msg.sender, "h"); // auction must start private for the seller (indicates it's an auction without any bids so far)
        require(price.isStabletokenOnly, "i"); // auctions must be stabletokens only
        require(price.isNominalInStabletoken, "j"); // auctions must be paid in stabletokens
        require(!price.allowEbct, "k"); // auctions must not allow ebct
      }
    }

    if (!asset.isNft) {
      // transfer the resource from the farm to this contract
      uint256[] memory _resources = new uint256[](asset.id + 1);
      _resources[asset.id] = asset.quantity * 100; // the farm expects it in cents, so we need to multiply it by 100
      contracts.farm.transferFrom(msg.sender, address(this), 0, 0, _resources); // reverts on lack of balance
    } else {
      // transfer the nft to marketplace
      contracts.nft.transferFrom(msg.sender, address(this), asset.id); // reverts on lack of balance
    }

    if (isPoolFuel) {
      require(price.isStabletokenOnly, "f");
      require(asset.id != 21, "g"); // Dragon Scales cannot be used to fuel the pool
    }

    uint256 orderId = totalOrderCountEver;
    totalOrderCountEver++;
    _addOrder(
      Order({
        id: orderId,
        createdAt: block.number,
        isActive: true,
        asset: asset,
        price: price,
        players: players,
        isDutchAuction: isDutchAuction,
        isPoolFuel: isPoolFuel
      })
    );

    emit OrderCreated(
      orderId,
      block.number,
      asset.id,
      asset.quantity,
      players.seller,
      players.privateFor,
      price.amount,
      price.allowEbct,
      asset.isNft,
      price.isNominalInStabletoken,
      price.isStabletokenOnly,
      isDutchAuction,
      isPoolFuel
    );
  }

  function bidOnAuction(
    uint256 orderId,
    uint256 amount,
    bool isPowerBid
  ) public mutex whenNotPaused onlyFairGas notBlocklisted(msg.sender) {
    Order storage order = orders[orderIdToOrderIndex[orderId]];
    require(order.isActive, "18");
    require(order.isDutchAuction, "19");
    require(msg.sender != order.players.seller, "20");
    require(block.number < order.createdAt + 8640, "21"); // the auction can't be more than 1 day old

    if (isPowerBid) {
      // overwrites the amount with the minimum amount required for a power bid
      amount = (order.price.amount * 112) / 100;
    }
    require(amount >= (order.price.amount * 112) / 100, "22"); // the bid must be at least 12% more than the current price
    require(msg.sender != order.players.privateFor, "23"); // the bidder cannot be the currently winning player

    contracts.stabletoken.transferFrom(msg.sender, address(this), amount); // receive the Dollars; reverts on lack of balance or allowance

    address previousBidder = order.players.privateFor;

    // return the old privateFor's Dollars
    uint256 hundredAndFivePct;
    if (previousBidder != address(0) && previousBidder != order.players.seller) {
      // return the previousBidder's Dollars + 5%; reverts on lack of balance or allowance
      hundredAndFivePct = (order.price.amount * 105) / 100;
      contracts.stabletoken.transfer(previousBidder, hundredAndFivePct); // 105% of the previous bid is returned to the previous bidder
      orderIdToRemainingStabletokens[orderId] += amount - hundredAndFivePct; // the rest (at least 5% of the previous bid) is kept in the contract
    } else {
      // it's the very first bid, so this contract keeps the full amount
      orderIdToRemainingStabletokens[orderId] = amount;
    }

    order.players.privateFor = msg.sender; // the auction is now private for the highest bidder (only they can execute it)
    order.createdAt = block.number; // the last bid block is now
    order.price.amount = amount; // the new price is the bid amount

    orderIdToBids[orderId]++; // increment the number of bids for this order

    emit AuctionBidPlaced(orderId, msg.sender, amount, previousBidder, hundredAndFivePct, block.number);
  }

  function executeOrder(
    uint256 orderId,
    uint256 quantity,
    bool payWithStabletoken,
    bool payWithEbct
  ) public mutex whenNotPaused onlyFairGas notBlocklisted(msg.sender) onlyUnlockedSender {
    Order memory order = getOrder(orderId);

    require(order.isActive, "1");
    require(orderIdToAllowedBlock[orderId] < block.number, "2");
    require(order.players.seller != msg.sender && order.players.secondaryReceiver != msg.sender, "3");
    require(order.players.privateFor == msg.sender || order.players.privateFor == address(0), "4");
    require((order.asset.isNft && quantity == 1) || quantity > 0, "5");

    if (order.price.isStabletokenOnly || order.isPoolFuel) {
      require(payWithStabletoken, "8");
    }
    if (payWithEbct) {
      require(order.price.allowEbct, "9");
    }

    uint256 originalPrice = order.price.amount;

    order.price.amount = order.isDutchAuction ? order.price.amount : order.price.amount * quantity;
    uint256 amountPaid;

    if (order.isDutchAuction) {
      // If we are executing an auction, it means that we are the privateFor (the latest bidder)
      // AND that our bid is at least 1 day old;
      // in this case only, we have already paid for the item.
      require(quantity == order.asset.quantity, "6"); // dutch auctions must be bought in full
      require(block.number >= order.createdAt + 8640, "12"); // the last bid must be at least 1 day old
      require(order.players.privateFor == msg.sender, "23"); // only the privateFor can execute the auction

      // the tokens are already 'in' this contract, don't need to transfer more;
      /*
      if (order.isPoolFuel) {
        contracts.pool.buyAndBurn(orderIdToRemainingStabletokens[orderId]);
        merchants[order.players.seller].poolFuel += order.price.amount;
      } else {
        */
      // transfer the remaining tokens to the seller (todo: activate for merchants; currently lacking validations)
      // contracts.stabletoken.transfer(order.players.seller, orderIdToRemainingStabletokens[orderId]);
      reservedStabletokens += orderIdToRemainingStabletokens[orderId];
      //}

      amountPaid = order.price.amount;
      merchants[order.players.seller].auctions++;

      // now give the buyer a bonus based on how many bids we got
      uint256[] memory _resources = new uint256[](25);
      _resources[22] = orderIdToBids[orderId] * 100; // Griffin Feathers in cents
      _resources[23] = orderIdToBids[orderId] * 50; // Satyr Horns in cents
      _resources[24] = orderIdToBids[orderId] * 25; // Dinosaur Skulls in cents

      uint256 ebct = orderIdToBids[orderId] * 250 * 1e18; // 250 eBCT per bid

      contracts.farm.addTo(msg.sender, ebct, _resources);

      emit PrizePaid(orderId, msg.sender, ebct, _resources);
    } else {
      require(quantity <= order.asset.quantity, "7"); // cannot buy more than what's available

      // Transfer payment
      amountPaid = _receivePayment(
        PaymentRequest({
          payer: msg.sender,
          players: order.players,
          price: order.price,
          paymentConditions: PaymentConditions({
            payingWithStabletoken: payWithStabletoken,
            payingWithEbct: payWithEbct,
            isPoolFuel: order.isPoolFuel
          })
        })
      );

      // we'll send 1% in Dragon Scales to the buyer and 1% in Dragon Scales to the seller
      // unless the resources bheing dealt with are Dragon Scales themselves
      // dragon scales is the resource with ID 21
      if (payWithStabletoken && order.asset.id != 21) {
        uint256[] memory _resources = new uint256[](22);
        uint256 drasca = order.isPoolFuel ? (amountPaid * 50) / 1E18 : amountPaid / 1E18; // it's in cents of resources, therefore (amountPaid/100)/1E16, which is amountPaid/1E18; 50 times that if it's a donation toi the pool
        _resources[21] = drasca;
        contracts.farm.addTo(msg.sender, 0, _resources);
        contracts.farm.addTo(order.players.seller, 0, _resources);
        emit drascaTransferred(address(this), msg.sender, drasca);
        emit drascaTransferred(address(this), order.players.seller, drasca);
      }
    }

    // Update merchant stats
    merchants[order.players.seller].sales++;

    // Transfer asset
    if (!order.asset.isNft) {
      // transfer the resource from this contract to the buyer
      uint256[] memory _resources = new uint256[](order.asset.id + 1);
      _resources[order.asset.id] = quantity * 100; // the farm expects it in cents, so we need to multiply it by 100
      contracts.farm.transferFrom(address(this), msg.sender, 0, 0, _resources); // reverts on lack of balance
    } else {
      // transfer the nft to the buyer
      contracts.nft.transferFrom(address(this), msg.sender, order.asset.id); // reverts on lack of balance
    }

    emit OrderExecuted(
      orderId,
      order.asset.id,
      order.asset.quantity,
      quantity,
      order.players.seller,
      msg.sender,
      originalPrice,
      amountPaid,
      order.price.isNominalInStabletoken,
      payWithStabletoken,
      payWithEbct,
      order.asset.isNft
    );

    if (quantity == order.asset.quantity) {
      _deleteOrder(orderId);
    } else {
      _updateOrderQuantity(orderId, order.asset.quantity, quantity);
    }
  }

  function _updateOrderQuantity(uint256 orderId, uint256 currentQuantity, uint256 quantitySpent) private {
    emit OrderUpdated(orderId, currentQuantity, currentQuantity - quantitySpent);
    orders[orderIdToOrderIndex[orderId]].asset.quantity -= quantitySpent; //reverts on negative
  }

  function cancelOrder(uint256 orderId) public whenNotPaused onlyFairGas notBlocklisted(msg.sender) {
    Order memory order = getOrder(orderId);
    require(order.id == orderId && order.isActive, "10");

    require(order.players.seller == msg.sender || hasRole(OPERATOR_ROLE, msg.sender), "11");

    // allow it for now
    /*
    if (order.isDutchAuction) {
      // if it's a dutch auction, the seller can only cancel it if it's private for them (meaning that nobody made a bid yet)
      require(order.players.privateFor == order.players.seller, "12"); 
    }
    */

    uint256 orderAssetId = order.asset.id;
    bool orderAssetIsNft = order.asset.isNft;
    uint256 orderAssetQuantity = order.asset.quantity;
    address seller = order.players.seller;

    _deleteOrder(orderId);

    emit OrderCancelled(orderId);

    if (!orderAssetIsNft) {
      // transfer the resource from this contract to the seller
      uint256[] memory _resources = new uint256[](orderAssetId + 1);
      _resources[orderAssetId] = orderAssetQuantity * 100; // the farm expects it in cents, so we need to multiply it by 100
      contracts.farm.transferFrom(address(this), seller, 0, 0, _resources);
    } else {
      // transfer the nft to the seller
      contracts.nft.transferFrom(address(this), seller, orderAssetId);
    }
  }

  function cancelOrders(uint256[] memory orderIds) public {
    for (uint256 i = 0; i < orderIds.length; i++) {
      cancelOrder(orderIds[i]);
    }
  }

  //###############
  // Internals
  // How much stabletoken to charge for a given amount of BCT;
  function bctToStabletoken(uint256 bctAmount) public view returns (uint256) {
    return contracts.pool.quoteBuyGameTokens(bctAmount);
  }

  // How much BCT to charge for a given amount of STABLETOKEN;
  function stabletokenToBct(uint256 stabletokenAmount) public view returns (uint256) {
    return contracts.pool.quoteStableToGameTokens(stabletokenAmount);
  }

  function _receivePayment(PaymentRequest memory paymentRequest) internal returns (uint256 amountPaid) {
    if (paymentRequest.paymentConditions.payingWithStabletoken) {
      amountPaid = _handleStabletokenPayment(paymentRequest);
    } else if (paymentRequest.paymentConditions.payingWithEbct) {
      amountPaid = _handleEbctPayment(paymentRequest);
    } else {
      amountPaid = _handleBctPayment(paymentRequest);
    }
  }

  function _handleStabletokenPayment(PaymentRequest memory paymentRequest) internal returns (uint256 amountPaid) {
    amountPaid = paymentRequest.price.isNominalInStabletoken
      ? paymentRequest.price.amount
      : bctToStabletoken(paymentRequest.price.amount);
    _transferAndBurnStabletoken(paymentRequest, amountPaid);
  }

  function _handleEbctPayment(PaymentRequest memory paymentRequest) internal returns (uint256 amountPaid) {
    require(paymentRequest.price.allowEbct, "13");
    require(!paymentRequest.price.isStabletokenOnly, "14");

    amountPaid = paymentRequest.price.isNominalInStabletoken
      ? (stabletokenToBct(paymentRequest.price.amount) * eBctPct) / 100
      : (paymentRequest.price.amount * eBctPct) / 100;
    _transferAndBurnEbct(paymentRequest, amountPaid);
  }

  function _handleBctPayment(PaymentRequest memory paymentRequest) internal returns (uint256 amountPaid) {
    require(!paymentRequest.price.isStabletokenOnly, "15");
    amountPaid = paymentRequest.price.isNominalInStabletoken
      ? stabletokenToBct(paymentRequest.price.amount)
      : paymentRequest.price.amount;
    _transferAndBurnBct(paymentRequest, amountPaid);
  }

  function _transferAndBurnStabletoken(PaymentRequest memory paymentRequest, uint256 amount) internal {
    if (paymentRequest.paymentConditions.isPoolFuel) {
      merchants[paymentRequest.players.seller].poolFuel += amount;
      // everything goes to the pool:
      contracts.stabletoken.transferFrom(paymentRequest.payer, address(this), amount);
      contracts.pool.buyAndBurn(amount);
    } else {
      (
        uint256 sellerAmount,
        uint256 secondaryReceiverAmount,
        uint256 burnAmount,
        uint256 merchantAmount
      ) = _extractAmounts(amount, paymentRequest.price.secondaryReceiverPct);

      _transferStabletoken(paymentRequest.payer, paymentRequest.players.seller, sellerAmount + merchantAmount);
      _transferStabletoken(paymentRequest.payer, paymentRequest.players.secondaryReceiver, secondaryReceiverAmount);

      if (burnAmount > 0) {
        contracts.stabletoken.transferFrom(paymentRequest.payer, address(this), burnAmount);
        contracts.pool.buyAndBurn(burnAmount);
      }
    }
  }

  function _transferAndBurnEbct(PaymentRequest memory paymentRequest, uint256 amount) internal {
    (
      uint256 sellerAmount,
      uint256 secondaryReceiverAmount,
      uint256 burnAmount,
      uint256 merchantAmount
    ) = _extractAmounts(amount, paymentRequest.price.secondaryReceiverPct);

    _transferEbct(paymentRequest.payer, paymentRequest.players.seller, sellerAmount + merchantAmount);
    _transferEbct(paymentRequest.payer, paymentRequest.players.secondaryReceiver, secondaryReceiverAmount);

    if (burnAmount > 0) {
      contracts.farm.payWithBalance(paymentRequest.payer, burnAmount, new uint256[](0));
    }
  }

  function _transferAndBurnBct(PaymentRequest memory paymentRequest, uint256 amount) internal {
    uint256 bctBalanceInFarm = contracts.farm.bctBalanceOf(paymentRequest.payer);
    uint256 bctToChargeFromFarm = bctBalanceInFarm >= amount ? amount : bctBalanceInFarm;
    uint256 bctToChargeFromMetamask = bctBalanceInFarm >= amount ? 0 : amount - bctBalanceInFarm;

    if (bctToChargeFromFarm > 0) {
      (
        uint256 sellerAmount,
        uint256 secondaryReceiverAmount,
        uint256 burnAmount,
        uint256 merchantAmount
      ) = _extractAmounts(bctToChargeFromFarm, paymentRequest.price.secondaryReceiverPct);

      _transferBctFromFarm(paymentRequest.payer, paymentRequest.players.seller, sellerAmount + merchantAmount);
      _transferBctFromFarm(paymentRequest.payer, paymentRequest.players.secondaryReceiver, secondaryReceiverAmount);

      if (burnAmount > 0) {
        contracts.farm.spendBctFrom(paymentRequest.payer, burnAmount, false);
      }
    }

    if (bctToChargeFromMetamask > 0) {
      (
        uint256 sellerAmount,
        uint256 secondaryReceiverAmount,
        uint256 burnAmount,
        uint256 merchantAmount
      ) = _extractAmounts(bctToChargeFromMetamask, paymentRequest.price.secondaryReceiverPct);

      _transferBctFromMetamask(paymentRequest.payer, paymentRequest.players.seller, sellerAmount + merchantAmount);
      _transferBctFromMetamask(paymentRequest.payer, paymentRequest.players.secondaryReceiver, secondaryReceiverAmount);

      if (burnAmount > 0) {
        contracts.bct.burnFrom(paymentRequest.payer, burnAmount);
      }
    }
  }

  function _transferStabletoken(address payer, address receiver, uint256 amount) internal {
    if (amount > 0) {
      contracts.stabletoken.transferFrom(payer, receiver, amount);
    }
  }

  function _transferEbct(address payer, address receiver, uint256 amount) internal {
    if (amount > 0) {
      contracts.farm.transferFrom(payer, receiver, 0, amount, new uint256[](0));
      emit eBctTransferred(payer, receiver, amount);
    }
  }

  function _transferBctFromFarm(address payer, address receiver, uint256 amount) internal {
    if (amount > 0) {
      contracts.farm.transferFrom(payer, receiver, amount, 0, new uint256[](0));
    }
  }

  function _transferBctFromMetamask(address payer, address receiver, uint256 amount) internal {
    if (amount > 0) {
      contracts.bct.transferFrom(payer, receiver, amount);
    }
  }

  function _extractAmounts(
    uint256 amount,
    uint256 secondaryReceiverPct
  )
    internal
    view
    returns (uint256 sellerAmount, uint256 secondaryReceiverAmount, uint256 burnAmount, uint256 merchantAmount)
  {
    // The merchant fee is 0% to 4% of the price, depending on the number of auctions the seller has made
    //uint256 merchantAuctions = merchants[seller].auctions > 40 ? 40 : merchants[seller].auctions;
    //merchantAmount = (amount * merchantAuctions) / 1000; // goes from 0 to 4%
    merchantAmount = 0; // UPDATE: merchants gain Dragon Scales for selling items, so they don't need to get a fee on top of that

    // All transactions cost 2% (burnFeePct) of the price minus the merchant fee
    uint256 originalBurnFee = (amount * burnFeePct) / 100;
    burnAmount = originalBurnFee - merchantAmount;

    // The secondary receiver gets a percentage of the rest
    secondaryReceiverAmount = ((amount - originalBurnFee) * secondaryReceiverPct) / 100;

    // The seller gets the rest
    sellerAmount = amount - secondaryReceiverAmount - burnAmount - merchantAmount;
  }

  function _addOrder(Order memory order) internal {
    // Add it to the full list
    orders.push(order);

    // Add it to the order ID to index mapping
    orderIdToOrderIndex[order.id] = orders.length - 1;

    // Add it to the allowed block list
    orderIdToAllowedBlock[order.id] = block.number + gracePeriod;
  }

  function _deleteOrder(uint256 orderId) internal {
    uint256 orderIndex = orderIdToOrderIndex[orderId];
    require(orderIndex < orders.length && orderIndex != 0, "16");

    Order storage order = orders[orderIndex];
    require(order.id == orderId && order.isActive, "17");
    order.isActive = false;

    Order memory lastOrder = orders[orders.length - 1];

    if (lastOrder.id != orderId) {
      orders[orderIndex] = lastOrder;
      orderIdToOrderIndex[lastOrder.id] = orderIndex;
    }

    orders.pop();
    delete orderIdToOrderIndex[orderId];
  }

  //###############
  // Operator only
  function setContracts(
    address _bct,
    address _stabletoken,
    address _nft,
    address _pool,
    address _farm
  ) external onlyRole(OPERATOR_ROLE) {
    contracts = Contracts({
      bct: IBkERC20(_bct),
      stabletoken: IBkERC20(_stabletoken),
      nft: IBkNft(_nft),
      pool: ICommunityPool(_pool),
      farm: IBkFarm(_farm)
    });

    contracts.stabletoken.approve(_pool, type(uint256).max);
  }

  function clearAllOrders() external onlyRole(OPERATOR_ROLE) {
    // first get all order ids:
    uint256[] memory orderIds = new uint256[](orders.length - 1);
    for (uint256 i = 1; i < orders.length; i++) {
      orderIds[i - 1] = orders[i].id;
    }

    cancelOrders(orderIds);
  }

  //###############
  // Standard
  function onERC721Received() external pure returns (bytes4) {
    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }
}
