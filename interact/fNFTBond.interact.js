const HDWalletProvider = require('@truffle/hdwallet-provider')


const env = require('../.env.json')

const Web3 = require('web3')
const web3 = new Web3(new HDWalletProvider(env.KOVAN_KEY, "https://kovan.infura.io/v3/c63564d5fad8416ba9fddb16007a737c"))

const fNFTBondABI = require('../build/contracts/fNFTBond.json').abi;
const ERC20ABI = require('../build/contracts/ERC20.json').abi;
const BondManagerABI = require('../build/contracts/BondManager.json').abi;
const TreasuryABI = require('../build/contracts/FrankTreasury.json').abi;

const init = async () => {

    const address = "0xb3304A14F01Cb5C22E6f5E9fd55b6b6c826e8cc7"
/*
    const address = "0xb690Bb5A5008fdC7E78724475F0855F681920f4d"

    const bondAddress = "0x89a92cb19Baaaee5098Cb92e3AcC301887397C50"
    const tokenAddress = "0x706Ccf8c25BA5fdd00bCfe9765e0FF35cc8e6C99"
    const managerAddress = "0xf42EA7F3F1eCD01Db779f5E222FfD24fcbbAE3d9"

    const bond = new web3.eth.Contract(fNFTBondABI, bondAddress)
    const token = new web3.eth.Contract(ERC20ABI, tokenAddress)
    const manager = new web3.eth.Contract(BondManagerABI, managerAddress)

    //await bond.methods.transferOwnership(managerAddress).send({from: address})

    console.log(await bond.methods.getActiveBondLevels().call())
    */

    const c = new web3.eth.Contract(TreasuryABI, "0xa2EE02a3A7cD4592e33174b8C159c593E877F977")
    //console.log(await c.methods.approve("0x706b4f0Bf3252E946cACD30FAD779d4aa27080c0", "999999999999999999999999999999999999").send({from: "0xb3304A14F01Cb5C22E6f5E9fd55b6b6c826e8cc7"}))
    console.log(await c.methods._addAndFarmLiquidity("100000000000000000000", "0x706b4f0Bf3252E946cACD30FAD779d4aa27080c0").send({from: address}))
}

init()
