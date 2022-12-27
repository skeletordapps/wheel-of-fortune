import { getNamedAccounts, network, ethers, deployments } from "hardhat"
import { developmentChains } from "../../helper-hardhat-config"
import { assert, expect } from "chai"
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber } from "ethers"

enum prize {
  FREESPIN,
  X2,
  WIN5,
  WIN10,
  WIN20,
  WIN30,
  LOSE2,
  LOSE3,
  LOSE5,
  LOSEALL,
}

!developmentChains.includes(network.name)
  ? describe
  : describe("Wheel Unit Tests", () => {
      let wheel: any
      let deployer: string
      let accounts: SignerWithAddress[]
      let owner: SignerWithAddress
      let player: SignerWithAddress
      let minWheelBalanceAmount: BigNumber
      let enterFee: BigNumber
      let spinFee: BigNumber

      beforeEach(async () => {
        accounts = await ethers.getSigners()
        deployer = (await getNamedAccounts()).deployer
        owner = accounts[0]
        player = accounts[1]
        await deployments.fixture(["all"])

        wheel = await ethers.getContract("Wheel", deployer)
        enterFee = await wheel.enterFee()
        spinFee = await wheel.spinFee()
        minWheelBalanceAmount = enterFee.mul(10)
      })

      describe("constructor", () => {
        it("Should initialize the wheel correctly", async () => {
          const wheelState = await wheel.state()
          assert.equal(wheelState.toString(), "0") // IDDLE
        })
      })

      describe("On Refill", () => {
        it("Should revert when is not the owner", async () => {
          await expect(
            player.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Should receive eth from owner", async () => {
          const initialBalance = await wheel.getBalance()
          await owner.sendTransaction({ to: wheel.address, value: enterFee })

          const endingBalance = await wheel.getBalance()
          assert.equal(initialBalance.add(enterFee).toString(), endingBalance.toString())
        })

        it("Should emit an event when wheel is refilled", async () => {
          await expect(owner.sendTransaction({ to: wheel.address, value: enterFee })).to.emit(
            wheel,
            "WheelFilled"
          )
        })

        it("Should change wheel state to OPEN", async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          const state = await wheel.state()
          assert.equal(state, "1") // OPEN
        })

        it("Should emit an event when state turns to OPEN", async () => {
          await expect(
            owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          ).to.emit(wheel, "WheelIsOpen")
        })
      })

      describe("On Enter", () => {
        beforeEach(async () => {})

        it("Should raise error when try to enter when wheel is closed", async () => {
          await wheel.close()
          await expect(wheel.enter({ value: enterFee })).to.be.revertedWithCustomError(
            wheel,
            "Wheel__NotOpen"
          )
        })

        it("Should revert when user don't pay enough", async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          await expect(wheel.enter()).to.be.revertedWithCustomError(
            wheel,
            "Wheel__NotEnoughToEnter"
          )
        })

        it("Should save new player", async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          wheel = wheel.connect(player)
          await wheel.enter({ value: enterFee })
          const numberOfPlayers = await wheel.playersCount()
          assert.equal(numberOfPlayers.toString(), "1")
        })

        it("Should store the new player's balance", async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          wheel = wheel.connect(player)
          await wheel.enter({ value: enterFee })
          const playerFromContract = await wheel.addressToPlayer(player.address)
          assert.equal(enterFee.toString(), playerFromContract["balance"].toString())
        })

        it("Should emit an event on enter", async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          wheel = wheel.connect(player)
          await expect(wheel.enter({ value: enterFee })).to.emit(wheel, "WheelEnter")
        })
      })

      describe("On Spin", () => {
        beforeEach(async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          wheel = wheel.connect(player)
          await wheel.enter({ value: enterFee })
        })

        it("Should raise error when try to spin a closed wheel", async () => {
          wheel = wheel.connect(owner)
          await wheel.close()
          wheel = wheel.connect(player)
          await expect(wheel.spin({ value: spinFee })).to.be.revertedWithCustomError(
            wheel,
            "Wheel__NotOpen"
          )
        })

        it("Should revert if player has no balance", async () => {
          wheel = wheel.connect(owner) // deployer
          await expect(wheel.spin()).to.be.revertedWithCustomError(wheel, "Wheel__PlayerNoBalance")
        })

        it("Should delivery prize", async () => {
          const startPlayerInfos = await wheel.addressToPlayer(player.address)
          const startPlayerPrize = await wheel.addressToPrize(player.address)
          await wheel.spin()
          const endPlayerPrize = await wheel.addressToPrize(player.address)
          const endPlayerInfos = await wheel.addressToPlayer(player.address)

          switch (endPlayerInfos.lastPrize) {
            case prize.FREESPIN:
              assert.equal(endPlayerInfos.balance.toString(), spinFee.mul(10).toString())
              break
            case prize.X2:
              assert.equal(
                startPlayerInfos.balance.sub(spinFee).mul(2).toString(),
                endPlayerPrize.toString()
              )
              break
            case prize.WIN5:
              assert.equal(
                startPlayerPrize.add(spinFee.mul(5)).toString(),
                endPlayerPrize.toString()
              )
              break
            case prize.WIN10:
              assert.equal(
                startPlayerPrize.add(spinFee.mul(10)).toString(),
                endPlayerPrize.toString()
              )
              break
            case prize.WIN20:
              assert.equal(
                startPlayerPrize.add(spinFee.mul(20)).toString(),
                endPlayerPrize.toString()
              )
              break
            case prize.WIN30:
              assert.equal(
                startPlayerPrize.add(spinFee.mul(30)).toString(),
                endPlayerPrize.toString()
              )
              break
            case prize.LOSE2:
              assert.equal(
                startPlayerInfos.balance.sub(spinFee).sub(spinFee.mul(2)).toString(),
                endPlayerInfos.balance.toString()
              )
              break
            case prize.LOSE3:
              assert.equal(
                startPlayerInfos.balance.sub(spinFee).sub(spinFee.mul(3)).toString(),
                endPlayerInfos.balance.toString()
              )
              break
            case prize.LOSE5:
              assert.equal(
                startPlayerInfos.balance.sub(spinFee).sub(spinFee.mul(5)).toString(),
                endPlayerInfos.balance.toString()
              )
              break
            case prize.LOSEALL:
              assert.equal(endPlayerInfos.balance.toString(), "0")
              break
            default:
              break
          }
        })

        it("Should emit an event", async () => {
          await expect(wheel.spin()).to.emit(wheel, "WheelPrizeSent")
        })

        it("Should set a player UNBALANCED when spent all bets", async () => {
          let playerState = await wheel.addressToPlayer(player.address)
          let balance = Number(ethers.utils.formatEther(playerState.balance.toString()))

          while (balance > 0) {
            await wheel.spin()
            playerState = await wheel.addressToPlayer(player.address)
            balance = Number(ethers.utils.formatEther(playerState.balance.toString()))
          }

          assert.equal(playerState.state, 2)
        })
      })

      describe("When Claim", () => {
        beforeEach(async () => {
          await owner.sendTransaction({ to: wheel.address, value: minWheelBalanceAmount })
          wheel = wheel.connect(player)
          await wheel.enter({ value: enterFee })
        })

        it("Should revert when has nothing to claim", async () => {
          await expect(wheel.claim(player.address)).to.be.revertedWithCustomError(
            wheel,
            "Wheel__NothingToClaim"
          )
        })

        it("Should let player claim it's prize", async () => {
          await wheel.spin()
          const { lastPrize } = await wheel.addressToPlayer(player.address)

          if (
            lastPrize === prize.X2 ||
            lastPrize === prize.WIN5 ||
            lastPrize === prize.WIN10 ||
            lastPrize === prize.WIN20 ||
            lastPrize === prize.WIN30
          ) {
            const startPlayerBalance = await player.getBalance()
            const accPrize = await wheel.addressToPrize(player.address)
            const tx = await wheel.claim(player.address)
            const txReceipt = await tx.wait(1)
            const txGasUsed = txReceipt.cumulativeGasUsed.mul(txReceipt.effectiveGasPrice)
            const endPlayerBalance = await player.getBalance()
            const endAccPrize = await wheel.addressToPrize(player.address)

            assert.equal(
              startPlayerBalance.sub(txGasUsed).add(accPrize).toString(),
              endPlayerBalance.toString()
            )
            assert.equal(endAccPrize.toString(), "0")
          }
        })
      })

      describe("On Close", () => {
        it("Should revert when is not the owner", async () => {
          wheel = wheel.connect(player)
          await expect(wheel.close()).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Should transfer all funds to owner", async () => {
          const initialBalance = await owner.getBalance()

          const txSend = await owner.sendTransaction({
            to: wheel.address,
            value: minWheelBalanceAmount,
          })
          const txSendReceipt = await txSend.wait(1)
          const sendTxGasUsed = txSendReceipt.cumulativeGasUsed.mul(txSendReceipt.effectiveGasPrice)

          wheel = wheel.connect(player)
          await wheel.enter({ value: enterFee })

          wheel = wheel.connect(owner)
          const txClose = await wheel.close()
          const txCloseReceipt = await txClose.wait(1)
          const closeTxGasUsed = txCloseReceipt.cumulativeGasUsed.mul(
            txCloseReceipt.effectiveGasPrice
          )
          const finalBalance = await owner.getBalance()

          assert.equal(
            initialBalance.add(enterFee).sub(sendTxGasUsed).sub(closeTxGasUsed).toString(),
            finalBalance.toString()
          )
        })

        it("Should emit an event after close the wheel", async () => {
          await expect(wheel.close()).to.emit(wheel, "WheelClosed")
        })
      })
    })
