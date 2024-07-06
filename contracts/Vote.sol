// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title A simple voting system
/// @notice This contract not audited and never use in production.
/// @dev it'll create an underlying ERC20 token to give the ability of voting to users via token (governance token).
contract Vote is ERC20, Ownable {
    uint32 public startTime;
    uint32 public endTime;
    uint32 public round;

    struct UserVote {
        bool vote;
        uint amount;
    }

    string public desc;
    /**
        @notice to keep track of individuals votes and the weight of votes as final result in each round
    */
    mapping(uint32 => mapping(address => UserVote)) private s_votes;
    mapping(uint32 => mapping(bool => uint)) private s_resultWithWeight;

    event VoteSubmited(bool vote, uint voteWeight);
    event TimeHasBeenSet(
        uint32 startTime,
        uint32 endTime,
        uint32 indexed round,
        string desc
    );
    event MadeWithdrawal(address indexed voter, uint amount);
    // event ApproveInternal(address indexed spender, uint amount);

    error SetVoteTimesCantBeZero();
    error VotingIsClosed();
    error TokenUserIsLocked(address user);

    modifier isOpen() {
        if (block.timestamp >= startTime && block.timestamp < endTime) {
            _;
        } else {
            revert VotingIsClosed();
        }
    }

    constructor(
        uint256 _initialAmount
    ) ERC20("Vote", "VOT") Ownable(msg.sender) {
        _mint(msg.sender, _initialAmount);
    }

    /// @notice to submit users vote and make a transaction their tokens to Vote contract and the contract will keep them until the end of election round time.
    /// @dev note make the transfer to transferFrom to contract have the control to take the determined amount instead of user send it directly
    function elect(
        bool vote,
        uint256 voteAmount
    ) external isOpen returns (bool voted) {
        require(
            balanceOf(msg.sender) >= voteAmount,
            "User don't have enough balance."
        );
        if (
            s_votes[round][msg.sender].amount > 0 &&
            s_votes[round][msg.sender].vote != vote
        ) {
            revert("You've already voted opposite!");
        }
        _transferToSubmitVote(voteAmount);
        s_votes[round][msg.sender].vote = vote;
        s_votes[round][msg.sender].amount += voteAmount;
        s_resultWithWeight[round][vote] = _howMuchVoteWeigh(msg.sender); // It is a premetitive protection against bad behaver from big wallets, it will weigh their votes by divide into 10, 90, 910 once tokens go further than specified thresholds
        emit VoteSubmited(vote, voteAmount);
        return true;
    }

    /// @notice it will trigger a withdraw request by user
    /// @dev it will trigger a withdraw request by user to get their locked tokens if they have any locked token in provided round. for now users must input the round to check whether they have anything
    /// @dev note implement the logic to users be able to whithdraw before round starts and also prevent of bad acting with deleting the users votes' from mapping storage
    /// @param _round it will specify the round of election that the user wants to withdraw tokens from to assure that the round is already has done
    function withdrawalRequest(uint32 _round) external returns (bool success) {
        if (_round == round && block.timestamp < startTime - 10 minutes) {
            // TODO: implement the logic to users be able to whithdraw before round starts and also prevent of bad acting with deleting the users votes' from mapping storage
        }

        require(block.timestamp > endTime, "The election is not finish yet.");
        uint amount = s_votes[_round][msg.sender].amount;
        require(
            amount > 0,
            "The user did not attend to the prior elections or already has withdrawn their tokens."
        );
        _withdrawal(msg.sender, amount);
        emit MadeWithdrawal(msg.sender, amount);
        return true;
    }

    /// @notice it will return back the result in weight
    /// @param _round the round to obtain the data from
    /// @param _vote the vote TRUE or FALSE to obtain the data from
    /// @dev note still needs work because it will return result if we pass a true of false as _vote parameter to get the specific section data and won't give back all data in a round altogether
    function getResultWithWeight(
        uint32 _round,
        bool _vote
    ) external view returns (uint) {
        return s_resultWithWeight[_round][_vote];
    }

    /// @notice This is will set a specific time in the future to start and end voting
    /// @dev we assume that the dev will put the description for the vote on UI of web application, so it's not a good idea to useing in a real situation. didn't implement it because of keeping simple everything maybe add it in the future
    /// @param _startTime set start time of the next voting round
    /// @param _endTime set the end time of the next voting round
    function setTimes(
        uint32 _startTime,
        uint32 _endTime,
        string memory _desc
    ) public onlyOwner {
        if (_startTime == 0 || _endTime == 0) {
            revert SetVoteTimesCantBeZero();
        }
        require(_startTime > block.timestamp, "The time has already over.");
        // @TODO add to the require that vote last at least for about 72h to avoid time difference and also users know about ongoing voting
        require(
            _startTime < _endTime,
            "The start time of voting can not be set before the end time."
        );
        startTime = _startTime;
        endTime = _endTime;
        desc = _desc;
        round++;
        emit TimeHasBeenSet(_startTime, _endTime, round, desc);
    }

    /// @notice to return the amount of a user voted in specific round for clarifying
    /// @param round_ vote round
    /// @param voter user address
    /// @return to return the amount of vote of a user
    function howMuchAUserVotedPerRound(
        uint32 round_,
        address voter
    ) public view returns (uint) {
        return s_votes[round_][voter].amount;
    }

    /// @notice to determine how much a user's vote weigh
    /// @param voter the voter address
    /// @return userElection return the weight of user vote based on their tokens voted
    function _howMuchVoteWeigh(address voter) internal view returns (uint) {
        uint userElection = s_votes[round][voter].amount;
        if (userElection > 100) {
            return userElection / 10;
        } else if (userElection > 1000) {
            return userElection / 90;
        } else if (userElection > 10000) {
            return userElection / 910;
        }
        return userElection;
    }

    /// @notice will make a transfer erc20 tx tokens user voted to contract address to lock it until the end round
    /// @param _value the amount of tokens voted by user
    /// @return success whether it is true or false
    function _transferToSubmitVote(
        uint _value
    ) internal returns (bool success) {
        // super.approve(msg.sender, _value);
        // bool result = ERC20.transferFrom(_msgSender(), address(this), _value);
        require(transfer(address(this), _value), "Tx failed.");
        return true;
    }

    /// @notice will give the user the ability to get their tokens back
    /// @dev note change transferFrom to transfer directly to avoid users have the ability to take control over contract assets
    /// @param to msg.sender the user address
    /// @param _amount amount of tokens
    /// @return success whether it is true or false
    function _withdrawal(
        address to,
        uint _amount
    ) private returns (bool success) {
        _transfer(address(this), to, _amount);
        return true;
    }
}

// function _approve(address _spender, uint _amount) private returns (bool) {
//     approve(_spender, _amount)
//     // _allowances[address(this)][_spender] = _amount;
//     // emit ApproveInternal(_spender, _amount);
//     // return true;
// }

// function _checkIfLocked(address user) internal view returns (bool) {
//     if ( s_votes[round][user].amount > 0 ) {
//         return false;
//     }
// }

/// @dev after an election has done owner must trigger the function to vote be done and individuals can withdraw their tokens
// function _ElectionStatusToFinish() private {

// }

// function _determineUserVoteToLock(address user) private view returns (uint) {
//     return s_votes[round][user].amount;
// }
