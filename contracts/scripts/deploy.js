const { ethers } = require("hardhat");
const hre = require('hardhat');

function getSigner(network) {
    const signer = new ethers.Wallet(process.env.WALLET_PRIVATE_KEY).connect(
        new ethers.providers.JsonRpcProvider(network.rpc)
    );
    return signer;
}

// async function setDestLzEndpoint(endpointAddress, sourceAddress, destAddress) {
//   const signer = getSigner(network);
//   const LayerZeroEndpointContract = ethers.Contract(endpointAddress, abi, signer);
// }

async function deployContract(contractName, endpointAddress) {
  const contractDeployInstance = await ethers.getContractFactory(contractName);
  const contract = await contractDeployInstance.deploy(endpointAddress);
  await contract.deployed();
  return contract.address;
}

async function main() {
  const network_name = hre.network.name;
  let network_config = JSON.parse(fs.readFileSync("./xdapp.config.json").toString());
  let network = network_config.networks[network_name];
  const endpointAddres = network.endpointAddress;
  const contractName = network.contractType == "main" ? "AnyChainDAO" : "SideChainDAO";
  const contractAddress = await deployContract(contractName, bridgeAddress);
  network.deployedAddress = contractAddress;
  console.log(`${contractName} Contract deployed to: ${contractAddress}`);
  network_config.networks[network_name] = network;
  fs.writeFileSync("./dapp.config.json", JSON.stringify(network_config, null, 4));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });