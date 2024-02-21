// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBkChar {
  struct BkChar {
    uint256 id; // the NFT ID
    string name; // is an empty string up until the owner sets it
    string imageUrl; // is an empty string up until the owner sets it
    address currentOwner; // the current owner
    uint256 squadId; // the squad ID this NFT is in
    uint256 collection; // the collection this NFT belongs to
    uint256 baseFarm; // how many Weis of BCT this NFT will generate per cycle
    uint256 farmPerBlock; // the final farm per block
    uint256[] attributes; // species, rarity, rank, agility, nuts, evos
    uint256[] traits; // from 0 to 3 traits, that are numbers from 1 to 50+
    uint256[] skills; // multipliers for the farming of specific kinds of resources
    bool isDead; // whether the NFT is dead or not
  }

  enum ATTRIBUTE {
    SPECIES,
    RARITY,
    RANK,
    AGILITY,
    NUTS,
    EVOS
  }
}
