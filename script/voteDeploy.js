const { ethers } = require("hardhat");

async function main() {
  const voteFactory = await ethers.getContractFactory("Vote");
  console.log("Vote contract is Deploying...");
  const vote = await voteFactory.deploy(1e10);
  await vote.waitForDeployment();
  console.log("Contract is deployed at", vote.target);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.log(e);
    process.exit(1);
  });
