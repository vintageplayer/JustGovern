const { ethers } = require("hardhat");

async function main() {
  // Deploy the AnyChainDAO contract
  const AnyChainDAO = await ethers.getContractFactory("AnyChainDAO");
  const anyChainDAO = await AnyChainDAO.deploy();
  await anyChainDAO.deployed();

  console.log("AnyChainDAO deployed to: ", anyChainDAO.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });