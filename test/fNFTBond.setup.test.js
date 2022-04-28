const Web3 = require('web3')
const web3 = new Web3()

var fNFTBond = artifacts.require('fNFTBond')

contract("fNFTBond", async (accounts) => {

    const name = 'fNFT Bond - (JOE)'
    const symbol = 'fNFTB01'

    const initialLevels = [
        {
            index: "0",
            name: "Level I",
            basePrice: "10",
            weight: "100"
        },
        {
            index: "1",
            name: "Level II",
            basePrice: "100",
            weight: "105"
        },
        {
            index: "2",
            name: "Level III",
            basePrice: "1000",
            weight: "110"
        },
        {
            index: "3",
            name: "Level IV",
            basePrice: "5000",
            weight: "115"
        }
    ]

    beforeEach(async () => {
        this.instance = await fNFTBond.new(name, symbol);
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