const { ethers, network } = require("hardhat")
const sleep = require("sleep-promise")

async function mockSpin() {
  const contract = await ethers.getContract("Wheel")
  const tx = await contract.spin()
  const txReceipt = await tx.wait(1)
  const requestId = txReceipt.events[1].args.requestId
  console.log("Spin the wheel with requestId", requestId)
  console.log("waiting the wheel to get random words")
  await sleep(20000)
  await mockVrf(requestId, contract)
}

async function mockVrf(requestId, contract) {
  console.log("We on a local network? Ok let's pretend...")
  const vrfCoordinatorV2Mock = await ethers.getContract("VRFCoordinatorV2Mock")
  await vrfCoordinatorV2Mock.fulfillRandomWords(requestId, contract.address)
  console.log("Responded!")
  console.log(vrfCoordinatorV2Mock)
  // const recentWinner = await contract.getRecentWinner()
  // console.log(`The winner is: ${recentWinner}`)
}

mockSpin()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
