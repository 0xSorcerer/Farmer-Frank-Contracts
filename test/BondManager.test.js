const Web3 = require('web3')
const web3 = new Web3()

var fNFTBond = artifacts.require('fNFTBond')
var BondManager = artifacts.require('BondManager')

contract("BondManager", async (accounts) => {

    const name = 'fNFT Bond - (JOE)'
    const symbol = 'fNFTB01'

    beforeEach(async () => {
        this.bond = await fNFTBond.new(name, symbol);
    })
    
    it("Correct name.", async () => {
        assert.equal(await this.instance.name(), name);
    })

    it("Correct symbol.", async () => {
        assert.equal(await this.instance.symbol(), symbol);
    })

    it("Correct level count.", async () => {
        assert.equal(Object.values(await this.instance.getActiveBondLevels()).length, initialLevels.length)
    })
    
    it("Correct levels.", async () => {
        const activeLevels = Object.values(await this.instance.getActiveBondLevels())

        for(var i = 0; i < initialLevels.length; i++) {
            const level = await this.instance.getBondLevel(activeLevels[i])

            assert.equal(level.levelID, activeLevels[i])
            assert.equal(level.active, true)
            assert.equal(level.basePrice, initialLevels[i].basePrice)
            assert.equal(level.weight, initialLevels[i].weight)
            assert.equal(level.name, initialLevels[i].name)
        }
    })
    
})