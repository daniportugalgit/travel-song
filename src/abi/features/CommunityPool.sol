// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../utils/AdministrableUpgradable2024.sol";

import "../utils/AntiGasWars.sol";
import "../utils/AntiMevLock.sol";

import "../erc20/interfaces/IBkERC20.sol";
import "../interfaces/IBkStasher.sol";

contract CommunityPool is AntiMevLock, AntiGasWars, AdministrableUpgradable2024 {
  // The MhdaoStasher contract
  IBkStasher public stasher;

  // ERC20 token state variables
  IBkERC20 public gameToken;
  IBkERC20 public stableToken;

  // State variables for token reserves
  uint256 public gameTokenReserve;
  uint256 public stableTokenReserve;

  uint256 public startBlock; // we start counting months from this block

  /// @dev a 'month' equals 30 days here
  struct Config {
    uint8 stasherDiscount; // percentual points per stasher level
    uint8 baseCommunityFee; // percentual points in the beginning
    uint8 closedForMonths; // will not allow selling until this many months have passed
    uint8 steepCurveMonths; // will decresase the community fee by 10% every month
    uint8 maxMonths; // will stop decreasing the community fee after this many months
  }
  Config public config;

  event LiquidityAdded(address from, uint256 gameTokensIn, uint256 stableTokensIn, uint256 newPrice);
  event Buy(address account, uint256 stableTokensIn, uint256 gameTokensOut, uint256 newPrice);
  event BuyAndBurn(address account, uint256 stableTokensIn, uint256 gameTokensBurned, uint256 newPrice);
  event Sell(address account, uint256 gameTokensIn, uint256 stableTokensOut, uint256 newPrice);
  event NewPrice(uint256 price);
  event AddToFund(uint256 amount);

  address public bkCommonwealthFund;

  function initialize(
    address _operator,
    address _blocklist,
    address _gameToken,
    address _stableToken,
    address _stasher,
    uint256 _startBlock
  ) public initializer {
    __Administrable_init(_operator, _blocklist);

    gameToken = IBkERC20(_gameToken);
    stableToken = IBkERC20(_stableToken);
    stasher = IBkStasher(_stasher);

    config = Config({
      stasherDiscount: 4, // percentual points per stasher level, up to 30%
      baseCommunityFee: 70, // percentual points in the beginning
      closedForMonths: 0, // will not allow selling until this many months have passed
      steepCurveMonths: 3, // will decrease the community fee by 10% every month
      maxMonths: 12 // will stop decreasing the community fee after this many months
    });

    startBlock = _startBlock;

    _setLockPeriod(200); // 10 minutes in blocks
    _setGasPriceLimit(5 gwei);
  }

  function getReserves() public view returns (uint256 _gameTokenReserve, uint256 _stableTokenReserve) {
    _gameTokenReserve = gameTokenReserve;
    _stableTokenReserve = stableTokenReserve;
  }

  function getPrice() public view returns (uint256 _price) {
    _price = quoteBuyGameTokens(1e18);
  }

  // Quote BUY: how many game tokens will I get for a given amount of stable tokens?
  function quoteStableToGameTokens(uint256 stableTokens) public view returns (uint256 gameTokens) {
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();

    gameTokens = (_gameTokenReserve * stableTokens) / (_stableTokenReserve + stableTokens);
    require(gameTokens < _gameTokenReserve, "Insufficient Liquidity");
  }

  // Quote SELL: how many stable tokens will I get for a given amount of game tokens?
  function quoteGameToStabletokens(uint256 gameTokens) public view returns (uint256 stableTokens) {
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();

    stableTokens = (_stableTokenReserve * gameTokens) / (_gameTokenReserve + gameTokens);
    require(stableTokens < _stableTokenReserve, "Insufficient Liquidity");
  }

  // Calculate how much you need to pay in stableTokens to get `bctOut` bct
  function getStabletokensIn(uint256 bctOut) public view returns (uint256 stableTokensIn) {
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();
    require(bctOut < _gameTokenReserve, "Insufficient Liquidity");

    stableTokensIn = (_stableTokenReserve * bctOut) / (_gameTokenReserve - bctOut) + 1;
  }

  function quoteBuyGameTokens(uint256 gameTokensToBuy) public view returns (uint256 costInStabletokens) {
    require(gameTokensToBuy >= 1 ether, "Minimum buy is 1 BCT");
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();
    require(gameTokensToBuy < _gameTokenReserve, "Insufficient Liquidity");

    costInStabletokens = (_stableTokenReserve * gameTokensToBuy) / (_gameTokenReserve - gameTokensToBuy) + 1;
  }

  function quoteSellGameTokens(uint256 gameTokensToSell) public view returns (uint256 stableTokensOut, uint256 feePct) {
    return _quoteSellGameTokens(gameTokensToSell, msg.sender);
  }

  function quoteSellGameTokensFor(
    uint256 gameTokensToSell,
    address account
  ) public view returns (uint256 stableTokensOut, uint256 feePct) {
    return _quoteSellGameTokens(gameTokensToSell, account);
  }

  function _quoteSellGameTokens(
    uint256 gameTokensToSell,
    address account
  ) private view returns (uint256 stableTokensOut, uint256 feePct) {
    // get reserves
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();

    // get stasher level
    uint256 stasherLevel = stasher.levelOf(account);

    // calculate community fee
    feePct = getCommunityFeePct(stasherLevel);
    feePct += (gameTokensToSell / 1e18) / 500;

    if (feePct > 90) {
      feePct = 90;
    }

    uint finalGameTokensToSell = gameTokensToSell - (gameTokensToSell * feePct) / 100;
    stableTokensOut = (_stableTokenReserve * finalGameTokensToSell) / (_gameTokenReserve + finalGameTokensToSell);

    require(stableTokensOut < _stableTokenReserve, "Insufficient Liquidity");
  }

  function buyGameTokens(
    uint256 gameTokens
  )
    external
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensPaid)
  {
    return _buyGameTokens(gameTokens);
  }

  function buyGameTokensAtPrice(
    uint256 gameTokens,
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

    return _buyGameTokens(gameTokens);
  }

  function _buyGameTokens(uint256 gameTokens) private returns (uint256 stableTokensPaid) {
    require(gameTokens >= 1 ether, "Minimum buy is 1 BCT");
    stableTokensPaid = quoteBuyGameTokens(gameTokens);

    // Transfer tokenIn to the liquity pool optimistically
    stableToken.transferFrom(msg.sender, address(this), stableTokensPaid);

    // Transfer tokenOut to the user
    gameToken.transfer(msg.sender, gameTokens);

    // Update the reserves
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    emit Buy(msg.sender, stableTokensPaid, gameTokens, newPrice);
    emit NewPrice(newPrice);
  }

  function sellGameTokens(
    uint256 gameTokens
  )
    external
    mutex
    whenNotPaused
    onlyFairGas
    notBlocklisted(msg.sender)
    onlyUnlockedSender
    returns (uint256 stableTokensOut)
  {
    return _sellGameTokens(gameTokens);
  }

  function sellGameTokensAtPrice(
    uint256 gameTokens,
    uint256 atPrice,
    uint256 maxSlippage
  )
    external
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

    return _sellGameTokens(gameTokens);
  }

  function _sellGameTokens(uint256 gameTokens) private returns (uint256 stableTokensOut) {
    require(gameTokens > 0, "Insufficient Amount");
    (uint256 _stableTokensOut, ) = quoteSellGameTokens(gameTokens);
    stableTokensOut = _stableTokensOut;

    // Transfer gameTokens to the liquity pool
    gameToken.transferFrom(msg.sender, address(this), gameTokens);

    // Transfer tokenOut to the user
    stableToken.transfer(msg.sender, stableTokensOut);

    // Update the reserves
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    emit Sell(msg.sender, gameTokens, stableTokensOut, newPrice);
    emit NewPrice(newPrice);
  }

  ///@dev The community decided (after launch) to open the pool when the farm's balance reaches 5M BCT.
  ///@dev When that happens, we'll get the current block number and set it as the startBlock.
  function isOpenForSelling() public pure returns (bool) {
    return true;
  }

  function getCommunityFeePct(uint256 stasherLevel) public view returns (uint256 feeInPct) {
    require(isOpenForSelling(), "Closed for selling");

    uint256 _stasherDiscount = stasherLevel * config.stasherDiscount; // has to be divided by 100

    uint256 monthsPassed = (block.number - startBlock) / 864000;

    if (monthsPassed > config.maxMonths) {
      monthsPassed = config.maxMonths;
    }

    uint256 steepMonths = monthsPassed >= config.steepCurveMonths + config.closedForMonths
      ? config.steepCurveMonths
      : monthsPassed - config.closedForMonths;

    uint256 gradualMonths = monthsPassed >= config.steepCurveMonths + config.closedForMonths
      ? monthsPassed - (config.steepCurveMonths + config.closedForMonths)
      : 0;

    uint256 baseFee = (config.baseCommunityFee - steepMonths * 10) - (gradualMonths * config.stasherDiscount);

    if (_stasherDiscount > baseFee) {
      return 0;
    } else {
      return baseFee - _stasherDiscount;
    }
  }

  function addLiquidity(uint256 amountOfBct, uint256 amountOfStabletokens) external {
    // get reserves
    (uint256 _gameTokenReserve, uint256 _stableTokenReserve) = getReserves();

    /*
    Check if the ratio of tokens supplied is proportional
    to reserve ratio to satisfy x * y = k for price to not
    change if both reserves are greater than 0
    */
    if (_gameTokenReserve > 0 || _stableTokenReserve > 0) {
      require(
        amountOfBct * _stableTokenReserve == amountOfStabletokens * _gameTokenReserve,
        "Unbalanced Liquidity Provided"
      );
    }

    // Transfer tokens to the liquidity pool
    if (amountOfBct > 0) {
      gameToken.transferFrom(msg.sender, address(this), amountOfBct);
    }
    if (amountOfStabletokens > 0) {
      stableToken.transferFrom(msg.sender, address(this), amountOfStabletokens);
    }

    // Update the reserves
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    emit LiquidityAdded(msg.sender, amountOfBct, amountOfStabletokens, newPrice);
    emit NewPrice(newPrice);
  }

  // Private function to update liquidity pool reserves
  function _update(uint256 _gameTokenReserve, uint256 _stableTokenReserve) private {
    gameTokenReserve = _gameTokenReserve;
    stableTokenReserve = _stableTokenReserve;
  }

  ////////////////////////////
  // Operator Functions
  function burnBct(uint256 amount) external onlyRole(UPDATER_ROLE) {
    gameToken.burn(amount);
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));

    emit NewPrice(getPrice());
  }

  function buyAndBurn(uint256 amountIn) external mutex onlyRole(UPDATER_ROLE) returns (uint256 amountBurned) {
    require(amountIn > 0, "Insufficient Amount");
    amountBurned = quoteStableToGameTokens(amountIn);

    // sends the money to the commonwealth fund
    stableToken.transferFrom(msg.sender, bkCommonwealthFund, amountIn);

    emit AddToFund(amountIn);
  }

  function actuallyBuyAndBurn(uint256 amountIn) external mutex onlyRole(UPDATER_ROLE) returns (uint256 amountBurned) {
    require(amountIn > 0, "Insufficient Amount");
    amountBurned = quoteStableToGameTokens(amountIn);

    stableToken.transferFrom(msg.sender, address(this), amountIn);

    // burn tokenOut
    gameToken.burn(amountBurned);

    // Update the reserves
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));

    uint256 newPrice = getPrice();
    emit BuyAndBurn(msg.sender, amountIn, amountBurned, newPrice);
    emit NewPrice(newPrice);
  }

  function recoverERC20(address tokenAddress, address to, uint256 amount) external override onlyRole(OPERATOR_ROLE) {
    IBkERC20(tokenAddress).transfer(to, amount);

    // Update the reserves
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));
    uint256 newPrice = getPrice();
    emit NewPrice(newPrice);
  }

  function setGameToken(address _gameToken) external onlyRole(OPERATOR_ROLE) {
    gameToken = IBkERC20(_gameToken);
  }

  function setStabletoken(address _stableToken) external onlyRole(OPERATOR_ROLE) {
    stableToken = IBkERC20(_stableToken);
  }

  function setStasher(address _stasherAddress) external onlyRole(OPERATOR_ROLE) {
    stasher = IBkStasher(_stasherAddress);
  }

  function setStartBlock(uint256 _startBlock) external onlyRole(OPERATOR_ROLE) {
    startBlock = _startBlock;
  }

  function setConfig(Config calldata _config) external onlyRole(OPERATOR_ROLE) {
    config = _config;
  }

  function setGasPriceLimit(uint256 _gasLimit) external onlyRole(OPERATOR_ROLE) {
    _setGasPriceLimit(_gasLimit);
  }

  function setLockPeriod(uint256 blocks) external onlyRole(OPERATOR_ROLE) {
    _setLockPeriod(blocks);
  }

  function openForSelling() external onlyRole(OPERATOR_ROLE) {
    startBlock = block.number;
    config.maxMonths = 12;
    config.closedForMonths = 0;
  }

  function resetReserves() external onlyRole(OPERATOR_ROLE) {
    _update(gameToken.balanceOf(address(this)), stableToken.balanceOf(address(this)));
  }

  function setBkCommonwealthFund(address _bkCommonwealthFund) external onlyRole(OPERATOR_ROLE) {
    bkCommonwealthFund = _bkCommonwealthFund;
  }
}
