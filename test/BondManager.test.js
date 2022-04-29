const Web3 = require('web3')
const web3 = new Web3()

const ethers = require('ethers')

const truffleAssert = require('truffle-assertions');

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

    

    describe("Ownership test", async () => {
        it("Correct ownership for fNFT Bond Contract.", async () => {
            assert.equal(await this.bond.owner(), this.manager.address)
        })
    })

    


    describe("Bond level testing", async () => {

        beforeEach(async () => {
            await this.manager.addBondLevel(this.levelToAdd.name, this.levelToAdd.basePrice, this.levelToAdd.weight)
            const events = await this.bond.getPastEvents('NewBondLevel')
            assert.equal(events.length, 1)
            this.bondLevelAddEvent = events[0].returnValues
        })

        
        /*

        it("Create bond", async () => {

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

            for(var i = 0; i < activeLevels.length; i++) {
                if(levelID == activeLevels[i]) {
                    found = true
                    break
                }
            }

            assert(found, "Bond level is not in totalActiveBondLevels array.")
            assert.equal(activeLevels.length, 5)
        })

        */

        it("Verify that bond level can be changed.", async () => {
            const levelID = this.bondLevelAddEvent.levelID.substring(0, 10)

            const changedLevel = {
                name: "Level 5",
                basePrice: "20000",
                weight: "120"
            }    

            await this.bond.changeBondLevel(levelID, changedLevel.name, changedLevel.basePrice, changedLevel.weight)

            const events = await this.bond.getPastEvents('BondLevelChanged')

            console.log(events)
        })

    })
    
    
    
})