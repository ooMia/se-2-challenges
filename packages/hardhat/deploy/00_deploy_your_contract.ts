import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DEX } from "../typechain-types/contracts/DEX";
import { Balloons } from "../typechain-types/contracts/Balloons";

/**
 * Deploys a contract named "YourContract" using the deployer account and
 * constructor arguments set to the deployer address
 *
 * @param hre HardhatRuntimeEnvironment object.
 */
const deployYourContract: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  /*
    On localhost, the deployer account is the one that comes with Hardhat, which is already funded.

    When deploying to live networks (e.g `yarn deploy --network sepolia`), the deployer account
    should have sufficient balance to pay for the gas fees for contract creation.

    You can generate a random account with `yarn generate` which will fill DEPLOYER_PRIVATE_KEY
    with a random private key in the .env file (then used on hardhat.config.ts)
    You can run the `yarn account` command to check your balance in every network.
  */
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  await deploy("Balloons", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  });
  const balloons: Balloons = await hre.ethers.getContract("Balloons", deployer);
  const balloonsAddress = await balloons.getAddress();

  await deploy("DEX", {
    from: deployer,
    args: [balloonsAddress],
    log: true,
    autoMine: true,
  });

  const dex = (await hre.ethers.getContract("DEX", deployer)) as DEX;

  await balloons.transfer(process.env.ADMIN_ADDRESS!, "" + 10 * 10 ** 18);

  const dexAddress = await dex.getAddress();
  console.log("Approving DEX (" + dexAddress + ") to take Balloons from main account...");
  await balloons.approve(dexAddress, hre.ethers.parseUnits("1500000", "gwei"));
  console.log("INIT exchange...");
  await dex.init(hre.ethers.parseUnits("1500000", "gwei"), {
    value: hre.ethers.parseUnits("1500000", "gwei"),
    gasLimit: 200000,
  });
};

export default deployYourContract;

// Tags are useful if you have multiple deploy files and only want to run one of them.
// e.g. yarn deploy --tags YourContract
deployYourContract.tags = ["Balloons", "DEX"];
