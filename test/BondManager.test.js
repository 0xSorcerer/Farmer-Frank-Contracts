const Web3 = require('web3')
const web3 = new Web3()

const ethers = require('ethers')
const truffleAssertions = require('truffle-assertions')

var fNFTBond = artifacts.require('fNFTBond')
var BondManager = artifacts.require('BondManager')
var ERC20 = artifacts.require('ERC20')

contract("BondManager", async (accounts) => {

    const tokenName = "JOE"
    const tokenSymbol = "JOE"
    const bondName = 'fNFT Bond - (JOE)'
    const bondSymbol = 'fNFTB01'

    const tokenBalance = "10000000000000000000000000" //10^25

    this.levelToAdd = {
        name: "Level V",
        basePrice: "10000",
        weight: "120",
        sellableAmount: "0"
    }

    beforeEach(async () => {
        this.token = await ERC20.new(tokenName, tokenSymbol);
        this.bond = await fNFTBond.new(bondName, bondSymbol);
        this.manager = await BondManager.new(this.bond.address, this.token.address)

        await this.bond.transferOwnership(this.manager.address)
    })

    /*
    describe("Ownership test", async () => {
        it("Correct ownership for fNFT Bond Contract.", async () => {
            assert.equal(await this.bond.owner(), this.manager.address)
        })
    })
    

    describe("Bond level tests.", async () => {
        
        beforeEach(async () => {
            await this.manager.addBondLevel(this.levelToAdd.name, this.levelToAdd.basePrice, this.levelToAdd.weight, 0)
            const events = await this.bond.getPastEvents('NewBondLevel')
            assert.equal(events.length, 1)
            this.bondLevelAddEvent = events[0].returnValues
        })

        

        it("Create new bond level.", async () => {
            assert.equal(this.bondLevelAddEvent.name, this.levelToAdd.name)
            assert.equal(this.bondLevelAddEvent.weight, this.levelToAdd.weight)
            assert.equal(this.bondLevelAddEvent.basePrice, this.levelToAdd.basePrice)
        })

        it("Verify that bond level has been added to mapping.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            const level = await this.bond.getBondLevel(levelID)

            assert.equal(level.levelID, levelID)
            assert.equal(level.active, true)
            assert.equal(level.basePrice, this.levelToAdd.basePrice)
            assert.equal(level.weight, this.levelToAdd.weight)
            assert.equal(level.name, this.levelToAdd.name)
        })

        it("Verify that bond level has been added to totalActiveBondLevels array.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            const activeLevels = await this.bond.getActiveBondLevels()

            var found = false

            for (var i = 0; i < activeLevels.length; i++) {
                if (levelID == activeLevels[i]) {
                    found = true
                    break
                }
            }

            assert(found, "Bond level is not in totalActiveBondLevels array.")
            assert.equal(activeLevels.length, 5)
        })
        

        it("Verify that bond level can be changed.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            const changedLevel = {
                name: "Level 5",
                basePrice: "20000",
                weight: "120",
                sellableAmount: "0"
            }

            await this.manager.changeBondLevel(levelID, changedLevel.name, changedLevel.basePrice, changedLevel.weight, changedLevel.sellableAmount)

            
            // Checking event

            const events = await this.bond.getPastEvents('BondLevelChanged')

            // Only 1 event must be fired
            assert.equal(events.length, 1)

            const changeLevelEvent = events[0].returnValues


            assert.equal(changeLevelEvent.levelID.substring(0, 10), levelID)
            assert.equal(changeLevelEvent.basePrice, changedLevel.basePrice)
            assert.equal(changeLevelEvent.weight, changedLevel.weight)
            assert.equal(changeLevelEvent.name, changedLevel.name)

            // Checking mapping
            const level = await this.bond.getBondLevel(levelID)

            assert.equal(level.levelID, levelID)
            assert.equal(level.active, true)
            assert.equal(level.basePrice, changedLevel.basePrice)
            assert.equal(level.weight, changedLevel.weight)
            assert.equal(level.name, changedLevel.name)
            assert.equal(level.sellableAmount, changedLevel.sellableAmount)

            //Verify that bond level is still in totalActiveBondLevels array
            const activeLevels = await this.bond.getActiveBondLevels()

            var found = false

            for (var i = 0; i < activeLevels.length; i++) {
                if (levelID == activeLevels[i]) {
                    found = true
                    break
                }
            }

            assert(found, "Bond level is not in totalActiveBondLevels array.")
            assert.equal(activeLevels.length, 5)
            
        })

        

        it("Verify that bond level can be deactivated.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            await this.manager.deactivateBondLevel(levelID)

            // Checking event

            const events = await this.bond.getPastEvents('BondLevelDeactivated')

            // Only 1 event must be fired
            assert.equal(events.length, 1)

            const deactivateLevelEvent = events[0].returnValues

            assert.equal(deactivateLevelEvent.levelID.substring(0, 10), levelID)

            //Check mapping active is false

            assert(!(await this.bond.getBondLevel(levelID)).active, "Mapping active parameter is still true")

            // Check it was removed from totalActiveBondLevels array

            const activeLevels = await this.bond.getActiveBondLevels()

            var found = false

            for (var i = 0; i < activeLevels.length; i++) {
                if (levelID == activeLevels[i]) {
                    found = true
                    break
                }
            }

            assert(!found, "Bond level is in totalActiveBondLevels array.")
        })

        it("Verify that bond level can be activated at index.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            // Mapping must first be disabled in order to re-enable it.
            await this.manager.deactivateBondLevel(levelID)

            const index = 2

            await this.manager.activateBondLevel(levelID, index)

            // Checking event

            const events = await this.bond.getPastEvents('BondLevelActivated')

            // Only 1 event must be fired
            assert.equal(events.length, 1)

            const activatedLevelEvent = events[0].returnValues

            assert.equal(activatedLevelEvent.levelID.substring(0, 10), levelID)

            //Check mapping active is true

            assert((await this.bond.getBondLevel(levelID)).active, "Mapping active parameter is still false")

            // Check it was removed from totalActiveBondLevels array

            const activeLevels = await this.bond.getActiveBondLevels()

            var found = false
            var _index;

            for (var i = 0; i < activeLevels.length; i++) {
                if (levelID == activeLevels[i]) {
                    found = true
                    _index = i
                    break
                }
            }

            assert(found, "Bond level is not in totalActiveBondLevels array.")
            assert.equal(_index, index)
        })

        it("Verify that bond level can be rearranged at index.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            const index = 1

            await this.manager.rearrangeBondLevel(levelID, index)

            const activeLevels = await this.bond.getActiveBondLevels()

            var found = false
            var _index;

            for (var i = 0; i < activeLevels.length; i++) {
                if (levelID == activeLevels[i]) {
                    found = true
                    _index = i
                    break
                }
            }

            assert(found, "Bond level is not in totalActiveBondLevels array.")
            assert.equal(_index, index)
        })
        
       
        it("Verify that a maximum of 10 Bond levels can exist concurrently", async () => {

            const BOND_LEVEL_MAX = 10

            const totalActiveBondLevels = await this.bond.totalActiveBondLevels()

            for (var i = totalActiveBondLevels.toNumber(); i < BOND_LEVEL_MAX; i++) {
                await this.manager.addBondLevel(this.levelToAdd.name + i.toString(), this.levelToAdd.basePrice, this.levelToAdd.weight)
            }

            await this.manager.addBondLevel(this.levelToAdd.name + "A", this.levelToAdd.basePrice, this.levelToAdd.weight, this.levelToAdd.sellableAmount)

            var catched = false

            try {
                await this.manager.addBondLevel(this.levelToAdd.name + "A", this.levelToAdd.basePrice, this.levelToAdd.weight, this.levelToAdd.sellableAmount)
            } catch {
                catched = true
            }

            assert(catched, "User was able to create more Bond levels than allowed.")
            
        })
        
    })
    
   */
/*
    describe("Create bond tests.", async () => {
        beforeEach(async () => {
            await this.manager.linkBondManager();
            await this.token.approve(this.manager.address, "99999999999999999999999999999999999")
        })

        

        it("Check Bond Creation.", async () => {

            const precision = web3.utils.toBN(10).pow(web3.utils.toBN(18))

            // Index of bond level we want to mint in activeBondLevels array. 
            const activeBondLevelIndex = 0

            const levelID = (await this.bond.getActiveBondLevels())[activeBondLevelIndex]
            const price = (await this.manager.getPrice(levelID))[0]

            // Check balance before bond creation.
            const initialBalance = await this.token.balanceOf(accounts[0])

            // Create bonds.
            await this.manager.createMultipleBondsWithTokens(levelID, 1)

            // Get minted bond.
            const bondObj = await this.bond.getBond("0")

            // Check if balance decreased by correct amount
            assert.equal(price, initialBalance.sub(await this.token.balanceOf(accounts[0])).toString())

            // Check bond object values
            assert.equal(bondObj.levelID, levelID);
            assert.equal(bondObj.weight, (await this.bond.getBondLevel(levelID)).weight)
            assert.equal(bondObj.earned, "0")
            assert.equal(bondObj.unweightedShares, price.toString())
            assert.equal(bondObj.weightedShares, web3.utils.toBN(bondObj.weight).mul(price).div(web3.utils.toBN(100)).toString())
            assert.equal(bondObj.rewardDebt, web3.utils.toBN(bondObj.weightedShares).mul(web3.utils.toBN(await this.manager.accRewardsPerWS())).div(precision).toString())
            assert.equal(bondObj.shareDebt, web3.utils.toBN(bondObj.unweightedShares).mul(web3.utils.toBN(await this.manager.accSharesPerUS())).div(precision).toString())
        })
        

        it("Ensure a maximum of 20 bonds can be minted within one transaction.", async() => {
            const activeBondLevelIndex = 0
            const levelID = (await this.bond.getActiveBondLevels())[activeBondLevelIndex]

            var catched = false

            try {
                await this.manager.createMultipleBondsWithTokens(levelID, 21)
            } catch {
                catched = true
            }

            assert(catched, "User was able to create more Bonds than allowed in a single transaction")

        })

        


        
        
    })
*/
    describe("Maths checks", async () => {
        beforeEach(async () => {
            await this.manager.linkBondManager();
            await this.token.approve(this.manager.address, "99999999999999999999999999999999999")
        })

        it("Maths checks", async () => {

            const precision = web3.utils.toBN(10).pow(web3.utils.toBN(18))

            var levels = [{US: 10 , WS: 10}, {US: 100, WS: 105}, {US: 1000, WS: 1100}, {US: 5000, WS: 5750}]

            /*
                Mint:
                    - 2 Level 4 bonds - US: 10,000, WS: 11,500
                    - 2 Level 3 bonds - US: 2,000, WS: 2,200
                    - 5 Level 2 bonds - US: 500, WS: 525
                    - Total - US: 12,500, WS: 14,225
            */

            var totalUS = levels[3].US * 2 + levels[2].US * 2 + levels[1].US * 5
            var totalWS = levels[3].WS * 2 + levels[2].WS * 2 + levels[1].WS * 5

            const activeLevels = await this.bond.getActiveBondLevels()

            await this.manager.createMultipleBondsWithTokens(activeLevels[3], 2)
            await this.manager.createMultipleBondsWithTokens(activeLevels[2], 2)
            await this.manager.createMultipleBondsWithTokens(activeLevels[1], 5)

            // Check there are a total amount of 9 bonds.
            //assert.equal(await this.bond.totalSupply(), 9)

            // Check if total amount of shares is exact.
            //assert.equal((await this.manager.totalUnweightedShares()).toString(), web3.utils.toBN(totalUS).mul(precision).toString())
            //assert.equal((await this.manager.totalWeightedShares()).toString(), web3.utils.toBN(totalWS).mul(precision).toString())

            // Deposit rewards
            // Function is called by user but it should be called by treausury, yet test isn't affected, as this tests mathematics.

            /*
                Total rewards:
                    - Token rewards: 1,000 tokens.
                    - Shares rewards: 1,000 shares.

                Individual rewards (Tokens):
                    - Level 4: 5750 / 14225 * 1000 = 404.22
                    - Level 3: 1100 / 14225 * 1000 = 77.33
                    - Level 2: 105 / 14225 * 1000 = 7.38

                Individual rewards (Shares):
                    - Level 4: 5000 / 12500 * 1000 = 400.00
                    - Level 3: 1000 / 12500 * 1000 = 80.00
                    - Level 2: 100 / 12500 * 1000 = 8.00

                New individual bonds US:
                    - Level 4: 5000 + 400 = 5400
                    - Level 3: 1000 + 80 = 1080
                    - Level 2: 100 + 8 = 108

                New individual bonds WS:
                    - Level 4: 5750 + 400 * 1.15 = 6210
                    - Level 3: 1100 + 80 * 1.10 = 1188
                    - Level 2: 105 + 8 * 1.05 = 113.4

                New total protocol shares (if all users claim):
                    - US: 5400 * 2 + 1080 * 2 + 108 * 5 = 13,500
                    - WS: 6210 * 2 + 1188 * 2 + 113.4 * 5 = 15,363
            */

            await this.manager.depositRewards(web3.utils.toBN(1000).mul(precision), web3.utils.toBN(1000).mul(precision))

            /*
            const rewardBN = BN(1000).mul(precision)
            const totalUSBN = await this.manager.totalUnweightedShares()
            const totalWSBN = await this.manager.totalWeightedShares()

            for(var i = 0; i < 3; i++) {
                const USBN = BN((await this.bond.getBond(1 + (i * 2))).unweightedShares)
                const WSBN = BN((await this.bond.getBond(1 + (i * 2))).weightedShares)

                const claimableShares = (await this.manager.getClaimableAmounts(1 + (i * 2)))[0].toString()
                const claimableRewards = (await this.manager.getClaimableAmounts(1 + (i * 2)))[1].toString()

                //.substring(0, 14) is used to disregard BN precision errors in the calculations.

                assert.equal(claimableShares.substring(0, 14), USBN.mul(rewardBN).div(totalUSBN).toString().substring(0, 14))
                assert.equal(claimableRewards.substring(0, 14), WSBN.mul(rewardBN).div(totalWSBN).toString().substring(0, 14))
            }

            */

            // Claim all bonds
            await this.manager.claimAll()

            // Increase level shares and total shares
            levels = [{US: 10 , WS: 10}, {US: 108, WS: 113.4}, {US: 1080, WS: 1188}, {US: 5400, WS: 6210}]

            totalUS = levels[3].US * 2 + levels[2].US * 2 + levels[1].US * 5
            totalWS = levels[3].WS * 2 + levels[2].WS * 2 + levels[1].WS * 5

            // Check if total shares have increased by the correct amount
            assert.equal((await this.manager.totalUnweightedShares()).toString(), BN(totalUS).mul(precision).toString())
            assert.equal((await this.manager.totalWeightedShares()).toString(), BN(totalWS).mul(precision).toString())
            
        })
    })
})

function BN(n) {
    return web3.utils.toBN(n)
}