const HDWalletProvider = require('@truffle/hdwallet-provider')


const env = require('../.env.json')

const Web3 = require('web3')
const web3 = new Web3(new HDWalletProvider(env.AVAX_PRIVATE_KEY, env.AVAX_API))

const abi = require('../build/contracts/fNFTBond.json').abi;

const init = async () => {
    const c = new web3.eth.Contract(abi, "0x1266Ec0B642520A1feb556A15Db127e74d304063")
    //console.log(await c.methods.getActiveBondLevels().call())
    //console.log(await c.methods.mintBonds("0x60BC62E16fB6A96E68DE1a90cA88E9901e05C634", "0x951ab8c7", "5", "100000000000000").send({from: "0x60BC62E16fB6A96E68DE1a90cA88E9901e05C634"}))
    //console.log(await c.methods.symbol(0).call())
    //await c.methods.setURI("https://ipfs.io/ipfs/QmfRk6W7dnZfZrBzxdZxMUJxDVERMLKwm1xiaGwEJYVJjY", 0).send({from: "0x60BC62E16fB6A96E68DE1a90cA88E9901e05C634"})
    //console.log(await c.methods.tokenURI("10").call())
    //await c.methods.setBaseURI("QmcB9HfMiASd2Yh3S2JrPE6t9JEAUi2y2LAkMCBnnjdhXG").send({from: "0x60BC62E16fB6A96E68DE1a90cA88E9901e05C634"})
    console.log(await c.methods.mintBonds("0xb690Bb5A5008fdC7E78724475F0855F681920f4d", (await c.methods.getActiveBondLevels().call())[0], "1", "100000000000000").send({from: "0xb690Bb5A5008fdC7E78724475F0855F681920f4d"}))
    console.log(await c.methods.tokenURI("0").call())
}

init()
