const Web3 = require('web3')
const web3 = new Web3()

var fNFTBond = artifacts.require('fNFTBond')
var BondManager = artifacts.require('BondManager')
var ERC20 = artifacts.require('ERC20')

contract("BondManager", async (accounts) => {

    const tokenName = "JOE"
    const tokenSymbol = "JOE"
    const bondName = 'fNFT Bond - (JOE)'
    const bondSymbol = 'fNFTB01'

    const tokenBalance = "10000000000000000000000000" //10^25
    
    beforeEach(async () => {
        this.token = await ERC20.new(tokenName, tokenSymbol);
        this.bond = await fNFTBond.new(bondName, bondSymbol);
        this.manager = await BondManager.new(this.bond.address, this.token.address)
    })  

    it("Correct user balance.", async () => {
        assert.equal(await this.token.balanceOf(accounts[0]), tokenBalance)
    })

    it("Correct user.", async () => {
        console.log(this.manager.address)
    })


    
})