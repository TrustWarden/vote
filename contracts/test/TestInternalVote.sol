// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../Vote.sol";

contract TestInternalVote is Vote {
    constructor() Vote(1e10) {}

    function exposed_howMuchVoteWeigh(
        address target
    ) external view returns (uint) {
        return _howMuchVoteWeigh(target);
    }
}
