// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../../utils/Blocklistable.sol";

contract AdminUpgradeableERC721 is
  ERC721EnumerableUpgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  Blocklistable
{
  bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE"); // EOA that can pause, unpause, configure the blocklist, and setBaseTokenURI
  bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE"); // Contracts that can Mint tokens
  bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE"); // Contracts that can Burn tokens

  uint256 public nextNftId;
  string public baseTokenURI;

  function __AdminUpgradeableERC721_init(
    string memory _name,
    string memory _symbol,
    string memory _baseTokenURI,
    address _operator,
    address _blocklistAddress
  ) public onlyInitializing {
    __ERC721_init(_name, _symbol);
    __ERC721Enumerable_init();
    __Pausable_init();
    _setBlocklist(_blocklistAddress);

    _setupRole(DEFAULT_ADMIN_ROLE, _operator);
    _setupRole(OPERATOR_ROLE, _operator);

    baseTokenURI = _baseTokenURI;
    nextNftId = 1; // Start tokenIds at 1
  }

  function tokensOfOwner(address _owner) external view returns (uint256[] memory) {
    uint256 tokenCount = balanceOf(_owner);
    uint256[] memory tokensId = new uint256[](tokenCount);
    for (uint256 i = 0; i < tokenCount; i++) {
      tokensId[i] = tokenOfOwnerByIndex(_owner, i);
    }

    return tokensId;
  }

  /// @dev Mandatory override
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(AccessControlUpgradeable, ERC721EnumerableUpgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function mintTo(address to) external onlyRole(MINTER_ROLE) {
    _doMint(to);
  }

  function burnFrom(address account, uint256 tokenId) external virtual {
    require(
      ownerOf(tokenId) == account || isApprovedForAll(account, _msgSender()) || hasRole(BURNER_ROLE, _msgSender()),
      "forbidden"
    );

    _burn(tokenId);
  }

  function setBaseTokenURI(string memory _baseTokenURI) external onlyRole(OPERATOR_ROLE) {
    baseTokenURI = _baseTokenURI;
  }

  function _doMint(address to) internal {
    _mint(to, nextNftId);
    nextNftId++;
  }

  function _doMintMany(address to, uint256 amount) internal {
    uint256 id = nextNftId;

    for (uint256 i = 0; i < amount; i++) {
      _mint(to, id);
      id++;
    }

    nextNftId = id;
  }

  function _doMintForMany(address[] memory owners) internal {
    uint256 id = nextNftId;

    for (uint256 i = 0; i < owners.length; i++) {
      _mint(owners[i], id);
      id++;
    }

    nextNftId = id;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal virtual override(ERC721EnumerableUpgradeable) {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);

    require(!paused(), "paused");
    require(!_areBlocklisted(from, to), "Sender and/or recipient is blocklisted");
  }

  function pause() public onlyRole(OPERATOR_ROLE) whenNotPaused {
    _pause();
  }

  function unpause() public onlyRole(OPERATOR_ROLE) whenPaused {
    _unpause();
  }
}
