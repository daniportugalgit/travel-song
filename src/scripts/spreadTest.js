const BigNumber = require("bignumber.js");

function calculateFee(amount) {
  const amountInUnits = BigNumber(amount).div(1e18);
  let extraFeePct = amountInUnits.div(1000);
  if (extraFeePct > 50) {
    extraFeePct = 50;
  }

  console.log(
    `Selling ${BigNumber(amount)
      .div(1e18)
      .toFixed(2)} BCT will result in a fee multiplier of ${extraFeePct}`
  );
}

calculateFee(BigNumber(100).times(1e18));
calculateFee(BigNumber(1000).times(1e18));
calculateFee(BigNumber(2000).times(1e18));
calculateFee(BigNumber(3000).times(1e18));
calculateFee(BigNumber(4000).times(1e18));
calculateFee(BigNumber(5000).times(1e18));
calculateFee(BigNumber(10000).times(1e18));
calculateFee(BigNumber(15000).times(1e18));
calculateFee(BigNumber(20000).times(1e18));
calculateFee(BigNumber(25000).times(1e18));
calculateFee(BigNumber(50000).times(1e18));
calculateFee(BigNumber(75000).times(1e18));
calculateFee(BigNumber(100000).times(1e18));
