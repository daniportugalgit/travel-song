// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../utils/Blocklistable.sol";

contract AdminUpgradeableERC20 is
  ERC20BurnableUpgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  Blocklistable
{
  bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE"); // EOA that can pause, unpause, and configure the blocklist
  bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE"); // Contracts that can Mint tokens

  // [to burn, use the public function burnFrom(from, amount) while having enough allowance]

  function __AdminUpgradeableERC20_init(
    string memory _name,
    string memory _symbol,
    address _operator,
    uint256 _totalSupply,
    address _blocklistAddress
  ) internal onlyInitializing {
    __ERC20_init(_name, _symbol);
    __Pausable_init();
    __ReentrancyGuard_init();
    _setBlocklist(_blocklistAddress);

    _setupRole(DEFAULT_ADMIN_ROLE, _operator);
    _setupRole(OPERATOR_ROLE, _operator);

    if (_totalSupply > 0) {
      _mint(_operator, _totalSupply);
    }
  }

  function basicData() public view returns (string memory, string memory, uint256, uint256) {
    return (name(), symbol(), decimals(), totalSupply());
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
    require(!_areBlocklisted(from, to), "Sender and/or recipient is blocklisted");
  }

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
    _mint(to, amount);
  }

  function pause() public onlyRole(OPERATOR_ROLE) whenNotPaused {
    _pause();
  }

  function unpause() public onlyRole(OPERATOR_ROLE) whenPaused {
    _unpause();
  }
}
