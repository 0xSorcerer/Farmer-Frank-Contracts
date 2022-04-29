const Web3 = require('web3')
const web3 = new Web3()

const ethers = require('ethers')

const truffleAssert = require('truffle-assertions');
const { isTypeValueInput } = require('truffle/build/459.bundled');

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
        weight: "120"
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
*/
    describe("Bond level tests.", async () => {

        beforeEach(async () => {
            await this.manager.addBondLevel(this.levelToAdd.name, this.levelToAdd.basePrice, this.levelToAdd.weight)
            const events = await this.bond.getPastEvents('NewBondLevel')
            assert.equal(events.length, 1)
            this.bondLevelAddEvent = events[0].returnValues
        })
/*
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
                weight: "120"
            }

            await this.manager.changeBondLevel(levelID, changedLevel.name, changedLevel.basePrice, changedLevel.weight)

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
*/
        it("Verify that a maximum of 10 Bond levels can exist concurrently", async () => {

            const BOND_LEVEL_MAX = 10

            const totalActiveBondLevels = await this.bond.totalActiveBondLevels()

            for (var i = totalActiveBondLevels.toNumber(); i < BOND_LEVEL_MAX; i++) {
                await this.manager.addBondLevel(this.levelToAdd.name + i.toString(), this.levelToAdd.basePrice, this.levelToAdd.weight)
            }

            await this.manager.addBondLevel(this.levelToAdd.name + "A", this.levelToAdd.basePrice, this.levelToAdd.weight)

            /*

            var catched = false

            try {
                await this.manager.addBondLevel(this.levelToAdd.name + "A", this.levelToAdd.basePrice, this.levelToAdd.weight)
            } catch {
                catched = true
            }

            assert(catched, "User was able to create more Bond levels than allowed.")
            */
        })
    })
})