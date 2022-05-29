
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')

const FrankTreasury = artifacts.require('FrankTreasury.sol')

const ERC20 = artifacts.require('ERC20.sol')


/*
module.exports = async (deployer) => {

    await deployer.deploy(FrankTreasury)
    const treasury = await FrankTreasury.deployed()
    
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    await deployer.deploy(BondManager, fNFTBond.address, "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd", FrankTreasury.address)

    const bond = await fNFTBond.deployed()
    const manager = await BondManager.deployed()

    await bond.transferOwnership(BondManager.address)
    await manager.linkBondManager()

    await treasury.setBondManager(BondManager.address)
}
*/


module.exports = async (deployer) => {

    //await deployer.deploy(ERC20, "JOE", "JOE")

    await deployer.deploy(FrankTreasury)

    const treasury = await FrankTreasury.deployed()
    
    
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    await deployer.deploy(BondManager, fNFTBond.address, "0x1217686124AA11323cC389a8BC39C170D665370b", treasury.address)

    const bond = await fNFTBond.deployed()
    const manager = await BondManager.deployed()

    await bond.setBondManager(BondManager.address)
    await bond.transferOwnership(BondManager.address)

    await treasury.setBondManager(manager.address)
    
}