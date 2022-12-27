import { BigNumber } from "ethers"
import { ethers } from "hardhat"

type Config = {
  [key: string]: {
    name: string
    subscriptionId: BigNumber
  }
}

export const networkConfig: Config = {
  42161: {
    name: "arbitrum",
    subscriptionId: BigNumber.from("1"),
  },
  5: {
    name: "goerli",
    subscriptionId: BigNumber.from("1"),
  },
  31337: {
    name: "hardhat",
    subscriptionId: BigNumber.from("1"),
  },
  localhost: {
    name: "localhost",
    subscriptionId: BigNumber.from("1"),
  },
}

export const developmentChains = ["hardhat", "localhost"]
