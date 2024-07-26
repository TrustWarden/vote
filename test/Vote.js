const { ethers } = require("hardhat");
const { expect } = require("chai");
const {
  time,
  mine,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Vote Contract", () => {
  async function setup() {
    const oneDay = 60 * 60 * 24;
    const fixedAmountMint = 1e10; // amount to mint at contructor as total supply

    const [owner, alice, bob] = await ethers.getSigners();
    const Vote = await ethers.getContractFactory("Vote");
    const vote = await Vote.deploy(fixedAmountMint);

    const fireStartTime = (await time.latest()) + 10;
    const fireEndTime = (await time.latest()) + oneDay;
    const desc = "Let's make the Web3 great again!";

    return {
      vote,
      owner, // 1st address
      alice, // 2nd address
      bob, // 3rd address
      oneDay,
      fireStartTime,
      fireEndTime,
      desc,
    };
  }

  it("Should assign owner correctly", async () => {
    const { vote, owner } = await loadFixture(setup);

    expect(await vote.owner()).to.equal(owner.address);
  });

  it("Should totalSupply be equal to owner's balance", async () => {
    const { vote, owner } = await loadFixture(setup);

    expect(await vote.totalSupply()).to.equal(
      await vote.balanceOf(owner.address)
    );
  });

  describe("Set time:", () => {
    it("Must set correct time and round for the election", async () => {
      const { vote, fireStartTime, fireEndTime, desc } = await loadFixture(
        setup
      );

      await vote.setTimes(fireStartTime, fireEndTime, desc);
      const startTime = await vote.startTime();
      const endTime = await vote.endTime();
      const round = await vote.round();

      expect(startTime).to.equal(fireStartTime);
      expect(endTime).to.equal(fireEndTime);
      expect(round).to.equal(1);
    });

    it("Should emit TimeHasBeenSet event", async () => {
      const { vote, fireStartTime, fireEndTime, desc } = await loadFixture(
        setup
      );

      await expect(vote.setTimes(fireStartTime, fireEndTime, desc))
        .to.emit(vote, "TimeHasBeenSet")
        .withArgs(fireStartTime, fireEndTime, 1, desc);
    });

    it("Should revert by calling setTimes method that time is already passed", async () => {
      const { vote } = await loadFixture(setup);

      await expect(
        vote.setTimes(1000, 1000, "Testing timing...")
      ).to.be.revertedWith("The time has already over.");
    });

    it("Should throw an error when input zero to start or end times", async () => {
      const { vote } = await loadFixture(setup);

      await expect(
        vote.setTimes(0, 0, "Testing zero time")
      ).to.be.revertedWithCustomError(vote, "SetVoteTimesCantBeZero");
    });

    it("Must revert when entring start time with smaller input than end time", async () => {
      const { vote } = await loadFixture(setup);

      await expect(
        vote.setTimes((await time.latest()) + 10, 1001, "Testing revese time")
      ).to.be.revertedWith(
        "The start time of voting can not be set before the end time."
      );
    });

    it("Must revert if someone else's than owner try to set time for election", async () => {
      const { vote, alice, fireStartTime, fireEndTime, desc } =
        await loadFixture(setup);

      await expect(
        vote.connect(alice).setTimes(fireStartTime, fireEndTime, desc)
      ).to.be.revertedWithCustomError(vote, "OwnableUnauthorizedAccount");
    });
  });

  describe("Elect:", () => {
    async function setupTimeAndElection() {
      const { vote, owner, alice, bob, fireStartTime, fireEndTime, desc } =
        await loadFixture(setup);

      await vote.setTimes(fireStartTime, fireEndTime, desc);
      await time.increase(3600);

      const amountToVote = 5000000;

      return { vote, owner, alice, bob, amountToVote };
    }

    it("Should decrease amount of tokens from voter address and increase into contract address correclty", async () => {
      const { vote, owner, amountToVote } = await loadFixture(
        setupTimeAndElection
      );

      const ownerBalanceBeforeVoting = await vote.balanceOf(owner.address);
      await vote.elect(true, amountToVote);
      const ownerBalanceAfterVoting =
        Number(ownerBalanceBeforeVoting) - amountToVote; // convert ownerBalanceBeforeVoting BigInt to Number

      expect(await vote.balanceOf(vote.target)).to.equal(amountToVote);
      expect(await vote.balanceOf(owner.address)).to.equal(
        ownerBalanceAfterVoting
      );
    });

    it("Should assign correct amount of a user tokens that participated", async () => {
      const { vote, owner, amountToVote } = await loadFixture(
        setupTimeAndElection
      );

      await vote.elect(true, amountToVote);

      expect(await vote.howMuchAUserVotedPerRound(1, owner.address)).to.equal(
        amountToVote
      );
    });

    // cause the _howMuchVoteWeigh is internal function, use TestVote to expose the internal functions to be able to test
    it("Should save correct weighted vote in mapping result", async () => {
      const TestVote = await ethers.getContractFactory("TestInternalVote");
      const testVote = await TestVote.deploy();
      const [owner] = await ethers.getSigners();

      const oneDay = 60 * 60 * 24;
      const fireStartTime = (await time.latest()) + 10;
      const fireEndTime = (await time.latest()) + oneDay;
      const desc = "Let's make the Web3 great again!";
      const amountToVote = 5000000;

      await testVote.setTimes(fireStartTime, fireEndTime, desc);
      await time.increase(3600);
      await testVote.elect(true, amountToVote);

      expect(await testVote.exposed_howMuchVoteWeigh(owner.address)).to.equal(
        Number(await testVote.getResultWithWeight(1, true))
      );
    });

    it("Must revert if user don't have enough tokens", async () => {
      const { vote, alice, amountToVote } = await loadFixture(
        setupTimeAndElection
      );

      await expect(
        vote.connect(alice).elect(false, amountToVote)
      ).to.be.revertedWith("User don't have enough balance.");
    });

    it("Must revert if a user wants to voting on opposite side after already voted in that election", async () => {
      const { vote, amountToVote } = await loadFixture(setupTimeAndElection);

      await vote.elect(true, amountToVote);

      await expect(vote.elect(false, amountToVote)).to.be.revertedWith(
        "You've already voted on opposite!"
      );
    });

    it("Must revert when the election is closed withouting setting up a new round", async () => {
      const { vote } = await loadFixture(setup);

      await expect(vote.elect(true, 1000)).to.be.revertedWithCustomError(
        vote,
        "VotingIsClosed"
      );
    });
  });

  describe("Withdraw:", () => {
    async function setupElectionAndMadeElect() {
      const { vote, owner, alice, bob, fireStartTime, fireEndTime, desc } =
        await loadFixture(setup);

      // start vote round
      await vote.setTimes(fireStartTime, fireEndTime, desc);
      await time.increase(3600); // 1hr

      // Getting balance and made vote
      const balanceBeforeVote = await vote.balanceOf(owner.address);
      const amountToVote = 5000000;
      await vote.elect(true, amountToVote);

      // increase the time by 1 day to vote be done
      await time.increase(86400);

      return { vote, owner, alice, bob, amountToVote, balanceBeforeVote };
    }

    it("Should return back correct balance after made withdraw and emit MadeWithdrawal event", async () => {
      const { vote, owner, amountToVote, balanceBeforeVote } =
        await loadFixture(setupElectionAndMadeElect);

      expect(await vote.withdrawalRequest(1))
        .to.emit(vote, "MadeWithdrawal")
        .withArgs(owner.address, amountToVote);

      const currentBalance = await vote.balanceOf(owner.address);
      expect(currentBalance).to.equal(balanceBeforeVote);
    });

    it("Must revert if the election is not finish", async () => {
      const { vote, fireStartTime, fireEndTime, desc } = await loadFixture(
        setup
      );

      await vote.setTimes(fireStartTime, fireEndTime, desc);
      await time.increase(3600); // 1 hr
      await vote.elect(true, 5000000);

      await expect(vote.withdrawalRequest(1)).to.be.revertedWith(
        "The election is not finish yet."
      );
    });

    it("Must revert if the user didn't attend to the specified round", async () => {
      const { vote, alice } = await loadFixture(setupElectionAndMadeElect);

      await expect(vote.connect(alice).withdrawalRequest(1)).to.be.revertedWith(
        "The user did not attend to the specified election round or already has withdrawn their tokens."
      );
    });

    it();
  });
});
