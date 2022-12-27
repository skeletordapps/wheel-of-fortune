import { ethers, network } from "hardhat"
import { developmentChains } from "../helper-hardhat-config"
import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"

const BASE_FEE = ethers.utils.parseEther("0.25")
const GAS_PRICE_LINK = 1e9

const mocks = async function (hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts, deployments } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const args = [BASE_FEE, GAS_PRICE_LINK]

  if (developmentChains.includes(network.name)) {
    log("Local network detected! Deploying mocks...")

    await deploy("VRFCoordinatorV2Mock", {
      from: deployer,
      log: true,
      args: args,
    })

    log("Mocks deployed!")
    log("----------------------------")
    log("You are deploying to a local network, you'll need a local network running to interact")
    log(
      "Please run `yarn hardhat console --network localhost` to interact with the deployed smart contracts!"
    )
    log("----------------------------------------------------------")
  }
}

export default mocks
mocks.tags = ["all", "mocks"]
