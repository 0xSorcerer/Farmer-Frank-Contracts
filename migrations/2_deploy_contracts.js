
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

    //deployer.deploy(ERC20, "JOE", "JOE")

    
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    await deployer.deploy(BondManager, fNFTBond.address, "0x202358975315f4c5E210d9b8520104C566BFd5d3")

    const bond = await fNFTBond.deployed()

    await bond.setBondManager(BondManager.address)
    await bond.transferOwnership(BondManager.address)
    
    

}