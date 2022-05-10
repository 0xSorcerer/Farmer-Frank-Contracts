
const fNFTBond = artifacts.require('fNFTBond')
const BondManager = artifacts.require('BondManager')
const ERC20 = artifacts.require('ERC20')
const StableJoeStaking = artifacts.require('StableJoeStaking.sol')
const VeERC20 = artifacts.require('VeJoeToken.sol')
const VeJoeStaking = artifacts.require('VeJoeStaking.sol')

const FrankTreasury = artifacts.require('FrankTreasury.sol')


module.exports = async (deployer) => {

    await deployer.deploy(FrankTreasury)
    const treasury = await FrankTreasury.deployed()
    
    await deployer.deploy(fNFTBond, "fNFT Bond", "fNFTB")
    await deployer.deploy(BondManager, fNFTBond.address, "0x1217686124AA11323cC389a8BC39C170D665370b", FrankTreasury.address)

    const bond = await fNFTBond.deployed()
    const manager = await BondManager.deployed()

    await bond.transferOwnership(BondManager.address)
    await manager.linkBondManager()

    await treasury.setBondManager(BondManager.address)
}