// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";
import "../utils/AntiGasWars.sol";
import "../utils/AntiMevLock.sol";
import "../erc20/interfaces/IBkERC20.sol";

import "../utils/ABDKMath64x64.sol";

// Kozi is the network's native token
// Stabletoken is an external ERC20 token
contract KoziPool is AntiMevLock, AntiGasWars, AdministrableUpgradable2024 {
  using ABDKMath64x64 for *;

  // ERC20 token state variables
  IBkERC20 public stableToken;

  // State variables for token reserves
  uint256 public koziReserve;
  uint256 public stableTokenReserve;

  uint256 public startBlock; // we start counting blocks from this block
  uint256 public initialTargetPrice; // the initial target price
  uint256 public tPriceIncrementPerDay; // every day, the target price increases this much

  event LiquidityAdded(address from, uint256 koziIn, uint256 stableTokensIn);
  event Buy(address account, uint256 stableTokensIn, uint256 koziOut);
  event BuyAndBurn(address account, uint256 stableTokensIn, uint256 koziBurned);
  event Sell(address account, uint256 koziIn, uint256 stableTokensOut);
  event NewPrice(uint256 price, uint256 targetPrice);
  event TransferKozi(address from, address to, uint256 value);

  function initialize(address _operator, address _blocklist, address _stableToken) public initializer {
    __Administrable_init(_operator, _blocklist);

    stableToken = IBkERC20(_stableToken);

    startBlock = block.number;
    initialTargetPrice = 10 ether; // 10 stable per kozi
    tPriceIncrementPerDay = 1e15; // this should be 0.1% a day

    //_setLockPeriod(60); // 10 minutes in blocks
    _setLockPeriod(0); // 1 minute in blocks
    _setGasPriceLimit(3 gwei);
  }

  // Public View Functions
  function getReserves() public view returns (uint256 _koziReserve, uint256 _stableTokenReserve) {
    _koziReserve = koziReserve;
    _stableTokenReserve = stableTokenReserve;
  }

  function getPrice() public view returns (uint256 _price) {
    _price = quoteBuyKozi(1e18);
  }

  function getTargetPrice() public view returns (uint256 targetPrice) {
    uint256 blocksSinceStart = block.number - startBlock;
    uint256 daysSinceStart = blocksSinceStart / 8640;

    if (daysSinceStart == 0) {
      return initialTargetPrice;
    }

    // targetPrice = initialTargetPrice*(1+dailyIncrementPct)^daysSinceStart
    targetPrice = compound(initialTargetPrice, tPriceIncrementPerDay, daysSinceStart);
  }

  function getPricesAndReserves()
    public
    view
    returns (uint256 _price, uint256 _targetPrice, uint256 _koziReserve, uint256 _stableTokenReserve)
  {
    _price = quoteBuyKozi(1e18);
    _targetPrice = getTargetPrice();
    (_koziReserve, _stableTokenReserve) = getReserves();
  }

  // Quote BUY: how many Kozi will I get for a given amount of stable tokens?
  function quoteStableToKozi(uint256 stableTokens) public view returns (uint256 kozi) {
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    kozi = (_koziReserve * stableTokens) / (_stableTokenReserve + stableTokens) - 1;
    require(kozi < _koziReserve, "Insufficient Liquidity");
  }

  // Quote SELL: how many stable tokens will I get for a given amount of Kozi?
  function quoteKoziToStabletokens(uint256 kozi) public view returns (uint256 stable) {
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    uint256 stableTokensOut = (_stableTokenReserve * kozi) / (_koziReserve + kozi);

    uint256 currentPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    stable = _applySpread(kozi, stableTokensOut, currentPrice, targetPrice);

    require(stable < _stableTokenReserve, "Insufficient Liquidity");
  }

  // Calculate how much you need to pay in stableTokens to get `koziOut` Kozi
  function getStabletokensIn(uint256 koziOut) public view returns (uint256 stableTokensIn) {
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();
    require(koziOut < _koziReserve, "Insufficient Liquidity");

    stableTokensIn = (_stableTokenReserve * koziOut) / (_koziReserve - koziOut) + 1;
  }

  function quoteBuyKozi(uint256 koziToBuy) public view returns (uint256 costInStabletokens) {
    require(koziToBuy > 0, "amount=0");
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();
    require(koziToBuy < _koziReserve, "Insufficient Liquidity");

    costInStabletokens = (_stableTokenReserve * koziToBuy) / (_koziReserve - koziToBuy) + 1;
  }

  function quoteSellKozi(uint256 koziToSell) public view returns (uint256 stableTokensOut) {
    return _quoteSellKozi(koziToSell);
  }

  function compound(uint256 principal, uint256 ratio, uint256 n) public pure returns (uint256) {
    return
      ABDKMath64x64.mulu(
        ABDKMath64x64.pow(ABDKMath64x64.add(ABDKMath64x64.fromUInt(1), ABDKMath64x64.divu(ratio, 10 ** 18)), n),
        principal
      );
  }

  function simulateNewPriceAfterSell(
    uint256 koziIn,
    uint256 stableTokensOut,
    bool _isAboveTargetPrice
  ) public view returns (uint256 _priceAfter) {
    // get reserves
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    // here, we'll subtract koziIn from the kozi reserve, and add stableOut to the stable reserve,
    // then return that price
    // NOTE: if the price is currently below the target, we'll burn all kozi coming in
    uint256 postKoziReserve = _isAboveTargetPrice ? _koziReserve + koziIn : _koziReserve;
    uint256 postStableReserve = _stableTokenReserve - stableTokensOut;

    _priceAfter = (postStableReserve * 1e18) / (postKoziReserve - 1e18) + 1;
  }

  function estimateKindomSellToTargetPrice() external view returns (uint256 koziToSell) {
    // how much Kozi do we need to sell to make the price drop to [a little above] the target price?
    // if the price is already below the target price, we'll return 0
    (uint256 _price, uint256 _targetPrice, uint256 _koziReserve, ) = getPricesAndReserves();

    if (_price < _targetPrice) {
      return 0;
    }

    // we'll use the formula:
    koziToSell = (_koziReserve * (_price - _targetPrice)) / (_price + _targetPrice);

    // we have to account for the spread of 50%, so we'll add 33% to the amount
    koziToSell = (koziToSell * 133) / 100;
  }

  // Public Functions
  function buyKozi(
    uint256 kozi
  )
    external
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensPaid)
  {
    return _buyKozi(kozi);
  }

  function buyKoziAtPrice(
    uint256 kozi,
    uint256 atPrice,
    uint256 maxSlippage
  )
    external
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensPaid)
  {
    uint256 currentPrice = getPrice();
    uint256 maxPrice = atPrice + (atPrice * maxSlippage) / 1000;
    require(currentPrice <= maxPrice, "Price changed too much");

    return _buyKozi(kozi);
  }

  function sellKozi()
    external
    payable
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensOut)
  {
    return _sellKozi();
  }

  function sellKoziAtPrice(
    uint256 atPrice,
    uint256 maxSlippage
  )
    external
    payable
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensOut)
  {
    uint256 currentPrice = getPrice();
    uint256 minPrice = atPrice - (atPrice * maxSlippage) / 1000;
    require(currentPrice >= minPrice, "Price changed too much");

    return _sellKozi();
  }

  function addLiquidity(
    uint256 amountOfStabletokens
  ) external payable mutex whenNotPaused onlyFairGas notBlocklisted(msg.sender) onlyUnlockedSender {
    // get reserves
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    /*
    Check if the ratio of tokens supplied is proportional
    to reserve ratio to satisfy x * y = k for price to not
    change if both reserves are greater than 0
    */
    if (_koziReserve > 0 || _stableTokenReserve > 0) {
      require(msg.value * _stableTokenReserve == amountOfStabletokens * _koziReserve, "Unbalanced Liquidity Provided");
    }

    if (amountOfStabletokens > 0) {
      stableToken.transferFrom(msg.sender, address(this), amountOfStabletokens);
    }

    // Update the reserves
    _update(address(this).balance, stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    emit TransferKozi(msg.sender, address(this), msg.value);
    emit LiquidityAdded(msg.sender, msg.value, amountOfStabletokens);
    emit NewPrice(newPrice, targetPrice);
  }

  // Private function to update liquidity pool reserves
  function _update(uint256 _koziReserve, uint256 _stableTokenReserve) private {
    koziReserve = _koziReserve;
    stableTokenReserve = _stableTokenReserve;
  }

  function _quoteSellKozi(uint256 koziToSell) private view returns (uint256 stableTokensOut) {
    // get reserves
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    stableTokensOut = (_stableTokenReserve * koziToSell) / (_koziReserve + koziToSell);

    uint256 currentPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    stableTokensOut = _applySpread(koziToSell, stableTokensOut, currentPrice, targetPrice);

    require(stableTokensOut < _stableTokenReserve, "Insufficient Liquidity");
  }

  function _applySpread(
    uint256 koziIn,
    uint256 stableTokensOut,
    uint256 currentPrice,
    uint256 targetPrice
  ) private view returns (uint256) {
    uint256 simulatedPriceAfterSell = simulateNewPriceAfterSell(koziIn, stableTokensOut, currentPrice > targetPrice);

    uint256 _spread;
    // if the simulatedPriceAfterSell is above the targetPrice, the spread is half the percentual difference between the target and the current, up to 99%;
    if (simulatedPriceAfterSell > targetPrice) {
      _spread = (((simulatedPriceAfterSell - targetPrice) * 100) / targetPrice) / 2;
      if (_spread > 99) {
        _spread = 99;
      }
    } else {
      // else, it's 2x the percentual difference between the target and the current, up to 99%;
      _spread = (((targetPrice - simulatedPriceAfterSell) * 100) / targetPrice) * 2;
      if (_spread > 99) {
        _spread = 99;
      }
    }

    return (stableTokensOut * (100 - _spread)) / 100;
  }

  function _sellKozi() private returns (uint256 stableTokensOut) {
    require(msg.value > 0, "Insufficient Amount");

    uint256 _stableTokensOut = _quoteSellKozi(msg.value);
    stableTokensOut = _stableTokensOut;

    uint256 currentPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    if (currentPrice < targetPrice) {
      payable(address(0)).transfer(msg.value);
      emit TransferKozi(address(this), address(0), msg.value);
    }

    // Transfer tokenOut to the user
    stableToken.transfer(msg.sender, stableTokensOut);

    // Update the reserves
    _update(address(this).balance, stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    emit Sell(msg.sender, msg.value, stableTokensOut);
    emit NewPrice(newPrice, targetPrice);
  }

  function _buyKozi(uint256 kozi) private returns (uint256 stableTokensPaid) {
    require(kozi >= 1e15, "Minimum buy is 0.001 KOZI");
    stableTokensPaid = quoteBuyKozi(kozi);

    // Transfer tokenIn to the liquity pool optimistically
    stableToken.transferFrom(msg.sender, address(this), stableTokensPaid);

    // Transfer to the user
    payable(msg.sender).transfer(kozi);

    // Update the reserves
    _update(address(this).balance, stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    emit TransferKozi(address(this), msg.sender, kozi);
    emit Buy(msg.sender, stableTokensPaid, kozi);
    emit NewPrice(newPrice, targetPrice);
  }

  ////////////////////////////
  // Operator Functions
  // we'll sell kozi, but we'll receive only half the stabletokens
  function kingdomSell() public payable mutex onlyRole(UPDATER_ROLE) {
    uint256 stableTokensOut = quoteKingdomSell(msg.value);

    // Transfer stableTokensOut to the Kingdom
    stableToken.transfer(msg.sender, stableTokensOut);

    // Update the reserves
    _update(address(this).balance, stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    uint256 targetPrice = getTargetPrice();
    emit TransferKozi(msg.sender, address(this), msg.value);
    emit Sell(msg.sender, msg.value, stableTokensOut);
    emit NewPrice(newPrice, targetPrice);
  }

  function quoteKingdomSell(uint256 amount) public view onlyRole(UPDATER_ROLE) returns (uint256 stableTokensOut) {
    require(amount > 0, "Insufficient Amount");

    // get reserves
    (uint256 _koziReserve, uint256 _stableTokenReserve) = getReserves();

    // apply 50% spread: we'll receive only half the stable we should
    stableTokensOut = ((_stableTokenReserve * amount) / (_koziReserve + amount)) / 2;

    require(stableTokensOut < _stableTokenReserve, "Insufficient Liquidity");
  }

  function resetReserves() external mutex onlyRole(OPERATOR_ROLE) {
    _update(address(this).balance, stableToken.balanceOf(address(this)));
  }
}
