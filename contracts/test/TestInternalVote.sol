// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../Vote.sol";

contract TestInternalVote is Vote {
    constructor(uint _initial) Vote(_initial) {}

    function exposed_howMuchVoteWeigh(
        address target
    ) external view returns (uint) {
        return _howMuchVoteWeigh(target);
    }
}
