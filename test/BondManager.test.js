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
        })

        it("Create bond", async () => {
            const events = await this.bond.getPastEvents('NewBondLevel')
            assert.equal(events.length, 1)

            const event = events[0].returnValues
            this.levelToAddID = events[0].returnValues.levelID.substring(0, 9)

            assert.equal(event.name, this.levelToAdd.name)
            assert.equal(event.weight, this.levelToAdd.weight)
            assert.equal(event.basePrice, this.levelToAdd.basePrice)
        })

        it("Verify bond", async () => {
            console.log(this.levelToAddID)
        })
    })
    
    
    
})