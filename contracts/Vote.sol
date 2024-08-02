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

    error Vote__SetVoteTimesCantBeZero();
    error Vote__VotingIsClosed();
    // error Vote__UserTokenIsLocked(address user);

    modifier isOpen() {
        if (block.timestamp >= startTime && block.timestamp < endTime) {
            _;
        } else {
            revert Vote__VotingIsClosed();
        }
    }

    constructor(
        uint256 _initialAmount
    ) ERC20("Vote", "VOT") Ownable(msg.sender) {
        _mint(msg.sender, _initialAmount);
    }

    /// @notice to submit users vote and make a transaction their tokens to Vote contract and the contract will keep them until the end of election round time.
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
            revert("You've already voted on opposite!");
        }
        _transferToSubmitVote(voteAmount);
        s_votes[round][msg.sender].vote = vote;
        s_votes[round][msg.sender].amount += voteAmount;
        s_resultWithWeight[round][vote] = _howMuchVoteWeigh(msg.sender); // It is a premetitive protection against bad behaver from big wallets, it will weigh their votes by divide into 10, 90, 910 once tokens go further than specified thresholds
        emit VoteSubmited(vote, voteAmount);
        return true;
    }

    /// @notice it will trigger a withdraw request by user
    /// @notice user can withdraw before the end of election round and their vote will become false and zero amount token
    /// @param _round it will specify the round of election that the user wants to withdraw tokens from to assure that the round is already has done
    function withdrawalRequest(uint32 _round) external returns (bool success) {
        // trigger withdraw before 30mins end of the election
        if (_round == round && block.timestamp < endTime - 30 minutes) {
            _evaluateUserVoteToRemoveBeforeEnd();
            return true;
        }

        // close and suspend anyone to withdraw until the endTime exceed
        if (
            _round == round &&
            block.timestamp >= endTime - 30 minutes &&
            block.timestamp <= endTime
        ) {
            revert("The election is not finish yet.");
        }

        uint amount = s_votes[_round][msg.sender].amount;
        require(
            amount > 0,
            "The user did not attend to the specified election round or already has withdrawn their tokens."
        );
        require(_safeWithdrawal(msg.sender, amount), "Withdrawal failed.");
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
        if (endTime >= block.timestamp) {
            revert("Vote is still ongoing, need to be done.");
        }

        if (_startTime == 0 || _endTime == 0) {
            revert Vote__SetVoteTimesCantBeZero();
        }

        require(_startTime > block.timestamp, "The time has already over.");

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

    /* Not a good idea to use this kind of function cause it's against policy and keeping users data private */
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
        if (userElection >= 1500 && userElection <= 100000) {
            return userElection / 10;
        } else if (userElection < 1000000 && userElection > 100000) {
            return userElection / 90;
        } else if (userElection > 1000000) {
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
        require(transfer(address(this), _value), "Transfer failed.");
        return true;
    }

    function _evaluateUserVoteToRemoveBeforeEnd()
        private
        returns (bool success)
    {
        UserVote memory userVote = s_votes[round][msg.sender];
        uint weightAmount = _howMuchVoteWeigh(msg.sender);
        s_resultWithWeight[round][userVote.vote] -= weightAmount;
        s_votes[round][msg.sender].vote = false;
        s_votes[round][msg.sender].amount = 0;
        require(
            _safeWithdrawal(msg.sender, userVote.amount),
            "Withdrawal failed."
        );
        return true;
    }

    /// @dev NEED WORK - implement the logic to prevent users withdraw more than their assets
    /// @notice will give the user the ability to get their tokens back
    /// @param to msg.sender the user address
    /// @param _amount amount of tokens
    /// @return success whether it is true or false
    function _safeWithdrawal(
        address to,
        uint _amount
    ) private returns (bool success) {
        _transfer(address(this), to, _amount);
        return true;
    }
}
